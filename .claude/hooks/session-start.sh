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

# additionalContext として Claude に渡す
jq -n --arg ctx "── 前回セッションからの引き継ぎ (data/session_state/latest.md) ──

$CONTENT

──────────────────────────────────────" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
