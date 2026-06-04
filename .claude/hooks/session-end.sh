#!/bin/bash
# ADXSCORE: SessionEnd hook
# 自動スナップショットを書き出し、latest.md が無ければそれで埋める

cd "${CLAUDE_PROJECT_DIR}" || exit 0

STATE_DIR="data/session_state"
mkdir -p "$STATE_DIR/archive"

TS=$(date +%Y-%m-%d_%H%M)
SNAPSHOT="$STATE_DIR/archive/${TS}.md"

{
  echo "# 自動スナップショット ($(date '+%Y-%m-%d %H:%M'))"
  echo ""
  echo "## Git Status (短縮)"
  echo '```'
  git status --short 2>/dev/null | head -30
  echo '```'
  echo ""
  echo "## 直近24h 変更ファイル"
  echo '```'
  find data signals docs scripts -type f -mtime -1 ! -path '*/.git/*' 2>/dev/null | head -30
  echo '```'
  echo ""
  echo "## CLAUDE.md の Stage 進捗"
  echo '```'
  grep -E "^#### Stage [0-9]" CLAUDE.md 2>/dev/null
  echo '```'
  echo ""
  echo "## 最新コミット5件"
  echo '```'
  git log --oneline -5 2>/dev/null
  echo '```'
} > "$SNAPSHOT"

# latest.md が無ければ、このスナップショットで埋める
# Claude が手動更新した場合は触らない（あろさん運用に応じて Claude が latest.md を書く）
if [ ! -f "$STATE_DIR/latest.md" ]; then
  cp "$SNAPSHOT" "$STATE_DIR/latest.md"
fi
