#!/bin/bash
# 何处数据恢复:遍历 Time Machine 本地快照,找出仍含 ZITEM 数据的 default.store,
# 用 sqlite backup 合并 WAL 后存到新版专用路径。需要 sudo(挂载快照)。
set -u
MNT=/tmp/hechu-tmsnap
DEST_DIR="$HOME/Library/Application Support/Whereabouts"
DEST="$DEST_DIR/whereabouts.store"
KEEP_DIR="$HOME/Desktop/hechu-recovered"
mkdir -p "$MNT" "$KEEP_DIR"

BEST_FILE=""
BEST_COUNT=-1
BEST_SNAP=""

# 从最旧到最新逐个查(被覆盖前的最后一份 = 最新的仍有数据的快照)
for SNAP in $(tmutil listlocalsnapshots / | grep TimeMachine | sed 's/com.apple.TimeMachine.//;s/.local//' | sort); do
  mount_apfs -o rdonly -s "com.apple.TimeMachine.$SNAP.local" /System/Volumes/Data "$MNT" 2>/dev/null || { echo "跳过 $SNAP(挂载失败)"; continue; }
  F="$MNT/Users/bamcope/Library/Application Support/default.store"
  if [ -f "$F" ]; then
    HAS=$(sqlite3 "file:$F?immutable=1" "SELECT name FROM sqlite_master WHERE name='ZITEM';" 2>/dev/null)
    if [ -n "$HAS" ]; then
      CNT=$(sqlite3 "file:$F?immutable=1" "SELECT COUNT(*) FROM ZITEM;" 2>/dev/null || echo 0)
      echo "$SNAP → 有 ZITEM,物品 $CNT 条"
      if [ "$CNT" -ge "$BEST_COUNT" ]; then
        # 用 backup 把主库+WAL 合并成单文件快照副本
        sqlite3 "file:$F?immutable=1" ".backup '$KEEP_DIR/store-$SNAP.sqlite'" 2>/dev/null \
          && { BEST_FILE="$KEEP_DIR/store-$SNAP.sqlite"; BEST_COUNT=$CNT; BEST_SNAP=$SNAP; }
      fi
    else
      echo "$SNAP → 已被覆盖(无 ZITEM)"
    fi
  else
    echo "$SNAP → 无 default.store"
  fi
  umount "$MNT" 2>/dev/null
done

echo "--------------------------------------"
if [ -n "$BEST_FILE" ]; then
  mkdir -p "$DEST_DIR"
  cp "$BEST_FILE" "$DEST"
  # 归属修正(sudo 跑的,把文件还给用户)
  chown "$SUDO_USER":staff "$DEST" "$KEEP_DIR"/store-*.sqlite 2>/dev/null
  chown "$SUDO_USER":staff "$DEST_DIR" 2>/dev/null
  echo "✅ 恢复完成:用快照 $BEST_SNAP 的数据($BEST_COUNT 件物品)"
  echo "   已安装到新版专用路径:$DEST"
  echo "   备份副本在:$KEEP_DIR/"
else
  echo "❌ 本地快照里都没找到含数据的库。如果有外接 Time Machine 硬盘,插上后再跑一次本脚本。"
fi
