import Foundation
import Speech
import AVFoundation

// Phase 117:语音录入 —— 「记一条」的麦克风按钮。
// 直接用系统 SFSpeechRecognizer(跟随系统语言,中文环境即中文识别),
// 实时流式把识别文本写进 transcript,调用方绑定到草稿框。

@MainActor
@Observable
final class SpeechInput {

    /// 正在录音识别中。
    private(set) var isRecording = false
    /// 实时识别结果(每次开始录音时清空)。
    private(set) var transcript = ""
    /// 权限被拒 → UI 显示提示行。
    private(set) var permissionDenied = false

    private let recognizer = SFSpeechRecognizer()  // 跟随系统 locale
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let engine = AVAudioEngine()

    /// 切换录音状态(按钮点击入口)。
    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func start() {
        permissionDenied = false
        SFSpeechRecognizer.requestAuthorization { auth in
            DispatchQueue.main.async {
                guard auth == .authorized else {
                    self.permissionDenied = true
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.permissionDenied = true
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            permissionDenied = true
            return
        }
        transcript = ""
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            NSLog("[Whereabouts] speech session failed: %@", String(describing: error))
            stop()
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
