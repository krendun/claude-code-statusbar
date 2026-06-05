#!/usr/bin/env bash
# hooks/post-tool-use.sh
# Fires after every Claude Code tool call.
# Clears the active-mode flag after a 30-second delay so the wave
# animation continues during brief pauses between tool calls
# (e.g. during a multi-step workflow), but eventually returns
# to idle shimmer once Claude is genuinely done.

(
    sleep 30
    # Only remove if no new tool use has touched the flag in the last 30s
    # (file mtime check: if it's older than 28s, it's safe to remove)
    if [ -f /tmp/claude-active-task ]; then
        MTIME=$(stat -f %m /tmp/claude-active-task 2>/dev/null \
             || stat -c %Y /tmp/claude-active-task 2>/dev/null \
             || echo 0)
        NOW=$(date +%s)
        AGE=$(( NOW - MTIME ))
        [ "$AGE" -ge 28 ] && rm -f /tmp/claude-active-task
    fi
) &
disown
