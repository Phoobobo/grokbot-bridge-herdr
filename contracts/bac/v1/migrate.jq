# gbb registry v1 -> bac.registry.v1. All-or-nothing: error() fails the filter.
def kind_support($k):
  if $k == "grok" or $k == "codex" then "supported"
  elif $k == "pi" or $k == "antigravity" then "rejected"
  else "unknown" end;

def fake_pane($p):
  $p == "planned" or $p == "pending" or $p == "unknown" or $p == "fake" or $p == "placeholder";

def secret_key($k):
  $k == "header_value" or $k == "token" or $k == "secret" or $k == "password" or $k == "authorization";

if any(paths | .[-1] | strings; secret_key(.)) then
  error("secret field")
elif (.version != 1) then
  error("registry version")
else
  .panes as $panes
  | {
      schema: "bac.registry.v1",
      migrated_from: "gbb-registry-v1",
      panes: (
        $panes
        | to_entries
        | map(
            .key as $key
            | .value as $e
            | if ($e | type) != "object" then error("pane not object")
              elif ($e.pane_id | type) != "string" or $e.pane_id == "" then error("missing pane_id")
              elif ($e.pane_id | test("[[:space:]]")) then error("pane_id whitespace")
              elif fake_pane($e.pane_id) then error("fake pane_id")
              elif $e.pane_id != $key then error("key mismatch")
              elif (($e.owner != null) and (($e.owner | type) != "string" or ($e.owner | test("^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$") | not))) then error("bad owner")
              elif (($e.backend != null) and $e.backend != "herdr" and $e.backend != "hc") then error("bad backend")
              else
                ($e.kind // null) as $kr
                | ($e.backend // "herdr") as $be
                | {
                    key: $e.pane_id,
                    value: {
                      pane_id: $e.pane_id,
                      task_id: ($e.task_id // null),
                      owner: ($e.owner // null),
                      backend: $be,
                      kind: (if $kr == "grok" or $kr == "codex" then $kr else null end),
                      kind_reported: (if $kr == null then null else $kr end),
                      kind_support: (if $kr == null then "unknown" else kind_support($kr) end),
                      origin: ($e.origin // null),
                      agent_name: ($e.agent_name // null),
                      legacy_agent_name: ($e.agent_name // null),
                      workspace_id: ($e.workspace_id // null),
                      repo: ($e.repo // null),
                      worktree: ($e.worktree // null),
                      branch: ($e.branch // null),
                      created_terminal: ($e.created_terminal // false),
                      created_workspace: ($e.created_workspace // false),
                      armed: (if $e.armed == null then true else $e.armed end),
                      last_status: ($e.last_status // null),
                      legacy_labels: {grokbot: "managed", gbb_task: ($e.task_id // null)}
                    }
                  }
              end
          )
        | from_entries
      )
    }
end
