#!/bin/sh
# Offline placement: an hc launch (and a handover that is not already in a space)
# labels herdr.space and does not set herdr.tab. A matching local space is reused;
# a remote space is not; a miss mints an id and asks the app to name it.
# herdr-app and hc are stubs. No live Herdr window.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd -P); T=$(mktemp -d)
cleanup() {
  if [ -n "${GBB_STATE_DIR:-}" ] && [ -f "$GBB_STATE_DIR/hc-watch.pid" ]; then
    kill "$(cat "$GBB_STATE_DIR/hc-watch.pid")" 2>/dev/null || true
  fi
  rm -rf "$T"
}
trap cleanup EXIT
mkdir -p "$T/bin" "$T/state" "$T/data" "$T/repo" "$T/elsewhere"
cat >"$T/bin/hc" <<'H'
#!/bin/sh
d=$(mktemp "$STUB_DIR/call.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
case "$1" in
  run) printf '%s\n' '{"address":"t9","name":"n","state":"live","turn":0}' ;;
  ls) cat "$STUB_DIR/hc-ls.json" ;;
  get)
    addr=""
    for a in "$@"; do
      case "$a" in
        --*) ;;
        get) ;;
        *) addr="$a" ;;
      esac
    done
    if [ -n "$addr" ] && [ -f "$STUB_DIR/get-$addr.json" ]; then cat "$STUB_DIR/get-$addr.json"; exit 0; fi
    cat "$STUB_DIR/get.json"
    ;;
  send) printf '%s\n' '{"started":true,"status":"working","turn":1}' ;;
  read) printf '%s\n' ready ;;
  server) printf '%s\n' '{"pid":1,"version":"0.1.17","core":{"id":"stub"}}' ;;
  events) exit 0 ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
H
cat >"$T/bin/herdr-app" <<'H'
#!/bin/sh
d=$(mktemp "$STUB_DIR/app.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
if [ -f "$STUB_DIR/app-down" ]; then echo "no Herdr window" >&2; exit 2; fi
case "$1" in
  ls) cat "$STUB_DIR/app-ls.json" ;;
  do) printf '%s\n' '{"ok":true}' ;;
  *) printf '%s\n' '{"ok":true}' ;;
esac
H
cat >"$T/bin/herdr" <<'H'
#!/bin/sh
d=$(mktemp "$STUB_DIR/herdr.XXXXXX")
jq -nc '$ARGS.positional' --args -- "$@" >"$d"
printf '%s\n' '{"result":{}}'
H
chmod +x "$T/bin/hc" "$T/bin/herdr-app" "$T/bin/herdr"
export HERDR_BIN_PATH="$T/bin/herdr" HC_BIN_PATH="$T/bin/hc" HERDR_APP_BIN_PATH="$T/bin/herdr-app"
export STUB_DIR="$T" GBB_STATE_DIR="$T/state" GBB_DATA_DIR="$T/data" GBB_CONFIG="$T/config.toml" GBB_HC_WATCH_ONCE=1
unset GBB_WEBHOOK_URL GBB_WEBHOOK_HEADER_NAME GBB_WEBHOOK_HEADER_VALUE GBB_OWNER GBB_BACKEND 2>/dev/null || true
git -C "$T/repo" init -q
git -C "$T/repo" config user.email t@example.com
git -C "$T/repo" config user.name t
echo x >"$T/repo/f" && git -C "$T/repo" add f && git -C "$T/repo" commit -qm init
cat >"$T/config.toml" <<'TOML'
backend = "hc"
startup_settle_sec = 0
startup_ready_timeout_sec = 8
webhook_timeout_sec = 1
debounce_sec = 0
TOML
chmod 600 "$T/config.toml"
jq -n --arg c "$T/repo" '{address:"t9",state:"live",status:{state:"idle",app:"grok"},reported:true,cwd:$c,labels:{},turn:0,title:""}' >"$T/get.json"
printf '%s\n' '{"terminals":[]}' >"$T/hc-ls.json"
printf '%s\n' '{"spaces":[]}' >"$T/app-ls.json"
fail() { echo "FAIL: $*"; echo "--- hc ---"; cat "$T"/call.* 2>/dev/null | jq -s . || true; echo "--- app ---"; cat "$T"/app.* 2>/dev/null | jq -s . || true; echo "--- log ---"; cat "$T/state/bridge.log" 2>/dev/null || true; exit 1; }
reset_calls() {
  if [ -f "$T/state/hc-watch.pid" ]; then
    kill "$(cat "$T/state/hc-watch.pid")" 2>/dev/null || true
    sleep 0.1
  fi
  rm -f "$T"/call.* "$T"/app.* "$T"/herdr.*
  rm -f "$T/state/managed.json" "$T/state/hc-watch.pid"
  rm -rf "$T/data/worktrees" "$T/state/last" "$T/state/pending"
}
runs() { cat "$T"/call.* 2>/dev/null | jq -s 'map(select(.[0]=="run"))'; }
apps() { cat "$T"/app.* 2>/dev/null | jq -s .; }
labels_of() { # labels_of <json-array-file-via-stdin> key
  jq -r --arg k "$1" 'map(select(type=="string" and startswith($k))) | .[0] // empty'
}
# Our tab id is new (tb + 32 hex). It must not be a tab that already existed.
no_tab() {
  cat "$T"/call.* 2>/dev/null | jq -s -e '
    [map(.[]) | .[] | select(type=="string" and startswith("herdr.tab="))] as $t
    | ($t | length) >= 1 and ($t | all(test("^herdr\\.tab=tb[0-9a-f]{32}$")))' >/dev/null \
    || fail "herdr.tab was not a new id: $(cat "$T"/call.* 2>/dev/null | jq -s .)"
}
# The app titles a tab gbb created. It does not retitle a tab it did not create.
expect_mark() { # expect_mark <task-id>
  em_tab=$(cat "$T"/call.* 2>/dev/null | jq -s -r --arg t "$1" '
    ([map(select(.[0]=="run")) | .[] | select(index("gbb_task=" + $t)) | .[] | select(startswith("herdr.tab="))][0] // "") as $a
    | if $a != "" then $a else
        ([map(select(.[0]=="label")) | .[] | .[] | select(startswith("herdr.tab="))][-1] // "")
      end | sub("^herdr\\.tab=";"")') || em_tab=""
  apps | jq -e --arg id "$em_tab" --arg name "gbb · $1" '
    [.[] | select(.[0]=="do" and .[1]=="tab.rename")] as $r
    | ($r | map(.[2] | fromjson | select(.id == $id and .name == $name)) | length) == 1
    and ($id | test("^tb[0-9a-f]{32}$"))' >/dev/null \
    || fail "tab mark for $1 (tab=$em_tab): $(apps)"
}
no_space_close() {
  cat "$T"/app.* 2>/dev/null | jq -s -e '[.[] | select(.[0]=="do") | .[1]] | map(select(.=="space.close" or .=="tab.close")) | length == 0' >/dev/null \
    || fail "app closed a space or tab: $(apps)"
}

# --- a terminal launched in the checkout beats an active space that is only named like the repo ---
# The checkout space's folder is deliberately wrong. Folder is not a match.
reset_calls
rm -f "$T/app-down"
jq -n --arg repo "$T/repo" --arg else "$T/elsewhere" '{spaces:[
  {id:"spNAME",name:"repo",folder:$repo,machine:null,active:true,tabs:[]},
  {id:"spREPO",name:"custom",folder:$else,machine:null,active:false,tabs:[{id:"tb1",name:"1",terminals:[{terminal:"t1"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg repo "$T/repo" '{terminals:[{address:"t1",cwd:$repo,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task folder --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.ok == true and .backend == "hc" and .herdr_space == "spREPO" and .created_herdr_space == false and .workspace_id == null' >/dev/null \
  || fail "checkout match: $out"
run=$(runs | jq -c '.[0]')
printf '%s' "$run" | jq -e 'index("--keep") and index("herdr.space=spREPO") and (.[index("--cwd")+1] != "")' >/dev/null || fail "checkout run: $run"
no_tab
no_space_close
apps | jq -e '[.[] | select(.[0]=="do" and .[1]=="space.rename")] | length == 0' >/dev/null || fail "renamed a reused space: $(apps)"
expect_mark folder
[ "$("$ROOT/bin/gbb" list | jq -r '.managed[0].herdr_space')" = spREPO ] || fail "registry space"

# --- terminal launch cwd matches when the space folder does not ---
reset_calls
jq -n --arg else "$T/elsewhere" '{spaces:[
  {id:"spCWD",name:"scratch",folder:$else,machine:null,active:false,tabs:[{id:"tb9",name:"1",terminals:[{terminal:"t1"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg repo "$T/repo" '{terminals:[{address:"t1",cwd:$repo,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task bycwd --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spCWD" and .created_herdr_space == false' >/dev/null || fail "cwd match: $out"
printf '%s' "$(runs | jq -c '.[0]')" | jq -e 'index("herdr.space=spCWD")' >/dev/null || fail "cwd run"
no_tab

# --- display name, when nothing else matches ---
reset_calls
jq -n --arg else "$T/elsewhere" '{spaces:[
  {id:"spBYNAME",name:"repo",folder:$else,machine:null,active:false,tabs:[]}
]}' >"$T/app-ls.json"
printf '%s\n' '{"terminals":[]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task byname --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spBYNAME" and .created_herdr_space == false' >/dev/null || fail "name match: $out"
no_tab

# --- same checkout: the space named after the repo beats the active one; else the active one ---
reset_calls
jq -n --arg repo "$T/repo" '{spaces:[
  {id:"spNAMED",name:"repo",folder:"/stale",machine:null,active:false,tabs:[{id:"tbA",name:"1",terminals:[{terminal:"tA"}]}]},
  {id:"spACTIVE",name:"other",folder:$repo,machine:null,active:true,tabs:[{id:"tbB",name:"1",terminals:[{terminal:"tB"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg repo "$T/repo" '{terminals:[{address:"tA",cwd:$repo,state:"live"},{address:"tB",cwd:$repo,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task tie-name --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spNAMED"' >/dev/null || fail "name tie-break: $out"
reset_calls
jq -n --arg repo "$T/repo" '{spaces:[
  {id:"spFIRST",name:"a",folder:$repo,machine:null,active:false,tabs:[{id:"tbA",name:"1",terminals:[{terminal:"tA"}]}]},
  {id:"spACTIVE",name:"b",folder:$repo,machine:null,active:true,tabs:[{id:"tbB",name:"1",terminals:[{terminal:"tB"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg repo "$T/repo" '{terminals:[{address:"tA",cwd:$repo,state:"live"},{address:"tB",cwd:$repo,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task tie --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spACTIVE"' >/dev/null || fail "active tie: $out"

# --- a worktree launch still uses the main repo's space, and does not split its tab ---
reset_calls
jq -n --arg repo "$T/repo" '{spaces:[
  {id:"spREPO",name:"custom",folder:"/stale",machine:null,active:true,tabs:[{id:"tb1",name:"1",terminals:[{terminal:"t1"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg repo "$T/repo" '{terminals:[{address:"t1",cwd:$repo,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task wt1 --prompt "hi")
wt=$(printf '%s' "$out" | jq -r .worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spREPO" and .created_herdr_space == false' >/dev/null || fail "worktree place: $out"
printf '%s' "$(runs | jq -c '.[0]')" | jq -e --arg wt "$wt" --arg repo "$T/repo" '
  (.[index("--cwd")+1] == $wt) and ($wt != $repo) and index("herdr.space=spREPO")
  and (map(select(startswith("herdr.tab="))) | .[0] | test("^herdr\\.tab=tb[0-9a-f]{32}$"))' >/dev/null || fail "worktree run cwd: $(runs)"
no_tab

# --- the reported Mac layout: main checkout beats an active Herdr worktree of the same repo.
# Space folder fields are stale (mosa-next and Phoobot-Skills both claim instant-chat) and are ignored.
reset_calls
M=$T/ws/mosa-next
IC=$T/instant-chat
BOX=$T/.herdr/worktrees/mosa-next/bytebox-test
mkdir -p "$M" "$IC"
git -C "$M" init -q
git -C "$M" config user.email t@example.com
git -C "$M" config user.name t
echo m >"$M/f" && git -C "$M" add f && git -C "$M" commit -qm init
git -C "$IC" init -q
git -C "$IC" config user.email t@example.com
git -C "$IC" config user.name t
echo i >"$IC/f" && git -C "$IC" add f && git -C "$IC" commit -qm init
git -C "$M" worktree add -q "$M/.worktrees/botmux-card-button-adr-20261102" -b botmux
git -C "$M" worktree add -q "$BOX" -b bytebox-test
jq -n --arg ic "$IC" --arg box "$BOX" '{spaces:[
  {id:"sp09d75056770cf5768aeea2d61945c758", name:"mosa-next", folder:$ic, machine:null, active:false,
    tabs:[{id:"tb12488da7205dcedf9e4a4d0b7e2cbf47", name:"1", terminals:[{terminal:"t12"},{terminal:"t1g"}]}]},
  {id:"sp6ac043a819137bd811eb4f7b1820ddd8", name:"bytebox-test", folder:$box, machine:null, active:true,
    tabs:[{id:"tbBOX", name:"1", terminals:[{terminal:"t18"},{terminal:"t19"}]}]},
  {id:"spINSTANT", name:"instant-chat", folder:$ic, machine:null, active:false, tabs:[]},
  {id:"spPHOO", name:"Phoobot-Skills", folder:$ic, machine:null, active:false, tabs:[]}
]}' >"$T/app-ls.json"
jq -n --arg m "$M" --arg wt "$M/.worktrees/botmux-card-button-adr-20261102" --arg box "$BOX" '{terminals:[
  {address:"t12", cwd:$m, state:"live"},
  {address:"t1g", cwd:$wt, state:"live"},
  {address:"t18", cwd:$box, state:"live"},
  {address:"t19", cwd:$box, state:"live"}
]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$M" --kind grok --task place1 --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "sp09d75056770cf5768aeea2d61945c758" and .created_herdr_space == false' >/dev/null \
  || fail "mosa-next space: $out"
no_tab
out=$("$ROOT/bin/gbb" launch --repo "$IC" --kind grok --task place-ic --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spINSTANT" and .created_herdr_space == false' >/dev/null \
  || fail "stale folder did not steal instant-chat: $out"

# A Herdr worktree space alone is not the main checkout.
reset_calls
jq -n --arg box "$BOX" '{spaces:[
  {id:"sp6ac043a819137bd811eb4f7b1820ddd8", name:"bytebox-test", folder:$box, machine:null, active:true,
    tabs:[{id:"tbBOX", name:"1", terminals:[{terminal:"t18"},{terminal:"t19"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg box "$BOX" '{terminals:[{address:"t18",cwd:$box,state:"live"},{address:"t19",cwd:$box,state:"live"}]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$M" --kind grok --task place-box --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.created_herdr_space == true and .herdr_space != "sp6ac043a819137bd811eb4f7b1820ddd8"' >/dev/null \
  || fail "herdr worktree space was reused: $out"

# A gbb worktree of this repo beats that Herdr worktree space.
reset_calls
mkdir -p "$T/data/worktrees"
git -C "$M" worktree add -q "$T/data/worktrees/mosa-next-old" -b gbb-old
jq -n --arg box "$BOX" '{spaces:[
  {id:"spGBB", name:"old", folder:"/stale", machine:null, active:false,
    tabs:[{id:"tbG", name:"1", terminals:[{terminal:"tG"}]}]},
  {id:"sp6ac043a819137bd811eb4f7b1820ddd8", name:"bytebox-test", folder:$box, machine:null, active:true,
    tabs:[{id:"tbBOX", name:"1", terminals:[{terminal:"t18"}]}]}
]}' >"$T/app-ls.json"
jq -n --arg g "$T/data/worktrees/mosa-next-old" --arg box "$BOX" '{terminals:[
  {address:"tG", cwd:$g, state:"live"},
  {address:"t18", cwd:$box, state:"live"}
]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$M" --kind grok --task place-gbb --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spGBB" and .created_herdr_space == false' >/dev/null \
  || fail "gbb worktree space: $out"

# --- remote space is ignored; a new id is minted and renamed to the repo directory ---
reset_calls
jq -n --arg repo "$T/repo" '{spaces:[
  {id:"spREMOTE",name:"repo",folder:$repo,machine:"vps",active:true,tabs:[]}
]}' >"$T/app-ls.json"
printf '%s\n' '{"terminals":[]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task fresh --prompt "hi" --no-worktree)
sp=$(printf '%s' "$out" | jq -r .herdr_space)
printf '%s' "$out" | jq -e '.created_herdr_space == true and (.herdr_space | test("^sp[0-9a-f]{32}$")) and .herdr_space != "spREMOTE"' >/dev/null \
  || fail "mint: $out"
printf '%s' "$(runs | jq -c '.[0]')" | jq -e --arg s "herdr.space=$sp" 'index($s)' >/dev/null || fail "mint label: $(runs)"
no_tab
apps | jq -e --arg sp "$sp" '
  [.[] | select(.[0]=="do" and .[1]=="space.rename")] as $r
  | ($r | length) == 1 and ($r[0][2] | fromjson | .id == $sp and .name == "repo")' >/dev/null \
  || fail "rename: $(apps)"
expect_mark fresh
no_space_close
stop=$("$ROOT/bin/gbb" stop fresh)
printf '%s' "$stop" | jq -e '.ok == true and .origin == "launched"' >/dev/null || fail "stop: $stop"
cat "$T"/call.* | jq -s -e 'map(select(.[0]=="kill")) | length == 1' >/dev/null || fail "stop did not kill"
cat "$T"/call.* | jq -s -e 'map(select(.[0]=="rm")) | length == 1' >/dev/null || fail "stop did not rm"
no_space_close

# --- window down: reuse herdr.space from a terminal already in the repo; do not rename ---
reset_calls
printf 'down\n' >"$T/app-down"
jq -n --arg repo "$T/repo" '{terminals:[{address:"t1",cwd:$repo,state:"live",where:"repo / 1"}]}' >"$T/hc-ls.json"
jq -n --arg c "$T/repo" '{address:"t1",state:"live",cwd:$c,labels:{"herdr.space":"spFROM","herdr.tab":"tbFROM"},status:{state:"idle",app:"grok"},reported:true}' >"$T/get-t1.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task offline --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.herdr_space == "spFROM" and .created_herdr_space == false' >/dev/null || fail "offline reuse: $out"
no_tab
apps | jq -e '[.[] | select(.[0]=="do")] | length == 0' >/dev/null || fail "renamed while the window was down: $(apps)"

# --- window down and nothing placed yet: mint, and do not call herdr-app do ---
reset_calls
printf '%s\n' '{"terminals":[]}' >"$T/hc-ls.json"
out=$("$ROOT/bin/gbb" launch --repo "$T/repo" --kind grok --task offline-new --prompt "hi" --no-worktree)
printf '%s' "$out" | jq -e '.created_herdr_space == true and (.herdr_space | test("^sp[0-9a-f]{32}$"))' >/dev/null || fail "offline mint: $out"
no_tab
apps | jq -e '[.[] | select(.[0]=="do")] | length == 0' >/dev/null || fail "do while down: $(apps)"

# --- handover keeps an existing space and tab; it does not retitle that tab ---
reset_calls
rm -f "$T/app-down"
jq -n --arg c "$T/repo" '{address:"t4",state:"live",cwd:$c,name:"zsh",labels:{"herdr.space":"spKEEP","herdr.tab":"tbKEEP"},status:{state:"idle"}}' >"$T/get-t4.json"
ho=$("$ROOT/bin/gbb" handover --pane t4 --backend hc)
printf '%s' "$ho" | jq -e '.ok == true and .entry.herdr_space == "spKEEP" and .entry.created_herdr_space == false and .entry.created_terminal == false' >/dev/null \
  || fail "handover keep: $ho"
lab=$(cat "$T"/call.* | jq -s 'map(select(.[0]=="label")) | .[0]')
printf '%s' "$lab" | jq -e 'index("grokbot=managed") and (map(select(startswith("herdr.space=") or startswith("herdr.tab="))) | length) == 0' >/dev/null \
  || fail "handover relabeled space: $lab"
[ -z "$(ls "$T"/app.* 2>/dev/null || true)" ] || fail "handover of a placed terminal called herdr-app"

# --- handover of an unlabeled terminal joins the repo space, new tab ---
reset_calls
rm -f "$T/get-t4.json"
jq -n --arg c "$T/repo" '{address:"t5",state:"live",cwd:$c,name:"zsh",labels:{},status:{state:"idle"}}' >"$T/get-t5.json"
jq -n --arg repo "$T/repo" '{spaces:[{id:"spREPO",name:"repo",folder:$repo,machine:null,active:true,tabs:[]}]}' >"$T/app-ls.json"
printf '%s\n' '{"terminals":[]}' >"$T/hc-ls.json"
ho=$("$ROOT/bin/gbb" handover --pane t5 --backend hc)
printf '%s' "$ho" | jq -e '.ok == true and .entry.herdr_space == "spREPO" and .entry.created_herdr_space == false and .entry.origin == "handover"' >/dev/null \
  || fail "handover place: $ho"
lab=$(cat "$T"/call.* | jq -s 'map(select(.[0]=="label")) | .[0]')
printf '%s' "$lab" | jq -e 'index("herdr.space=spREPO") and (map(select(startswith("herdr.tab="))) | .[0] | test("^herdr\\.tab=tb[0-9a-f]{32}$"))' >/dev/null \
  || fail "handover label: $lab"
expect_mark "$(printf '%s' "$ho" | jq -r .entry.task_id)"
apps | jq -e '[.[] | select(.[0]=="do" and .[1]=="space.rename")] | length == 0' >/dev/null || fail "handover renamed a space: $(apps)"
no_space_close

echo "place-test: PASS"
