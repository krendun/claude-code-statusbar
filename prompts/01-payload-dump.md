# Prompt 01 — Payload Dump

Run this prompt first, before building the status bar. It creates a 
temporary debug script that dumps the raw statusline JSON payload so 
Claude can read your exact field names before wiring anything permanent.

Also upload a screenshot of your Claude.ai usage panel (Settings → Usage) 
in the same session — this lets Claude confirm which rate-limit windows 
your plan actually exposes.

---

## The prompt

```
Write a temporary statusline hook script that does one thing only:
dumps the raw JSON payload it receives to /tmp/statusline-payload.json
and exits. Register it as the statusline command in my Claude Code config.

Then trigger a redraw and read /tmp/statusline-payload.json back to me 
so I can see the exact field names for:
- Rate-limit windows (5h, 15h, 7d, or whatever your plan sends)
- Context window usage
- Any reset timestamps
- Any fields indicating active/streaming/processing state

Do not build the real status bar yet. Just show me the full raw payload 
so I know what data is actually available.
```

---

## What to do with the output

Once Claude returns the raw JSON:

1. Note the exact field names for each rate-limit window
2. Check whether a `fifteen_hour` (or equivalent) field exists
3. Check whether reset timestamps exist and what they're named
4. Keep this session open — the next prompt (02-full-build.md) 
   uses these confirmed field names to build the real bar
