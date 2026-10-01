import Foundation
import Speech
import AVFoundation

// Phase 117:语音录入 —— 「记一条」的麦克风按钮。
// 直接用系统 SFSpeechRecognizer(跟随系统语言,中文环境即中文识别),
// 实时流式把识别文本写进 transcript,调用方绑定到草稿框。
//
// Phase 122:健壮性 ——
//   - 权限申请是异步的:isStarting 防止期间重复开局;每轮一个 sessionID,
//     权限回调 / 识别回调都核对它,作废轮次(取消、上一轮)的晚到回调一律丢弃
//   - installTap 前先 removeTap(残留 tap 重复 install 会直接崩);输入格式 0 Hz / 0 声道时不开局
//   - stop() 是"优雅停":停音频后等识别器把最终结果送回来;cancel() 是"硬停"(提交 / 离开页面用)
//   - 识别服务不可用 与 权限被拒 分开提示
//   - 来电等音频会话中断 → 优雅停止

@MainActor
@Observable
final class SpeechInput {

    /// 正在录音识别中。
    private(set) var isRecording = false
    /// 实时识别结果(每次开始录音时清空)。
    private(set) var transcript = ""
    /// 权限被拒 → UI 显示提示行。
    private(set) var permissionDenied = false
    /// Phase 122:识别服务 / 麦克风暂不可用(无网络、语言不支持、无输入设备……)→ 另一条提示。
    private(set) var unavailable = false

    private let recognizer = SFSpeechRecognizer()  // 跟随系统 locale
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let engine = AVAudioEngine()

    /// Phase 122:权限申请进行中(两步都是异步回调)。
    private var isStarting = false
    /// Phase 122:每次开局 / 作废 +1;回调里核对,不是当前轮的直接丢弃。
    private var sessionID = 0
    /// Phase 122:本类是否激活了音频会话(只停自己开的)。
    private var audioActive = false
    /// Phase 122:音频会话中断监听(录音期间才挂)。
    private var interruptionObserver: NSObjectProtocol?

    /// 切换录音状态(按钮点击入口)。
    func toggle() {
        if isRecording || isStarting { stop() } else { start() }
    }

    func start() {
        guard !isRecording, !isStarting else { return }
        // 上一轮优雅停止后可能还在等最终结果 —— 作废它,免得晚到的结果盖掉新一轮。
        if task != nil { cancel() }
        isStarting = true
        permissionDenied = false
        unavailable = false
        sessionID += 1
        let session = sessionID
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                guard self.isStarting, self.sessionID == session else { return }
                guard auth == .authorized else {
                    self.isStarting = false
                    self.permissionDenied = true
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard self.isStarting, self.sessionID == session else { return }
                        guard granted else {
                            self.isStarting = false
                            self.permissionDenied = true
                            return
                        }
                        self.beginSession(session)
                    }
                }
            }
        }
    }

    private func beginSession(_ session: Int) {
        isStarting = false
        guard let recognizer, recognizer.isAvailable else {
            // 识别服务不可用(不是权限问题)—— 单独提示。
            unavailable = true
            return
        }
        transcript = ""
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            audioActive = true

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // 没有可用输入时格式是 0 Hz / 0 声道,installTap 会直接抛 ObjC 异常崩溃。
            guard format.sampleRate > 0, format.channelCount > 0 else {
                unavailable = true
                stopAudio()
                return
            }

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            // 上一轮异常退出可能残留 tap;同一 bus 重复 install 会崩。
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            observeInterruptions()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                DispatchQueue.main.async {
                    // 作废轮次(cancel 过 / 已开新一轮)的晚到回调一律丢弃。
                    guard let self, self.sessionID == session else { return }
                    if let text { self.transcript = text }
                    if failed || isFinal { self.finishSession() }
                }
            }
        } catch {
            NSLog("[Whereabouts] speech session failed: %@", String(describing: error))
            unavailable = true
            cancel()
        }
    }

    /// 优雅停:停音频、告诉识别器"说完了",最终结果仍会经回调送回 transcript。
    func stop() {
        if isStarting && !isRecording {
            // 还在等权限 → 直接作废这一轮
            cancel()
            return
        }
        guard isRecording else { return }
        stopAudio()
        request?.endAudio()
        task?.finish()
        isRecording = false
    }

    /// Phase 122:硬停 —— 提交 / 离开页面 / 退后台时用。作废本轮,之后的回调一律丢弃,
    /// 已提交的文字不会被晚到的识别结果写回草稿。
    func cancel() {
        sessionID += 1
        isStarting = false
        stopAudio()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
    }

    /// 识别结束(最终结果 / 出错):收尾。
    private func finishSession() {
        stopAudio()
        task = nil
        request = nil
        isRecording = false
    }

    /// 停引擎 + 摘 tap + 摘中断监听 + 释放自己开的音频会话。可重复调用。
    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if audioActive || isRecording {
            engine.inputNode.removeTap(onBus: 0)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if audioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioActive = false
        }
    }

    /// 来电 / Siri / 闹钟等打断音频会话 → 优雅停止(已识别的文字保留)。
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }
}
