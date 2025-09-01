#!/bin/bash
# Claude Code Automation Hook for this project

AUTOMATION_SCRIPT="/Users/charleskrivan/.claude/automation/claude-quality.sh"
FILE_PATH="$1"

if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    export PATH="$HOME/.npm-global/bin:$PATH"
    "$AUTOMATION_SCRIPT" run "$FILE_PATH"
fi
