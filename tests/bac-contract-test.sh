#!/bin/sh
# Offline BotAsCollie v1 contract check. Fixtures, baseline observations, registry migration.
# Does not run bac, herdr, hc, or a network service, and does not read live config.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
C="$ROOT/contracts/bac/v1"
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v jq >/dev/null || fail "jq missing"
command -v sha256sum >/dev/null || fail "sha256sum missing"

# --- identity vs this tree -------------------------------------------------
impl=$(jq -r '.runtime_implemented' "$C/identity.json")
[ "$impl" = false ] || [ "$impl" = true ] || fail "runtime_implemented must be boolean"
if [ "$impl" = false ]; then
  [ ! -e "$ROOT/bin/bac" ] || fail "runtime_implemented is false but bin/bac exists"
  grep -q 'GBB_VERSION="0.3.3"' "$ROOT/bin/gbb" || fail "baseline version string missing"
  grep -q 'id = "phoobobo.grokbot-bridge"' "$ROOT/herdr-plugin.toml" || fail "plugin id changed before cutover"
else
  [ -x "$ROOT/bin/bac" ] || fail "runtime_implemented is true but bin/bac is missing"
fi
jq -e '.names.cli == "bac" and .names.source == "bot-as-collie" and .names.contract_version == 1' "$C/identity.json" >/dev/null || fail "identity names"
jq -e '.baseline.commit == "bbdfc4bbaece3ddafa3a9363b1d0f43b230aa5a6"' "$C/identity.json" >/dev/null || fail "baseline sha"
jq -e '.repo_renamed == false and .published == false' "$C/identity.json" >/dev/null || fail "repo/publish flags"
jq -e '.consumers_verified.dots_tunnel_bridge.commit == "a4b8e597060da1f3a714bc3b608278c3a2f219b0"' "$C/identity.json" >/dev/null || fail "dots commit"
jq -e '.consumers_verified.super_bot.verified == false and .consumers_verified.grok_bot.verified == false' "$C/identity.json" >/dev/null || fail "unverified consumers must stay unverified"

# --- baseline observations still match bin/gbb when that file is present ---
if [ -f "$ROOT/bin/gbb" ]; then
  jq -r '.must_contain[]' "$C/baseline-observations.json" | while IFS= read -r line; do
    grep -F -q "$line" "$ROOT/bin/gbb" || fail "baseline observation missing: $line"
  done
  jq -r '.kinds_absent[]' "$C/baseline-observations.json" | while IFS= read -r kind; do
    # Match the kind as a token. "pi" is a substring of pid/piped/pick.
    if grep -E -q "(^|[^A-Za-z0-9_-])${kind}([^A-Za-z0-9_-]|$)" "$ROOT/bin/gbb"; then
      fail "baseline bin/gbb mentions unsupported kind $kind"
    fi
  done
  if grep -E -q 'quota|rate_limit|credits' "$ROOT/bin/gbb"; then
    fail "baseline bin/gbb gained a quota field; kinds/quota contract must be revised"
  fi
fi

# Supported kinds in the contract are exactly the ones the baseline accept-branch names.
jq -e '[.kinds[] | select(.support == "supported") | .id] | sort == ["codex","grok"]' "$C/kinds.json" >/dev/null || fail "supported kinds"
jq -e '[.kinds[] | select(.id == "pi" or .id == "antigravity") | .support] | unique == ["rejected"]' "$C/kinds.json" >/dev/null || fail "pi/antigravity"
jq -e '.omitted_kind.code == "kind_required" and .unknown_never_becomes == ["codex","grok"]' "$C/kinds.json" >/dev/null || fail "kind defaults"

# --- usage lines in the human contract match commands.json -----------------
jq -r '.commands[].usage' "$C/commands.json" | while IFS= read -r line; do
  grep -F -q "$line" "$ROOT/docs/bac/v1/CONTRACT.md" || fail "CONTRACT.md missing usage: $line"
done
grep -F -q 'bbdfc4bbaece3ddafa3a9363b1d0f43b230aa5a6' "$ROOT/docs/bac/v1/CONTRACT.md" || fail "CONTRACT.md missing baseline sha"
grep -F -q 'bot-as-collie' "$ROOT/docs/bac/v1/CONTRACT.md" || fail "CONTRACT.md missing source"
grep -F -q 'a4b8e597060da1f3a714bc3b608278c3a2f219b0' "$ROOT/docs/bac/v1/MIGRATION.md" || fail "MIGRATION.md missing dots sha"

# --- dots argv: bac only, kind required, no hc tool ------------------------
jq -e '.target.argv0 == "bac" and .target.webhook_source_required == "bot-as-collie" and .target.webhook_version_required == 1 and .target.keep_gbb_tools == false' "$C/dots-argv.json" >/dev/null || fail "dots target"
jq -e '.today.webhook_source_required == "grokbot-bridge-herdr" and .today.launch_kind_default_in_python == "codex" and .today.handover_regex_rejects_hc_address == true and .today.no_subscription_queued == false' "$C/dots-argv.json" >/dev/null || fail "dots today"
jq -e '.tools.bac_launch | index("--kind") != null' "$C/dots-argv.json" >/dev/null || fail "bac_launch kind"
jq -r '.tools | to_entries[] | .value[0]' "$C/dots-argv.json" | while IFS= read -r a0; do
  [ "$a0" = bac ] || fail "dots tool argv0 is $a0"
done
jq -e '.not_tools | index("hc") != null' "$C/dots-argv.json" >/dev/null || fail "hc must stay off the tool list"
if jq -e '.tools | keys[] | select(startswith("gbb_"))' "$C/dots-argv.json" >/dev/null; then
  fail "target tool list still has gbb_"
fi

# --- acceptance scenarios are specified and unrun --------------------------
jq -e '.ran == false and .environment == "fixture" and .callers == ["grok-bot","dots"]' "$C/acceptance.json" >/dev/null || fail "acceptance header"
jq -e '[.scenarios[].ran] | all(. == false)' "$C/acceptance.json" >/dev/null || fail "a scenario claims it ran"
jq -e '[.scenarios[].environment] | all(. == "fixture")' "$C/acceptance.json" >/dev/null || fail "scenario environment"
# No step may invoke hc or gbb.
if jq -e '[.scenarios[].steps[]?.argv? // empty | .[0]] | any(. == "hc" or . == "gbb")' "$C/acceptance.json" >/dev/null; then
  fail "acceptance argv bypasses bac"
fi
jq -e 'any(.scenarios[]; .id == "grok-bot-primary" and any(.steps[]; .op == "launch") and any(.steps[]; .op == "status") and any(.steps[]; .route == "primary"))' "$C/acceptance.json" >/dev/null || fail "grok-bot flow"
jq -e 'any(.scenarios[]; .id == "dots-launch-and-handover" and any(.steps[]; .op == "launch") and any(.steps[]; .op == "handover") and any(.steps[]; .route == "owner"))' "$C/acceptance.json" >/dev/null || fail "dots flow"
jq -e 'any(.scenarios[]; .id == "cross-owner" and .mutates == false and all(.steps[]; .registry_unchanged == true and .expect.error.code == "owner_mismatch"))' "$C/acceptance.json" >/dev/null || fail "cross-owner"
jq -e '.scenarios[] | select(.id == "duplicate-and-timeout") | .attempt == 1 and .retry_same_target == false and .dedupe_key == "event_id" and .dots_202_without_subscription_does_not_queue == true' "$C/acceptance.json" >/dev/null || fail "timeout semantics"
jq -e '.scenarios[] | select(.id == "restart") | .replay_undelivered == false and .delivery == "at_most_once"' "$C/acceptance.json" >/dev/null || fail "restart semantics"

# --- callbacks -------------------------------------------------------------
event_id() { # pane event status generation
  printf 'bac.callback.v1\n%s\n%s\n%s\n%s' "$1" "$2" "$3" "$4" | sha256sum | awk '{print $1}'
}

callback_ok() { # payload json on stdin. Prints nothing. Nonzero = reject.
  jq -e '
    def fake: . == "planned" or . == "pending" or . == "unknown" or . == "fake" or . == "placeholder";
    def forbidden: ["text","screen","prompt","output","stdout","stderr","env","token","header","header_value","secret","password","model","quota","args","agent_args","raw"];
    (all(paths | .[-1] | strings; . as $k | forbidden | index($k) | not))
    and .version == 1
    and .source == "bot-as-collie"
    and (.event_id | type == "string" and test("^[0-9a-f]{64}$"))
    and (.generation | type == "number" and . >= 1)
    and .attempt == 1
    and (.event | IN("agent_status","handover","reclaim","stopped","pane_closed","test"))
    and (.route | IN("owner","primary","fallback","extra"))
    and (.owner == null or ((.owner | type) == "string"))
    and ((.pane_id | type) == "string")
    and (.pane_id | fake | not)
    and (.agent_kind == null or .agent_kind == "codex" or .agent_kind == "grok")
    and (.backend == "herdr" or .backend == "hc")
  ' >/dev/null
}

check_payload() {
  payload=$1
  pane=$(printf '%s' "$payload" | jq -r '.pane_id')
  ev=$(printf '%s' "$payload" | jq -r '.event')
  st=$(printf '%s' "$payload" | jq -r '.status // empty')
  gen=$(printf '%s' "$payload" | jq -r '.generation')
  want=$(event_id "$pane" "$ev" "$st" "$gen")
  got=$(printf '%s' "$payload" | jq -r '.event_id')
  [ "$got" = "$want" ] || fail "event_id $got != $want"
  printf '%s' "$payload" | callback_ok || fail "callback rejected: $payload"
}

p=$(jq -c '.payload' "$C/fixtures/callbacks/owner-done.json")
check_payload "$p"
# A new generation is a different id. A retry of the same generation is not.
alt=$(event_id t9 agent_status "done" 4)
[ "$alt" != "$(printf '%s' "$p" | jq -r .event_id)" ] || fail "generation did not change event_id"

n=$(jq '.payloads | length' "$C/fixtures/callbacks/fallback-same-event.json")
[ "$n" = 2 ] || fail "fallback pair length"
id1=$(jq -r '.payloads[0].event_id' "$C/fixtures/callbacks/fallback-same-event.json")
id2=$(jq -r '.payloads[1].event_id' "$C/fixtures/callbacks/fallback-same-event.json")
[ "$id1" = "$id2" ] || fail "fallback event_id changed"
jq -e '.payloads[0].route == "owner" and .payloads[1].route == "fallback" and .payloads[1].fallback_reason == "owner_delivery_failed" and .payloads[0].attempt == 1 and .payloads[1].attempt == 1' "$C/fixtures/callbacks/fallback-same-event.json" >/dev/null || fail "fallback shape"
jq -c '.payloads[]' "$C/fixtures/callbacks/fallback-same-event.json" | while IFS= read -r one; do
  check_payload "$one"
done
jq -e '.payload | (has("text") or has("screen") or has("prompt"))' "$C/fixtures/callbacks/reject-terminal-text.json" >/dev/null || fail "reject fixture lost terminal keys"
if jq -c '.payload' "$C/fixtures/callbacks/reject-terminal-text.json" | callback_ok; then
  fail "terminal text was accepted on a callback"
fi

# --- CLI examples ----------------------------------------------------------
model_ok='
  if .provenance == "unknown" then
    .id == null and .observed_at == null and .freshness == "unknown" and .freshness_sec == null
  elif .provenance == "observed" then
    (.id | type) == "string" and (.id | length) > 0 and (.id | length) <= 80
    and (.observed_at | type) == "string"
    and (.freshness_sec | type) == "number" and .freshness_sec >= 0
    and ((.freshness == "fresh" and .freshness_sec <= 900) or (.freshness == "stale" and .freshness_sec > 900))
  elif .provenance == "config" then
    (.id | type) == "string" and (.id | length) > 0
    and .freshness == "not_a_session_observation"
    and (.observed_at | type) == "string"
    and .freshness_sec == null
  else false end
'
quota_unknown='.provenance == "unknown" and .value == null and .unit == null and .observed_at == null and .freshness == "unknown"'

jq -e ".body.model | $model_ok" "$C/fixtures/cli/launch-hc-ok.json" >/dev/null || fail "launch model"
jq -e ".body.quota | $quota_unknown" "$C/fixtures/cli/launch-hc-ok.json" >/dev/null || fail "launch quota"
jq -e '
  .body.ok == true
  and .body.pane_id_source == "hc.address"
  and .body.pane_id == "t9"
  and .body.pane_id != .body.herdr_space
  and .body.pane_id != .body.herdr_tab
  and (.body.herdr_space | test("^sp[0-9a-f]{32}$"))
  and (.body.herdr_tab | test("^tb[0-9a-f]{32}$"))
  and (.body.kind == "codex" or .body.kind == "grok")
' "$C/fixtures/cli/launch-hc-ok.json" >/dev/null || fail "launch ok shape"
for fake in planned pending unknown fake placeholder; do
  jq -e --arg f "$fake" '.body.pane_id != $f' "$C/fixtures/cli/launch-hc-ok.json" >/dev/null || fail "fake pane id"
done

jq -e '.body.ok == false and .body.error.code == "agent_start_failed" and (.body | has("pane_id") | not) and (.body | has("herdr_space") | not)' "$C/fixtures/cli/launch-no-address.json" >/dev/null || fail "missing address still has a pane id"

jq -e '.body.error.code == "kind_unsupported" and .body.error.kind == "pi" and .body.error.kind_support == "rejected" and .body.error.kind != "codex"' "$C/fixtures/cli/kind-pi.json" >/dev/null || fail "pi kind"
jq -e '.body.error.code == "kind_unsupported" and .body.error.kind == "antigravity" and .body.error.kind_support == "rejected"' "$C/fixtures/cli/kind-antigravity.json" >/dev/null || fail "antigravity kind"
jq -e '.body.error.code == "kind_unsupported" and .body.error.kind == "nope" and .body.error.kind_support == "unknown" and .body.error.kind != "codex" and .body.error.kind != "grok"' "$C/fixtures/cli/kind-unknown.json" >/dev/null || fail "unknown kind"
jq -e '.body.error.code == "kind_required" and (.body.error.kind == null)' "$C/fixtures/cli/kind-omitted.json" >/dev/null || fail "omitted kind"
jq -e '.mutates == false and .body.error.code == "owner_mismatch" and (.body | has("text") | not)' "$C/fixtures/cli/owner-mismatch.json" >/dev/null || fail "owner mismatch"

jq -e ".model | $model_ok" "$C/fixtures/cli/model-observed.json" >/dev/null || fail "observed model"
jq -e ".model | $model_ok" "$C/fixtures/cli/model-config.json" >/dev/null || fail "config model"
jq -e ".model | $model_ok" "$C/fixtures/cli/model-unknown.json" >/dev/null || fail "unknown model"
if jq -e ".quota | $quota_unknown" "$C/fixtures/cli/quota-guess-rejected.json" >/dev/null; then
  fail "a guessed quota was accepted"
fi

# --- registry migration on an isolated copy --------------------------------
sha() { sha256sum "$1" | awk '{print $1}'; }
MIG="$C/migrate-fixture.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cp -R "$C/fixtures/registry-ok" "$T/ok"
cp -R "$C/fixtures/registry-bad" "$T/bad"
before=$(sha "$T/ok/managed.json")
bad_before=$(sha "$T/bad/managed.json")
sh "$MIG" "$T/ok" "$T/out" >/dev/null || fail "migrate ok fixture"
after=$(sha "$T/ok/managed.json")
[ "$before" = "$after" ] || fail "source registry changed"
jq -e '
  .schema == "bac.registry.v1"
  and (.panes | keys | sort) == ["t6","t7","t8","t9","w1:p1"]
  and .panes["t9"].pane_id == "t9" and .panes["t9"].owner == "dot" and .panes["t9"].kind == "codex" and .panes["t9"].backend == "hc"
  and .panes["w1:p1"].pane_id == "w1:p1" and .panes["w1:p1"].owner == "canmouzhang" and .panes["w1:p1"].kind == "grok" and .panes["w1:p1"].backend == "herdr"
  and .panes["t8"].pane_id == "t8" and .panes["t8"].owner == "dot" and .panes["t8"].kind == null and .panes["t8"].kind_reported == "pi" and .panes["t8"].kind_support == "rejected"
  and .panes["t7"].kind == null and .panes["t7"].kind_reported == "nope" and .panes["t7"].kind_support == "unknown" and .panes["t7"].kind != "codex"
  and .panes["t6"].backend == "herdr" and .panes["t6"].owner == null and .panes["t6"].kind == null
  and ([.panes[].pane_id] | index("planned") | not)
' "$T/out/managed.json" >/dev/null || fail "migrated registry lost owner/pane or rewrote kind"

if sh "$MIG" "$T/bad" "$T/bad-out" >/dev/null 2>&1; then
  fail "fake pane id was migrated"
fi
[ ! -e "$T/bad-out/managed.json" ] || fail "failed migration wrote a registry"
[ "$(sha "$T/bad/managed.json")" = "$bad_before" ] || fail "failed migration changed the source"

# Live state directories are refused even with the marker.
mkdir -p "$T/home/.local/state/grokbot-bridge-herdr"
cp "$T/ok/managed.json" "$T/ok/FIXTURE_OK" "$T/home/.local/state/grokbot-bridge-herdr/"
live_before=$(sha "$T/home/.local/state/grokbot-bridge-herdr/managed.json")
if HOME="$T/home" sh "$MIG" "$T/home/.local/state/grokbot-bridge-herdr" "$T/live-out" >/dev/null 2>&1; then
  fail "live state path was accepted"
fi
[ "$(sha "$T/home/.local/state/grokbot-bridge-herdr/managed.json")" = "$live_before" ] || fail "live refusal changed the file"
[ ! -e "$T/live-out/managed.json" ] || fail "live refusal wrote output"

mkdir -p "$T/nomark"
cp "$T/ok/managed.json" "$T/nomark/"
if sh "$MIG" "$T/nomark" "$T/nomark-out" >/dev/null 2>&1; then
  fail "missing marker was accepted"
fi

echo PASS
