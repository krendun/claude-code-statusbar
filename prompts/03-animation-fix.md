# Prompt 03 — Animation Fix (existing users)

Run this if your status bar animation looks choppy or only moves every 
few seconds. This does NOT rebuild the bar from scratch — it patches 
only the animation logic in your existing `statusline-command.sh`.

---

## Why animation feels slow

Claude Code calls the statusline hook on its own internal timer, 
typically every 2-3 seconds. If the script advances the wave by one 
step per call, it crawls. The fix is switching to wall-clock time so 
the script computes which frame *should* be showing right now — 
jumping to the correct position on every render instead of 
incrementing by one.

---

## The prompt

```
Update the animation logic in my existing statusline-command.sh.
Do NOT change colors, layout, thresholds, or active-mode detection.
Change the animation implementation only.

CORE CHANGE — switch from counter-based to time-based frames:

Get milliseconds at render time:
  MS=$(date +%s%3N)

Idle shimmer (replace existing implementation):
- Frame = (MS / 2000) % 2
- Frame 0: rightmost filled character = █
- Frame 1: rightmost filled character = ▓
- Result: correct toggle position on every render regardless of 
  how often the hook is called

Active wave (replace existing implementation):
- Wave sequence (7 characters, indices 0–6): ░ ▒ ▓ █ ▓ ▒ ░
- Wave offset = (MS / 250) % 7
- For each character position i in the bar:
    character = WAVE_SEQUENCE[ (wave_offset + i) % 7 ]
- All bars use the SAME wave_offset — synchronized, same phase
- Wave spans FULL bar width, not just filled portion
- At a 2s refresh interval this jumps 8 positions — clearly visible
  movement on every redraw even at slow poll rates

ALSO CHANGE — lower cadence detection threshold:
- Change the redraw-interval active-mode threshold from 800ms to 400ms
  (the /tmp/statusline-last-call comparison)

After patching:
- Show the exact lines changed in the script
- Confirm date +%s%3N is used for both idle and active frame calc
- Show a test render of both modes
```

---

## Verify the fix landed

After Claude Code applies the patch, confirm these two things in the 
script output:

1. `MS=$(date +%s%3N)` appears near the top of the render function
2. Wave offset uses `(MS / 250) % 7` — not a stored counter variable

If the wave still looks slow after the fix, the hook poll rate itself 
may be the ceiling. In that case ask:

```
Is there a way to increase the statusline hook poll frequency 
in Claude Code config? What's the minimum supported interval?
```

---

## Token cost of this change

None. The statusline script is a shell process run by Claude Code's 
runtime — it executes outside the model's context window. More 
frequent or more complex renders add CPU overhead only, not tokens. 
The hooks (`touch /tmp/claude-active-task`) are also system-level 
and add no context to the model.
