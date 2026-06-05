# Prompt 02 — Full Build

Run this prompt in the same session as 01-payload-dump.md, after you 
have the raw payload output (and optionally your usage screenshot) in 
context. Claude will use the confirmed field names rather than guessing.

---

## The prompt

```
Using the payload field names we just confirmed, build the full status 
bar from scratch using the statusline hook. Replace the debug script.

LAYOUT (left to right, single line):
[branch info] | [5h bar] | [15h bar] | [7d bar] | [ctx bar + countdown] | [model] [time]

FIELD NAMES:
Use the exact field names confirmed from the payload dump for all 
rate-limit windows and the ctx reset timestamp.
- If the 15h window was not present in the payload, skip it entirely — 
  no placeholder, no empty bar.
- If the ctx reset timestamp was not present, omit the countdown — 
  no ↺ symbol, no placeholder.
- Apply countdown timers to ANY rate-limit bar where a reset timestamp 
  is present in the payload, not just ctx.

METRICS AND COLORS:
1. 5h usage — label "5h", muted steel blue bar fill
   (#4a9eff at ~60% brightness, not full saturation)

2. 15h usage — label "15h", muted amber bar fill
   (#e8a045 at ~60% brightness)
   Only include if confirmed present in payload.

3. 7d usage — label "7d", muted violet bar fill
   (#9b6dff at ~60% brightness)

4. ctx — label "ctx", muted teal bar fill
   (#4ecdc4 at ~60% brightness)
   If reset timestamp confirmed in payload, append
   countdown: "↺ Xh Xm" after the percentage.

DUAL ANIMATION MODE:

CRITICAL — USE WALL-CLOCK TIME FOR ALL ANIMATION FRAMES.
Do NOT use a counter that increments by 1 per redraw. The statusline
hook is called every 2-3 seconds by Claude Code's runtime; a
counter-based approach makes animation crawl. Instead, compute the
current frame from the system clock on every render so the animation
jumps to the correct position regardless of refresh rate.

Implementation — get milliseconds at render time:
  MS=$(date +%s%3N)

Idle mode (no prompt being processed):
- Frame = (MS / 2000) % 2
- Frame 0: rightmost filled character = █
- Frame 1: rightmost filled character = ▓
- Toggles every 2 seconds, correct position on every redraw

Active mode detection — four conditions (any one = wave):
1. Redraw cadence < 400ms (primary signal — lowered from 800ms)
   - On each redraw, record timestamp to /tmp/statusline-last-call
   - Compare to previous stored timestamp
   - If interval < 400ms → active
2. total_output_tokens delta (secondary)
   - If context_window.total_output_tokens increased since last
     draw → active
   - NOTE: is_streaming and processing do not exist in the real
     payload — do not reference them
3. Active workflow or task in payload
   - Check payload fields: tasks, workflows, background_tasks,
     agents, running_tasks
   - If any entry has status matching "running", "active",
     "in_progress", "pending", or "executing" → active
4. Flag file exists: /tmp/claude-active-task → active

Transition:
- Into active: instant on first condition firing
- Out of active: only when ALL four conditions are false simultaneously
  (prevents flickering during brief pauses in long runs)

Active mode animation — time-based traveling wave:
- Wave sequence (7 chars, indices 0–6): ░ ▒ ▓ █ ▓ ▒ ░
- Current wave offset = (MS / 250) % 7  (advances every 250ms)
- For each character position i in the bar:
    char = WAVE_SEQUENCE[ (wave_offset + i) % 7 ]
- Wave spans the FULL bar width, not just the filled portion
- All bars use the SAME wave_offset — synchronized, same phase
- At a 2s refresh interval this jumps 8 positions forward
  (visually clear movement); at faster rates it's smooth

HOOKS (wire these automatically):
- PreToolUse hook: touch /tmp/claude-active-task
- PostToolUse hook: check payload for active workflows; if none 
  found OR payload field doesn't exist, remove the file after 
  a 30s delay via background process

COLOR THRESHOLDS (all bars):
- 0–60%: base muted color for that metric
- 60–85%: shift to muted amber warning tone (#e8a045 at ~60%)
- 85–100%: shift to muted red (#cc4444 at ~70% brightness)
- Never use full-saturation colors at any threshold

SEPARATOR: single dim │ between each metric group

MODEL + TIME:
- Model name as-is (e.g. "Opus 4.8")
- 12hr format with AM/PM, no seconds (e.g. "10:49 PM")

GENERAL:
- No ALL CAPS labels
- Dim branch/path info so metrics are the focal point
- Keep total line width under 120 chars; drop 15h last if wrapping

After building:
- Confirm which payload field (if any) triggered condition 3
- Confirm the hook config that was written and the exact file paths 
  for statusline-command.sh and both hook scripts
- Show test renders of both idle and active modes side by side
```

---

## After the build completes

Claude Code will tell you the exact paths for the generated files. 
Copy them into this repo:

```bash
# Claude Code will give you the exact source paths
cp ~/.claude/statusline-command.sh ./statusline-command.sh
cp [hook-path]/pre-tool-use.sh ./hooks/pre-tool-use.sh
cp [hook-path]/post-tool-use.sh ./hooks/post-tool-use.sh
```

Then commit:

```bash
git add .
git commit -m "add generated statusline script and hooks"
git push
```
