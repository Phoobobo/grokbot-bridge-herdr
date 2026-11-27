# Bounded validation and disabled Dots probes

## Context

The Mac handoff prohibits the aggregate test runner and lock, kill,
concurrency, capacity and fault probes, including on other machines.
The old CI runner includes these probes; bac-callers-test.sh also contains
concurrency cases. Publishing must not indirectly replay them in Actions.
An isolated loopback receiver also must not inspect the production Dots token.

## Decision

CI explicitly runs the reviewed offline contract/fixture migration check,
shellcheck and syntax parsing. It does not discover or run all test scripts.
The existing probe scripts are retained as historical material, not executed.
An explicitly disabled Dots module returns before inspecting its token-file
path or probing its endpoint. Automatic and explicitly enabled modes retain
their existing behavior.

## Consequences

A green CI proves only the listed checks, not runtime or Mac E2E acceptance.
Additional normal-path checks must be reviewed before adding them. Real
acceptance still needs an isolated receiver, a real completion callback and
matching task/pane/owner/assignment evidence. Disabling Dots is sufficient
to prevent its probe.

`BAC_ISOLATED_SCOPE` adds a backend label to newly launched hc terminals and
filters `hc events` by that label on the server. Placement creates fresh space
and tab ids without enumerating existing terminals or the app. Naming skips
app discovery. The mode requires explicit state/data/config and disabled Dots;
it forces hc for launch, disables list discovery, and permits handover only
for a terminal carrying the same scope label. Webhook environment overrides
are ignored so routing comes only from the dedicated config. Ordinary unscoped behavior is
unchanged. This is a local routing boundary, not authentication: scope strings
and state paths must be new and chosen by the trusted operator.

Live Codex 0.172 displayed a numbered folder-trust screen ending in
`enter continue`, outside the older classifier's `submit|confirm` forms.
Treat that screen as a dialog. A readiness timeout must preserve the prompt
and report `prompt_not_submitted`, not attempt to send it anyway. Recheck
Codex dialogs before each prompt retry. These checks do not select an option;
only an explicit caller answer/keys instruction can do that.
