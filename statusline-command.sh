#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# statusline-command.sh — claude-code-statusbar reference implementation
# https://github.com/krendun/claude-code-statusbar
#
# FIELD NAMES: Run prompts/01-payload-dump.md first to confirm your plan's
# exact payload field names, then update parse_window() calls below.
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

# ── 1. Capture payload and git context ───────────────────────────────────────
PAYLOAD=$(cat 2>/dev/null || echo '{}')
PAYLOAD_TMP=$(mktemp /tmp/cc-statusline-XXXXXX.json)
printf '%s' "$PAYLOAD" > "$PAYLOAD_TMP"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
DIRTY=$([ -n "$(git status --porcelain 2>/dev/null)" ] && echo "*" || echo "")
DIR=$(basename "$(pwd)")

# ── 2. Python renders the full status line ───────────────────────────────────
python3 - "$PAYLOAD_TMP" "$BRANCH" "$DIRTY" "$DIR" <<'PYEOF'
import json, sys, datetime, time, os

payload_file = sys.argv[1]
branch       = sys.argv[2]
dirty        = sys.argv[3]
directory    = sys.argv[4]

ms = int(time.time() * 1000)

try:
    with open(payload_file) as f:
        data = json.load(f)
except Exception:
    data = {}

# ── ANSI helpers ──────────────────────────────────────────────────────────────
R    = "\033[0m"
DIM  = "\033[2m"
BOLD = "\033[1m"
def rgb(r, g, b):      return f"\033[38;2;{r};{g};{b}m"
def dim_rgb(r, g, b):  return f"\033[2;38;2;{r};{g};{b}m"

C_5H     = rgb(74,  158, 255)   # steel blue
C_15H    = rgb(232, 160, 69)    # amber
C_7D     = rgb(155, 109, 255)   # violet
C_CTX    = rgb(78,  205, 196)   # teal
C_WARN   = rgb(232, 160, 69)    # amber warning  (60–85%)
C_CRIT   = rgb(204, 68,  68)    # muted red      (85–100%)
C_SEP    = rgb(70,  70,  70)    # dim separator
C_BRANCH = rgb(130, 130, 130)   # dim branch info
C_ALERT  = rgb(255, 255, 255)   # white flash for threshold alert

SEP   = f"{C_SEP}│{R}"
BAR_W = 8
WAVE  = ["░", "▒", "▓", "█", "▓", "▒", "░"]   # 7-char ripple sequence

# ── Parse rate-limit windows ──────────────────────────────────────────────────
# Searches both the top-level payload and a nested rate_limits object so that
# most plan/field-name variations are covered automatically.
rl = data.get('rate_limits') or data.get('rateLimits') or {}

def parse_window(*keys):
    """Return (pct, reset_ts) for the first key found in data or rl."""
    for src in (data, rl):
        for k in keys:
            w = src.get(k) if isinstance(src, dict) else None
            if isinstance(w, dict):
                used  = w.get('used')  or 0
                limit = w.get('limit') or 1
                pct   = min(100, int(used / limit * 100)) if limit else 0
                reset = w.get('reset_at') or w.get('resetAt') or w.get('reset')
                return pct, reset
    return None, None   # None pct = "field not in payload, omit bar"

fh_pct, fh_reset = parse_window('five_hour',    'fiveHour',    'five_hour_limit')
fh_pct = fh_pct if fh_pct is not None else 0

sh_pct, sh_reset = parse_window('fifteen_hour', 'fifteenHour', 'fifteen_hour_limit')
# sh_pct stays None → 15h bar is omitted

sd_pct, sd_reset = parse_window('seven_day',    'sevenDay',    'seven_day_limit')
sd_pct = sd_pct if sd_pct is not None else 0

ctx_d    = data.get('context_window') or data.get('contextWindow') or {}
ctx_in   = ctx_d.get('input_tokens')         or 0
ctx_out  = ctx_d.get('total_output_tokens')  or 0
ctx_max  = ctx_d.get('max_tokens')           or 200000
ctx_pct  = min(100, int((ctx_in + ctx_out) / ctx_max * 100)) if ctx_max else 0
ctx_reset = ctx_d.get('reset_at') or ctx_d.get('resetAt')

# ── Active-mode detection (four conditions) ───────────────────────────────────
is_active = os.path.exists('/tmp/claude-active-task')   # condition 4 (flag file)

if not is_active:                                       # condition 3 (payload tasks)
    for field in ('tasks', 'workflows', 'background_tasks', 'agents', 'running_tasks'):
        items = data.get(field) or []
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict) and \
                   item.get('status', '') in ('running','active','in_progress','pending','executing'):
                    is_active = True
                    break

# Condition 2: token delta
PREV_TOK_FILE = '/tmp/statusline-prev-tokens'
cur_tokens = ctx_in + ctx_out
try:
    prev_tokens = int(open(PREV_TOK_FILE).read().strip())
    if cur_tokens > prev_tokens:
        is_active = True
except Exception:
    pass
try:
    with open(PREV_TOK_FILE, 'w') as f: f.write(str(cur_tokens))
except Exception:
    pass

# Condition 1: cadence < 400 ms
CADENCE_FILE = '/tmp/statusline-last-call'
try:
    prev_ms = int(open(CADENCE_FILE).read().strip())
    if ms - prev_ms < 400:
        is_active = True
except Exception:
    pass
try:
    with open(CADENCE_FILE, 'w') as f: f.write(str(ms))
except Exception:
    pass

# ── Threshold alert (bell + reverse-flash) ────────────────────────────────────
# Fires once per metric per crossing of ALERT_PCT. A cooldown file per metric
# suppresses repeat firings until the metric drops back below RESET_PCT.
ALERT_PCT = 90    # ring bell + flash when metric hits this
RESET_PCT = 85    # cooldown clears once metric falls back below this

def maybe_alert(name, pct):
    """Return True if this render should flash (and fire the bell)."""
    if pct is None:
        return False
    flag = f'/tmp/cc-alerted-{name}'
    already_alerted = os.path.exists(flag)
    if pct >= ALERT_PCT and not already_alerted:
        try:
            open(flag, 'w').close()           # set cooldown
        except Exception:
            pass
        return True                           # flash + bell this render
    if pct < RESET_PCT and already_alerted:
        try:
            os.remove(flag)                   # reset cooldown for next crossing
        except Exception:
            pass
    return False

fh_alert  = maybe_alert('5h',  fh_pct)
sh_alert  = maybe_alert('15h', sh_pct) if sh_pct is not None else False
sd_alert  = maybe_alert('7d',  sd_pct)
ctx_alert = maybe_alert('ctx', ctx_pct)

any_alert = fh_alert or sh_alert or sd_alert or ctx_alert

# ── Idle-inactivity pause ─────────────────────────────────────────────────────
# When Claude is idle AND the terminal hasn't been touched for IDLE_PAUSE_SECS,
# skip the wave calc and emit a static bar. Saves redraws when you've stepped
# away. The wave resumes instantly on any active-mode trigger.
IDLE_PAUSE_SECS = 30
LAST_ACTIVE_FILE = '/tmp/statusline-last-active'

if is_active:
    try:
        with open(LAST_ACTIVE_FILE, 'w') as f: f.write(str(ms))
    except Exception:
        pass
    animation_paused = False
else:
    try:
        last_active_ms = int(open(LAST_ACTIVE_FILE).read().strip())
        animation_paused = (ms - last_active_ms) > (IDLE_PAUSE_SECS * 1000)
    except Exception:
        animation_paused = False   # no file yet → not paused

# ── Model display name ────────────────────────────────────────────────────────
model = str(data.get('model') or data.get('modelName') or data.get('model_name') or '')
ml = model.lower()
if   'opus'   in ml:
    if   '4.8' in model: mdisplay = 'Opus 4.8'
    elif '4.7' in model: mdisplay = 'Opus 4.7'
    elif '4.6' in model: mdisplay = 'Opus 4.6'
    else:                mdisplay = 'Opus 4'
elif 'sonnet' in ml: mdisplay = 'Sonnet 4.6'
elif 'haiku'  in ml: mdisplay = 'Haiku 4.5'
elif model:          mdisplay = model[:12]
else:                mdisplay = 'Claude'

# ── Reset countdown ───────────────────────────────────────────────────────────
def countdown(reset_ts):
    if not reset_ts: return ''
    try:
        now  = datetime.datetime.now(datetime.timezone.utc)
        then = datetime.datetime.fromisoformat(str(reset_ts).replace('Z', '+00:00'))
        secs = int((then - now).total_seconds())
        if secs <= 0: return ''
        d, rem = divmod(secs, 86400)
        h, rem = divmod(rem, 3600)
        m = rem // 60
        if d > 0: return f'↺{d}d'
        if h > 0: return f'↺{h}h'
        return f'↺{m}m'
    except: return ''

# ── Animation frames ──────────────────────────────────────────────────────────
# Time-based: correct position on every render regardless of poll interval.
wave_offset = (ms // 250) % 7     # wave advances every 250 ms
idle_frame  = (ms // 2000) % 2    # shimmer toggles every 2 s

REVERSE = "\033[7m"   # reverse-video for alert flash

def render_bar(pct, base_color, alert=False):
    if pct is None: return ''
    filled = min(BAR_W, BAR_W * pct // 100)
    color  = C_CRIT if pct >= 85 else (C_WARN if pct >= 60 else base_color)
    # Alert flash: invert the entire bar for one render cycle
    if alert:
        color = f"{REVERSE}{color}"
    out    = []
    if is_active and not animation_paused:
        # Full-width traveling wave
        for i in range(BAR_W):
            idx = (wave_offset + i) % 7
            out.append(f"{color}{WAVE[idx]}{R}")
    else:
        # Filled + shimmer on last filled char + dim empty
        # (shimmer frozen when animation_paused to save redraws)
        frame = idle_frame if not animation_paused else 0
        for i in range(BAR_W):
            if i < filled:
                ch = ("█" if frame == 0 else "▓") if i == filled - 1 else "█"
                out.append(f"{color}{ch}{R}")
            else:
                out.append(f"{DIM}░{R}")
    return ''.join(out)

# ── Time ──────────────────────────────────────────────────────────────────────
time_str = datetime.datetime.now().strftime("%I:%M %p").lstrip('0')

# ── Assemble output ───────────────────────────────────────────────────────────
# Branch / directory (dimmed)
branch_str = f"{C_BRANCH}{directory}/ ({branch}{dirty}){R}" if branch \
             else f"{C_BRANCH}{directory}/{R}"

S = f" {SEP} "

def metric(label, color, pct, reset, alert=False):
    b  = render_bar(pct, color, alert=alert)
    cd = countdown(reset)
    cd_str = f" {DIM}{cd}{R}" if cd else ""
    # Bell character goes to stderr so it doesn't corrupt the status line text
    if alert:
        print("\a", end='', file=sys.stderr)
    return f"{color}{label}{R} {b} {BOLD}{pct}%{R}{cd_str}"

segments = [branch_str]
segments.append(metric("5h",  C_5H,  fh_pct, fh_reset, alert=fh_alert))
if sh_pct is not None:
    segments.append(metric("15h", C_15H, sh_pct, sh_reset, alert=sh_alert))
segments.append(metric("7d",  C_7D,  sd_pct, sd_reset, alert=sd_alert))
segments.append(metric("ctx", C_CTX, ctx_pct, ctx_reset, alert=ctx_alert))
segments.append(f"{BOLD}{mdisplay}{R} {DIM}{time_str}{R}")

print(S.join(segments))
PYEOF

rm -f "$PAYLOAD_TMP"