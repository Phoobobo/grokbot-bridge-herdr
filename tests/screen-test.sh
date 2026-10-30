#!/bin/sh
# Offline test of Codex screen handling with a stubbed herdr that draws Codex 0.166 screens:
#  hook reclassification (hooks review / queued question / fresh session -> blocked, launching window ignored),
#  gbb send refusing to type into a dialog, gbb answer (queued question, label + number, selection
#  verified), and a saved launch prompt being submitted after the startup dialog is answered.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat >"$T/herdr" <<'H'
#!/bin/sh
S="$STUB_DIR"; mode=$(cat "$S/mode"); sel=$(cat "$S/sel")
opt() { if [ "$sel" = "$1" ]; then printf '› %s. %s\n' "$1" "$2"; else printf '  %s. %s\n' "$1" "$2"; fi; }
case "$1 $2" in
  "pane read")
    echo "• earlier transcript line"; echo "  1. a numbered list in the transcript"
    case "$mode" in
      hooks) echo "  Hooks need review"; echo "  1 hook is new or changed."; opt 1 "Review hooks"; opt 2 "Trust all and continue"
        opt 3 "Continue without trusting (hooks won't run)"; echo "  enter confirm · esc skip" ;;
      fresh) echo "› Ask Codex to do anything"; echo "  GPT-6.1-Sol xhigh · ~/x · Context 0% used · 0 in · 0 out" ;;
      ready) echo "› Ask Codex to do anything"; echo "  GPT-6.1-Sol xhigh · ~/x · Context 7% used · 12k in · 2k out" ;;
      queued) echo "• Queued follow-up inputs"; echo "  ? 1 question"; echo "  ⇧← to answer"; echo "› Ask Codex to do anything"
        echo "  GPT-6.1-Sol xhigh · ~/x · Context 7% used · 12k in · 2k out" ;;
      dialog) echo "  BLOCKED: Pick a letter?"; opt 1 Alpha; opt 2 Beta; opt 3 Other; echo "  enter submit   ⌃] skip   ⇧→ main prompt" ;;
      working) echo "• Working (1s • esc to interrupt)"; echo "› "; echo "  GPT-6.1-Sol xhigh · ~/x · Context 7% used · 12k in · 2k out" ;;
    esac ;;
  "agent get") case "$mode" in working) st=working ;; dialog | queued) st=blocked ;; fresh) st=done ;; *) st=idle ;; esac
    printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$st" ;;
  "agent send-keys") shift 3
    for k in "$@"; do
      echo "key $k" >>"$S/calls"
      case "$mode:$k" in
        queued:shift+left) echo dialog >"$S/mode"; echo 1 >"$S/sel" ;;
        dialog:down | hooks:down) echo $((sel + 1)) >"$S/sel" ;;
        dialog:up | hooks:up) echo $((sel - 1)) >"$S/sel" ;;
        dialog:enter) echo "answered $sel" >>"$S/calls"; echo ready >"$S/mode" ;;
        hooks:enter) echo "answered $sel" >>"$S/calls"; echo fresh >"$S/mode" ;;
      esac
      mode=$(cat "$S/mode"); sel=$(cat "$S/sel")
    done
    echo '{"result":{"type":"ok"}}' ;;
  "agent prompt") echo "prompt $4" >>"$S/calls"; echo working >"$S/mode"; echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
H
chmod +x "$T/herdr"
export HERDR_BIN_PATH="$T/herdr" GBB_STATE_DIR="$T/state" GBB_CONFIG="$T/none.toml" STUB_DIR="$T"
unset GBB_OWNER 2>/dev/null || true
mkdir -p "$T/state"
fail() { echo "FAIL: $*"; cat "$T/calls" 2>/dev/null; cat "$T/state/bridge.log" 2>/dev/null; exit 1; }
reset() { # reset <mode> [extra registry json]
  x=${2:-}; [ -n "$x" ] || x='{}' # not "${2:-{\}}": bash 3.2 (macOS sh) keeps the backslash
  printf '{"version":1,"panes":{"w1:p1":%s}}\n' "$(jq -cn --argjson x "$x" \
    '{pane_id:"w1:p1",workspace_id:"w1",task_id:"t1",agent_name:"gb-t1",kind:"codex",origin:"launched",armed:true} + $x')" >"$T/state/managed.json"
  echo "$1" >"$T/mode"; echo 1 >"$T/sel"; : >"$T/calls"; rm -rf "$T/state/last" "$T/state/pending"; mkdir -p "$T/state/last"
}
ev() { HERDR_PLUGIN_EVENT=pane.agent_status_changed HERDR_PLUGIN_EVENT_JSON="{\"data\":{\"pane_id\":\"w1:p1\",\"agent_status\":\"$1\"}}" "$ROOT/bin/gbb" hook; }
reg() { jq -r ".panes[\"w1:p1\"] | $1" "$T/state/managed.json"; }

# --- hook classification
reset hooks; ev idle
[ "$(reg '.last_status + "/" + .blocked_reason')" = blocked/hooks_review ] || fail "hooks review -> $(reg .)"
reset fresh; ev "done"
[ "$(reg '.last_status + "/" + .blocked_reason')" = blocked/prompt_not_submitted ] || fail "fresh launched -> $(reg .)"
reset fresh '{"origin":"handover"}'; ev "done"
[ "$(reg '.last_status + "/" + (.blocked_reason // "none")')" = idle/none ] || fail "fresh handover -> $(reg .)"
reset fresh "{\"launching_until\":$(($(date +%s) + 60))}"; ev "done"
[ "$(reg '.last_status // "none"')" = none ] || fail "launching window not ignored"
reset ready; ev "done"
[ "$(reg '.last_status + "/" + (.blocked_reason // "none")')" = done/none ] || fail "real done -> $(reg .)"
reset queued; ev "done"
[ "$(reg '.last_status + "/" + .blocked_reason')" = blocked/question ] || fail "queued question -> $(reg .)"

# --- send refuses to type into a dialog, with an actionable hint
reset queued
out=$("$ROOT/bin/gbb" send t1 "hello" || true)
printf '%s' "$out" | jq -e '.ok == false and .error.code == "agent_blocked" and (.error.hint | test("gbb answer"))' >/dev/null || fail "send hint: $out"
grep -q prompt "$T/calls" && fail "send typed into a dialog"
"$ROOT/bin/gbb" send t1 --pending >/dev/null 2>&1 && fail "--pending without a saved prompt"

# --- answer a queued question by label (opens it, moves down, enters)
reset queued
out=$("$ROOT/bin/gbb" answer t1 beta)
printf '%s' "$out" | jq -e '.ok and .answered.option == 2 and .answered.label == "Beta"' >/dev/null || fail "answer label: $out"
[ "$(tr '\n' ' ' <"$T/calls")" = "key shift+left key down key enter answered 2 " ] || fail "answer keys: $(tr '\n' ' ' <"$T/calls")"
reset dialog
"$ROOT/bin/gbb" answer t1 7 >/dev/null 2>&1 && fail "bad option accepted"
"$ROOT/bin/gbb" answer t1 a >/dev/null 2>&1 && fail "ambiguous label accepted"
reset ready
"$ROOT/bin/gbb" answer t1 1 >/dev/null 2>&1 && fail "answer without dialog"

# --- startup hooks dialog answered -> saved launch prompt is submitted
reset hooks
mkdir -p "$T/state/pending"; printf 'do the task' >"$T/state/pending/w1_p1"
out=$("$ROOT/bin/gbb" answer t1 3)
printf '%s' "$out" | jq -e '.ok and .pending_prompt_sent == true' >/dev/null || fail "pending prompt: $out"
{ grep -q 'answered 3' "$T/calls" && grep -q 'prompt do the task' "$T/calls"; } || fail "pending calls: $(tr '\n' ' ' <"$T/calls")"
[ ! -f "$T/state/pending/w1_p1" ] || fail "pending prompt not cleared"
echo PASS
