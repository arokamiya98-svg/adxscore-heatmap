#!/bin/bash
# ADXSCORE: SessionStart hook
# data/session_state/latest.md を Claude のセッション context に注入

LATEST="${CLAUDE_PROJECT_DIR}/data/session_state/latest.md"

if [ ! -f "$LATEST" ]; then
  exit 0
fi

CONTENT=$(cat "$LATEST")

if [ -z "$CONTENT" ]; then
  exit 0
fi

# additionalContext として Claude に渡す（Python で JSON 構築、jq 依存なし）
LATEST_PATH="$LATEST" python3 <<'PYEOF'
import json, os
with open(os.environ["LATEST_PATH"], encoding="utf-8") as f:
    content = f.read()
ctx = (
    "── 前回セッションからの引き継ぎ (data/session_state/latest.md) ──\n\n"
    + content
    + "\n\n──────────────────────────────────────"
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}, ensure_ascii=False))
PYEOF
