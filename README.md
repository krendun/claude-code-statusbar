# claude-code-statusbar

A Claude Code status bar with per-metric colors, usage thresholds, dual 
animation modes, and a live countdown to rate-limit reset. Built entirely 
with Claude Code prompts — no manual shell scripting required.

> Add your screenshot here — capture it mid-response so the active wave 
> animation is visible.

---

## What it shows

```
landing-page/ (main*) | 5h ████░░░░ 22% ↺3h | 7d ████░░░░ 2% ↺6d | ctx ████░░░░ 9% | Opus 4.8 10:49 PM
```

Left to right:

| Segment | Color | What it tracks |
|---|---|---|
| `5h` | Steel blue | 5-hour usage window |
| `15h` | Amber | 15-hour window (appears only if your plan exposes it) |
| `7d` | Violet | 7-day usage window |
| `ctx` | Teal | Context window usage |
| Model + time | — | Current model, 12hr clock |

**Countdown timers** (`↺ 3h`, `↺ 6d`) appear on any rate-limit bar where 
the payload includes a reset timestamp — not just ctx.

**Color thresholds apply to all bars:**
- 0–60% → base muted color for that metric
- 60–85% → amber warning
- 85–100% → muted red

---

## Animation modes

**Idle** — rightmost character alternates `█ ↔ ▓` every ~2s.

**Active** (Claude is busy) — all bars switch simultaneously to a 
synchronized left-to-right wave: `░ ▒ ▓ █ ▓ ▒ ░`. Fires on any of 
four conditions:

1. Redraw cadence < 400ms
2. `total_output_tokens` delta increased since last draw
3. Active workflow or background task detected in payload
4. `/tmp/claude-active-task` flag file exists (written by hooks)

The wave persists for the entire duration of a long background task 
(like a dynamic workflow run), not just while tokens are streaming.

**How animation works at slow refresh rates**

Claude Code calls the statusline hook on its own internal timer — 
typically every 2-3 seconds. Rather than advancing the wave one step 
per call (which makes it crawl), the script uses the system clock 
(`date +%s%3N`) to compute which animation frame *should* be showing 
at the current moment. At a 2s refresh interval the wave jumps 8 
positions forward; at faster rates it's smooth. Either way, the 
animation always shows the correct time-position rather than falling 
behind.

---

## Token usage — do these features cost extra?

**No.** The status bar and animation add zero token cost.

The `statusline-command.sh` script is a shell script executed directly 
by Claude Code's runtime — not by the Claude model. It runs outside 
the model's context window entirely. More frequent renders mean more 
shell process spawns (trivial CPU), not more API calls.

The PreToolUse and PostToolUse hooks are also system-level calls. 
`touch /tmp/claude-active-task` and the cleanup process add no tokens 
to Claude's context.

The only thing that consumes tokens faster is Claude actually 
processing more work — the display layer is completely decoupled from 
the model. Running a dynamic workflow like `grade-verify` will consume 
tokens at whatever rate Opus 4.8 processes; the status bar just 
reflects that activity visually.

---

## Prerequisites

- Claude Code v2.1.154 or later
- Any paid Claude plan (Max, Team, or Enterprise)
- The `statusline` hook capability enabled in your Claude Code session

---

## Setup

Setup is two steps: dump your live payload first (so Claude uses real 
field names), then build the bar. Takes about 5 minutes.

### Step 1 — Dump your live payload

Open a Claude Code session and run this prompt. It builds a temporary 
debug script that dumps the raw statusline payload so Claude can read 
the exact field names for your plan before building anything permanent.

→ **[prompts/01-payload-dump.md](prompts/01-payload-dump.md)**

Read the output. Look for:
- Rate-limit field names (5h and 7d windows — note exact names)
- Whether a 15h window exists for your plan
- Whether reset timestamps exist and what they're named

Also **upload a screenshot of your Claude.ai usage panel** 
(Settings → Usage) in the same session — this helps Claude confirm 
which windows your plan actually exposes before wiring them up.

### Step 2 — Build the status bar

With the payload output (and usage screenshot) in the same session, 
run the full build prompt:

→ **[prompts/02-full-build.md](prompts/02-full-build.md)**

Claude Code will create `statusline-command.sh`, register it as the 
statusline hook, and wire up the PreToolUse/PostToolUse hooks for the 
active-mode flag file. Confirm the test render looks right before 
ending the session.

---

## After setup — file locations

Claude Code will have created these files during setup. Copy them into 
this repo for version control:

```
statusline-command.sh      # Ask Claude Code: "where is my statusline script?"
hooks/active-task-on.sh    # wired to PreToolUse  (matcher *)
hooks/active-task-off.sh   # wired to PostToolUse (matcher *)
```

To find them quickly, run this in your Claude Code session:

```
Where did you save statusline-command.sh and the hook scripts? 
Give me the exact paths.
```

---

## Troubleshooting

**Animation looks choppy or only moves every few seconds**  
This is a poll-rate issue — Claude Code calls the hook on its own 
timer (~2-3s). Run the animation fix prompt to switch from 
counter-based to time-based frames:

→ **[prompts/03-animation-fix.md](prompts/03-animation-fix.md)**

**Bar isn't activating after setup**  
Ask Claude Code to verify the hook registration:
```
Check whether the statusline hook is registered correctly 
in my Claude Code config and show me the current entry.
```

**15h bar or countdown not showing**  
These depend on payload fields that vary by plan. Share your payload 
dump output and ask:
```
The 15h bar and/or countdown aren't appearing. Here's my 
raw payload: [paste it]. What field names should I use?
```

**Wave not persisting during long background tasks**  
Confirm the hooks registered:
```
Did the PreToolUse and PostToolUse hooks for 
/tmp/claude-active-task register correctly? Show me 
the current hooks config.
```

---

## Contributing

Found a payload field name that works better? Built this on a plan 
that exposes different windows? Open a PR or an issue — especially 
useful if you're on Pro and the field names differ from Max/Team.

---

## License

MIT
