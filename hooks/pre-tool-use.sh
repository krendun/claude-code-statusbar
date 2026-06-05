#!/usr/bin/env bash
# hooks/pre-tool-use.sh
# Fires before every Claude Code tool call.
# Sets the active-mode flag so the status bar wave animation
# starts immediately when Claude begins any tool use.
# _

touch /tmp/claude-active-task
