# grokbot-bridge-herdr

[中文](#中文) · [English](#english)

## 中文

让 Grok Bot 通过 [Herdr](https://herdr.dev) 驱动和监控你本机的编码 agent（grok、codex），并且可以把你自己的某些窗格交给 Grok Bot 接管、随时收回。

> **也可以给 ChatGPT dots 用。** 除了 Grok Bot，ChatGPT 的 dot 也能用同一套 gbb 驱动本机 agent、接收状态推送。这要借助配套的 MCP 服务 **[dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge)**（基于 [uezo/dots-bridge](https://github.com/uezo/dots-bridge) 的 fork），它跑在本机 `127.0.0.1`，经 **OpenAI Secure MCP Tunnel** 暴露给 ChatGPT（无入站端口）。见下文 [配合 ChatGPT dots 使用](#配合-chatgpt-dots-使用)。

- **状态回调**：Herdr 插件监听 `pane.agent_status_changed`，只对“托管窗格”生效；agent 进入 `done` / `idle` / `blocked` 时向 Grok Bot 的 webhook 发一条很小的 JSON（不含终端输出、不含密钥），带去重，后台 curl 不会卡住 Herdr。
- **托管窗格登记表**：`~/.local/state/grokbot-bridge-herdr/managed.json`，按 pane id 记录 task、agent 名称、类型、仓库、worktree、来源（launched / handover）。
- **交接 / 收回**：在 Herdr 命令面板对当前窗格执行 “Grok Bot: take over this pane” 或 “Grok Bot: give this pane back to me”。托管窗格会显示 `🤖 Grok Bot: <task>` 标记。
- **`gbb` 命令行**：Grok Bot 通过远程 shell 调用，全部 JSON 输出：`launch / list / status / read / send / answer / keys / owner / wait / result / stop / handover / reclaim / doctor / test-webhook`。
- **谁启动、回调给谁（owner）**：`gbb launch --owner <名字>`（或环境变量 `GBB_OWNER`）记录任务的 owner；配置里的 `[[owners]]` 给每个 owner 一个 webhook。状态变化只发给该 owner；没有 owner、owner 没配置或投递失败时回落到主 webhook（payload 带 `owner`、`route`、`fallback_reason`）。见下文 [多个调用方](#多个调用方owner-回调)。

### 安装

```sh
git clone git@github.com:Phoobobo/grokbot-bridge-herdr.git ~/Workspace/grokbot-bridge-herdr
cd ~/Workspace/grokbot-bridge-herdr && ./install.sh      # 软链 gbb 到 ~/.local/bin，并 herdr plugin link
mkdir -p ~/.config/grokbot-bridge-herdr
cp config.example.toml ~/.config/grokbot-bridge-herdr/config.toml
chmod 600 ~/.config/grokbot-bridge-herdr/config.toml     # 不是 600 就拒绝发送
# 编辑 config.toml：填 webhook_url、webhook_header_name、webhook_header_value（从 Grok Bot routine 面板复制）
gbb doctor && gbb test-webhook
```

依赖：herdr ≥ 0.9.0、jq、git、curl（macOS 自带 jq/curl/git）。卸载：`./uninstall.sh`（保留配置、登记表、日志和 worktree）。

### 快捷键（可选）

在 `~/.config/herdr/config.toml` 里加（先确认按键没被占用），然后 `herdr server reload-config`：

```toml
[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "phoobobo.grokbot-bridge.handover"
description = "hand pane to Grok Bot"

[[keys.command]]
key = "prefix+G"
type = "plugin_action"
command = "phoobobo.grokbot-bridge.reclaim"
description = "take pane back from Grok Bot"
```

### 安全边界

- 只处理登记过的窗格；`gbb stop` 只关闭 gbb 自己创建的工作区，交接来的窗格只注销、不关闭。
- 从不执行 `herdr server stop`；从不在 Grok 的 “Help improve Grok” 横幅上选 Opt in。
- webhook 只含 id 和状态；鉴权 header 通过 stdin 传给 curl，不出现在进程列表；日志只记录主机名。
- 可选 `allowed_repos` 限制 `gbb launch` 能用的仓库。

### 配合 ChatGPT dots 使用

配套的 MCP 服务 [dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge)（fork 自 [uezo/dots-bridge](https://github.com/uezo/dots-bridge)，经 OpenAI Secure MCP Tunnel 暴露给 ChatGPT）把 `gbb` 包装成 MCP 工具，让 ChatGPT 的 dot 也能驱动本机 coding agent。工具实现在 dots-tunnel-bridge 的 `src/dots_bridge/herdr_tools.py`，设 `DOTS_BRIDGE_HERDR_TOOLS=1` 才启用；完整说明见它的 [docs/HERDR.md](https://github.com/Phoobobo/dots-tunnel-bridge/blob/main/docs/HERDR.md)。

设置步骤：

1. 按本 README 安装 gbb，`gbb doctor` 正常。
2. 按 [dots-tunnel-bridge README](https://github.com/Phoobobo/dots-tunnel-bridge#安装人工步骤) 装好 bridge + tunnel-client，并在 ChatGPT 里添加该 MCP server（Connection: Tunnel）。
3. 生成 token 文件 `~/.config/dots-bridge/herdr_webhook_token`（mode 600），在 bridge 的 plist 里打开 `DOTS_BRIDGE_HERDR_TOOLS=1` 并重启 bridge。
4. 在 `~/.config/grokbot-bridge-herdr/config.toml` 末尾加 `[[extra_webhooks]]`（见下方 English 部分的示例），`gbb test-webhook` 测试。
5. ChatGPT 插件页 **Refresh** 工具，确认出现 13 个 `gbb_*`；让 dot 订阅 `app.message.created`（channel `herdr`，否则落到 `default`）。

要点：

- 工具：`gbb_list` / `gbb_status` / `gbb_read` / `gbb_result` / `gbb_doctor` / `gbb_wait`（最长 120 秒）只读；`gbb_launch`（自动附加“只开 draft PR”的要求，并带 `--owner dot`）/ `gbb_send` / `gbb_answer` / `gbb_keys` / `gbb_stop` / `gbb_handover` / `gbb_reclaim` 会改动状态。
- 回调归属：dot 启动的任务 owner 为 `dot`，配好 `[[owners]] name = "dot"` 后只回调给 dot（失败才回落到 Grok Bot 的主 webhook），见上文 [多个调用方](#多个调用方owner-回调)。
- 每个工具都以参数列表调用 `gbb`（不经过 shell），带超时和输入校验；send/keys/stop/reclaim 只作用于托管窗格，默认保护工作区 `wAS`、`wAT`（除非窗格是主动交接的）。
- 状态推送：在 `config.toml` 末尾加 `[[extra_webhooks]]`，指向 `http://127.0.0.1:8765/herdr/webhook`，header `X-Dots-Herdr-Token`，值为 `~/.config/dots-bridge/herdr_webhook_token` 的内容。gbb 对每个目标各发一份相同的 payload，原 Grok Bot webhook 不受影响；dots-tunnel-bridge 只接受本机请求，并把它变成 `herdr`（没有则 `default`）频道的 `app.message.created` 消息，`metadata.source = "herdr"`。
- 改了工具后要在 ChatGPT 插件页刷新（Refresh）dot 的工具。设计见 [docs/decisions/0003](docs/decisions/0003-dots-bridge-tools-and-extra-webhooks.md)。

### 多个调用方（owner 回调）

同一台机器上可能有几个调用方在用 gbb：你的 Grok Bot、另一个 Grok Bot（比如“参谋长”）、ChatGPT dot。给任务标上 owner，回调就只发给启动它的人：

```toml
# ~/.config/grokbot-bridge-herdr/config.toml 末尾（mode 600）
[[owners]]
name = "dot"                                   # dots-tunnel-bridge 的 gbb_launch 自动带 --owner dot
url = "http://127.0.0.1:8765/herdr/webhook"
header_name = "X-Dots-Herdr-Token"
header_value = "<~/.config/dots-bridge/herdr_webhook_token 的内容>"

[[owners]]
name = "canmouzhang"                           # 另一个 Grok Bot：在它那边建 webhook routine，把 URL 和 key 填这里
url = "<那个 routine 的 webhook URL>"
header_name = "<routine 面板上的 header 名>"
header_value = "<routine 面板上的 key>"
```

- 启动：`gbb launch ... --owner canmouzhang`，或先 `export GBB_OWNER=canmouzhang`；`gbb handover --owner`、`gbb owner <task> <名字>|--clear` 可补设/改。
- 路由：有 owner 且已配置 → 只发 owner（`route: owner`）；投递失败（curl 出错或非 2xx）→ 再发主 webhook（`route: fallback`, `fallback_reason: owner_delivery_failed`）；没有 owner → 主 webhook（`route: primary`）；owner 未配置 → 主 webhook（`fallback_reason: owner_not_configured`）。
- `[[extra_webhooks]]` 行为不变（每个事件都收），只是 URL 与 owner 目标相同的会跳过，避免同一事件发两遍。想让 dot 只收自己的任务：删掉 extra，只留 `[[owners]] name = "dot"`。
- 检查：`gbb doctor`（只显示 owner 名和主机）、`gbb test-webhook --owner <名字>`。设计见 [docs/decisions/0004](docs/decisions/0004-owner-routed-callbacks-and-codex-screens.md)。

### Codex

`gbb launch --kind codex` 同样可用（herdr 0.9.3 + codex-cli 0.164.0 起已测；最近一次：herdr 0.9.5 + codex-cli 0.165.0。herdr 0.9.5 起 codex 状态改为读屏判断，不再依赖 codex 的 turn hooks，gbb 无需改动）。注意：

- 新目录首次启动会弹 “Trust this folder?”，项目有 hooks 时还会弹 “Hooks need review”。gbb 不会往对话框里打字：返回 `state: startup_blocked`（含 `blocked_reason`、屏幕内容），把 prompt 存起来并发一条 `blocked` 回调。调用方看清后 `gbb answer <task> <选项号|文字>`（例如 hooks 界面 2 = 全部信任，3 = 不信任继续；gbb 从不自己替你信任 hooks），答完后存着的 prompt 会自动发出；也可 `gbb send <task> --pending` 手动发。
- Codex 提问（屏幕上 “? 1 question / ⇧← to answer”）时 `gbb send` 会拒绝并提示用 `gbb answer <task> <选项>`：它会按 shift+left 打开问题、上下移动到目标选项并核对、回车。手动方式：`gbb keys <task> shift+left`，`gbb keys <task> down`…，`gbb keys <task> enter`。
- 状态纠正：herdr 0.9.5 把 hooks 对话框报成 `idle`、把从没跑过的新会话（`Context 0% used · 0 in · 0 out`）报成 `done`。gbb 会读屏改成 `blocked`（`blocked_reason`: `hooks_review` / `question` / `dialog` / `prompt_not_submitted`），不再发假的 `done`。
- 模型没生效？`codex_args` 为空时 codex 用 `~/.codex/config.toml` 顶层的 `model` / `model_reasoning_effort`。`gbb doctor` 会显示 `codex_user_defaults`；`gbb launch`/`gbb status` 显示 Codex 底栏里的实际模型（`agent_model`，如 “GPT-6.1-Sol xhigh”）。要固定就在 gbb 配置里写 `codex_args`。
- herdr 目前拿不到 codex 的 session id，`gbb result` 给出 `cd <worktree> && codex resume --last`。
- 模型/推理强度：不带 `-- <agent args>` 时，gbb 使用配置里的 `codex_args` / `grok_args`（单行字符串数组，每项原样作为一个参数传给 agent）；都没有时用 agent 自己的默认值（codex 读 `~/.codex/config.toml`）。例：`codex_args = ["-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=\"xhigh\""]`。显式 `--`（哪怕后面为空）会覆盖配置。codex 0.165 可用的 effort：low / medium / high / xhigh（Extra high）/ max / ultra。
- 首条 prompt：codex 报 ready 后可能还在加载（动画 splash），会吞掉输入。gbb 先等真正的 `›` 输入框和底栏出现、没有对话框、屏幕连续几次轮询不变（`startup_ready_timeout_sec`，默认 90），再发送；发送后若 herdr 报 stalled，先看 agent 是否其实已在工作、文字是否停在输入框（只补一次回车），确认没有送达才重发，不会重复提交；发出后再确认 Codex 确实开始了这一轮。
- `codex exec --json` 适合无界面的一次性任务；`codex app-server` 仍是实验性接口。走 herdr 的好处是窗格可见、可接管、状态统一。

## English

Let Grok Bot drive and watch local coding agents (grok, codex) through [Herdr](https://herdr.dev), and let you hand some of your own panes over to Grok Bot and take them back.

> **Also works with ChatGPT dots.** Besides Grok Bot, a ChatGPT dot can drive the same agents through gbb and get their status pushed to it. This goes through the companion MCP server **[dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge)** (a fork of [uezo/dots-bridge](https://github.com/uezo/dots-bridge)), which runs on `127.0.0.1` and is exposed to ChatGPT via **OpenAI Secure MCP Tunnel** (no inbound ports). See [Use with ChatGPT dots](#use-with-chatgpt-dots).

- **Status webhook** — the plugin hooks `pane.agent_status_changed`, acts only on managed panes, and POSTs a small JSON (no terminal output, no secrets) on `done` / `idle` / `blocked`. Debounced; curl runs in the background with a short timeout, so Herdr never blocks.
- **Managed-pane registry** — `~/.local/state/grokbot-bridge-herdr/managed.json`, keyed by pane id: task id, agent name, kind, repo, worktree, origin (`launched` | `handover`).
- **Handover / reclaim** — pane actions in the Herdr command palette: "Grok Bot: take over this pane" and "Grok Bot: give this pane back to me". Managed panes show a `🤖 Grok Bot: <task>` marker.
- **`gbb` CLI** — what Grok Bot calls over remote shell; every command prints JSON.
- **Owner-routed callbacks** — `gbb launch --owner <name>` (or `GBB_OWNER`) records who launched a task; `[[owners]]` in the config gives each owner a webhook. Status callbacks go to that owner; with no owner, an unconfigured owner, or a failed delivery they fall back to the primary webhook. See [Several callers](#several-callers-owner-routed-callbacks).

### Install

See the Chinese section above for the commands (`./install.sh`, copy `config.example.toml` to `~/.config/grokbot-bridge-herdr/config.toml`, `chmod 600`, fill `webhook_url` + `webhook_header_name` + `webhook_header_value` from the Grok Bot routine panel, then `gbb doctor && gbb test-webhook`). Optional keybindings are shown above.

### Commands

```text
gbb launch --repo <path> --kind grok|codex --task <id> [--worktree <branch>|--no-worktree] [--base <ref>]
           (--prompt <text> | --prompt-file <f>) [--owner <name>] [-- <agent args>]
    git worktree under ~/.local/share/grokbot-bridge-herdr/worktrees/<repo>-<task> (branch gbb/<task>),
    new Herdr workspace with --no-focus, `herdr agent start` with retry, settle, prompt with stall retry,
    registers the pane. Without `--`, uses codex_args / grok_args from the config. Waits for the input box
    before the first prompt. Returns task_id, pane_id, agent_name, kind, agent_args, worktree, branch, owner,
    agent_model (codex footer), status, session_id, prompt_pending, prompt_error — or state:"startup_blocked"
    with blocked_reason + screen when a startup dialog is showing (the prompt is kept, not typed).
gbb list                          managed panes + live status
gbb status <task|pane>            herdr agent info + git status/log + session id + resume command,
                                  owner, screen_state (codex), agent_model, prompt_pending
gbb read <task|pane> [--lines N]  terminal text (use to inspect blocked dialogs)
gbb send <task|pane> <text>       follow-up prompt (refuses to type into a dialog; error.hint says how to answer)
gbb send <task|pane> --pending    submit the prompt saved by a startup_blocked launch
gbb answer <task|pane> <n|label>  answer a Codex question (open or queued "⇧← to answer") or startup dialog:
                                  opens it, moves the › selection, verifies, Enter; then sends a pending prompt
gbb keys <task|pane> <key>...     raw keys, herdr names (enter, esc, up, down, shift+left, t, y)
gbb owner <task|pane> [<name>|--clear]   show / change who gets this task's callbacks
gbb wait <task|pane> [--until S]  block until a state (fallback when webhooks are not configured)
gbb result <task|pane>            commits since launch, diff stat, branch, uncommitted, session id, resume
gbb stop <task|pane>              close only the workspace gbb created; handover panes are just unregistered
gbb handover --pane <id> [--note] [--owner <name>] / gbb reclaim --pane <id>
gbb doctor                        incl. owner names/hosts, codex_args, codex_user_defaults (no secrets)
gbb test-webhook [--owner <name>] sends a test event through the same routing
```

### Codex

`gbb launch --kind codex` works the same way (tested since Herdr 0.9.3 with codex-cli 0.164.0; last verified on Herdr 0.9.5 with codex-cli 0.165.0. From Herdr 0.9.5 codex status comes from screen detection instead of codex turn hooks; gbb needed no change). On first start in a new folder codex shows "Trust this folder?", and projects with hooks show "Hooks need review". gbb never types into such a dialog: launch returns `state: startup_blocked` (with `blocked_reason` and the screen), keeps the prompt and sends a `blocked` callback; the caller answers with `gbb answer <task> <n|label>` (hooks: 2 = trust all, 3 = continue without trusting — gbb never trusts hooks on its own), after which the saved prompt is submitted (or `gbb send <task> --pending`). When Codex asks a question ("? 1 question / ⇧← to answer") `gbb send` refuses with a hint; `gbb answer` opens it with shift+left, moves to the option with up/down, verifies the selection and presses Enter (manual: `gbb keys <task> shift+left`, `down`…, `enter`). Herdr 0.9.5 reports the hooks dialog as `idle` and a never-prompted session ("Context 0% used · 0 in · 0 out") as `done`; gbb reads the screen and reports `blocked` with `blocked_reason` (`hooks_review`, `question`, `dialog`, `prompt_not_submitted`) instead of a false `done`. Herdr does not report codex session ids yet, so `gbb result` suggests `cd <worktree> && codex resume --last`. Model and effort: without `-- <agent args>`, gbb uses `codex_args` / `grok_args` from the config (single-line string array, each item passed as one argv word); with neither, the agent's own defaults apply (codex reads `~/.codex/config.toml`). Example: `codex_args = ["-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=\"xhigh\""]`; an explicit `--` (even empty) overrides the config. Codex 0.165 efforts: low, medium, high, xhigh ("Extra high"), max, ultra. With `codex_args` empty, the top-level `model` / `model_reasoning_effort` of `~/.codex/config.toml` win — `gbb doctor` shows them as `codex_user_defaults`, and `launch` / `status` report the model line from the Codex footer (`agent_model`, e.g. "GPT-6.1-Sol xhigh"). First prompt: codex can report ready while its splash is still loading and drops typed input, so gbb waits until the `›` composer is drawn and the screen is stable for two polls (`startup_ready_timeout_sec`, default 90) before typing; on `agent_prompt_stalled` it checks whether the agent is actually working or the text is sitting in the composer (one Enter), and re-types only when nothing reached the screen, so a prompt is never submitted twice. `codex exec --json` suits headless one-shot jobs and `codex app-server` is still experimental; the Herdr route keeps a visible pane you can take over, with the same status signal as grok.

### Several callers (owner-routed callbacks)

Several callers may share one gbb: your Grok Bot, a second Grok Bot (e.g. 参谋长), a ChatGPT dot. Tag tasks with an owner so callbacks reach whoever launched them:

```toml
# end of ~/.config/grokbot-bridge-herdr/config.toml (mode 600)
[[owners]]
name = "dot"                                   # dots-tunnel-bridge's gbb_launch passes --owner dot
url = "http://127.0.0.1:8765/herdr/webhook"
header_name = "X-Dots-Herdr-Token"
header_value = "<contents of ~/.config/dots-bridge/herdr_webhook_token>"

[[owners]]
name = "canmouzhang"                           # another Grok Bot: a webhook routine on that bot
url = "<that routine's webhook URL>"
header_name = "<header name from the routine panel>"
header_value = "<key from the routine panel>"
```

- Launch with `--owner <name>` or `GBB_OWNER=<name>`; `gbb handover --owner` and `gbb owner <task> <name>|--clear` set it later.
- Routing: owner configured → owner target only (`route: "owner"`); its POST fails (curl error or non-2xx) → primary (`route: "fallback"`, `fallback_reason: "owner_delivery_failed"`); no owner → primary (`route: "primary"`); owner not configured → primary (`fallback_reason: "owner_not_configured"`).
- `[[extra_webhooks]]` behave as before (every event), except an extra whose URL equals the owner target is skipped, so nothing is delivered twice. For a dot that should only see its own tasks, drop the extra and keep `[[owners]] name = "dot"`.
- Check with `gbb doctor` (owner names and hosts only) and `gbb test-webhook --owner <name>`. Rationale: [docs/decisions/0004](docs/decisions/0004-owner-routed-callbacks-and-codex-screens.md).

### Use with ChatGPT dots

The companion MCP server [dots-tunnel-bridge](https://github.com/Phoobobo/dots-tunnel-bridge) (a fork of [uezo/dots-bridge](https://github.com/uezo/dots-bridge), exposed to ChatGPT through OpenAI Secure MCP Tunnel) wraps `gbb` as MCP tools so a ChatGPT dot can drive local coding agents too. The tools live in dots-tunnel-bridge (`src/dots_bridge/herdr_tools.py`, enabled by `DOTS_BRIDGE_HERDR_TOOLS=1`); full docs: [docs/HERDR.md](https://github.com/Phoobobo/dots-tunnel-bridge/blob/main/docs/HERDR.md#english).

Setup:

1. Install gbb as above; `gbb doctor` is clean.
2. Install the bridge and tunnel-client per the [dots-tunnel-bridge README](https://github.com/Phoobobo/dots-tunnel-bridge) and add it in ChatGPT as a custom MCP server (Connection: Tunnel).
3. Create the token file `~/.config/dots-bridge/herdr_webhook_token` (mode 600), set `DOTS_BRIDGE_HERDR_TOOLS=1` in the bridge plist and restart the bridge.
4. Append the `[[extra_webhooks]]` table below to `~/.config/grokbot-bridge-herdr/config.toml`; check with `gbb test-webhook`.
5. **Refresh** the tools on the ChatGPT plugin page (13 `gbb_*` tools), and have the dot subscribe to `app.message.created` on channel `herdr` (else events land on `default`).

Tools:

| Tool | Kind | gbb call |
|---|---|---|
| `gbb_list`, `gbb_status`, `gbb_read`, `gbb_result`, `gbb_doctor` | read-only | `list`, `status`, `read --lines/--visible`, `result`, `doctor` |
| `gbb_wait` | read-only, max 120 s | `wait --until … --timeout` |
| `gbb_launch` | starts an agent; appends a draft-PR-only policy to the prompt; owner `dot` | `launch --repo --kind --task [--worktree/--no-worktree] [--base] --prompt --owner dot` |
| `gbb_send`, `gbb_keys`, `gbb_answer` | input to a managed pane | `send [--pending]`, `keys`, `answer` |
| `gbb_stop` | destructive, idempotent | `stop` |
| `gbb_handover`, `gbb_reclaim` | ownership | `handover --pane [--note] --owner dot`, `reclaim --pane` |

Every call is an argv list (no shell) with an explicit PATH, a timeout and validated inputs. send/keys/stop/reclaim re-check `gbb list` and refuse unmanaged panes and the protected workspaces (`DOTS_BRIDGE_HERDR_PROTECTED_WORKSPACES`, default `wAS,wAT`) unless the pane was handed over.

Status events: add to the end of `config.toml`

```toml
[[extra_webhooks]]
url = "http://127.0.0.1:8765/herdr/webhook"
header_name = "X-Dots-Herdr-Token"
header_value = "<contents of ~/.config/dots-bridge/herdr_webhook_token>"
```

Each extra target (max 5) gets the identical payload in its own background curl, header via stdin; the primary Grok Bot webhook is unchanged. `gbb doctor` reports `config.extra_webhooks.{count,hosts}` only. The receiver accepts loopback clients with the token only and posts an `app.message.created` message (`metadata.source = "herdr"`) to the dot's `herdr` channel, falling back to `default`. Refresh the dot's tools on the ChatGPT plugin page after changing tools. Rationale: [docs/decisions/0003](docs/decisions/0003-dots-bridge-tools-and-extra-webhooks.md).

### Notes from testing

- Grok's default permission policy auto-approves most shell commands (including `rm` inside the repo and `curl`), so `blocked` mostly comes from interactive questions or real permission prompts.
- `herdr plugin action invoke` acts on the focused pane; use the command palette or a keybinding in the pane you want to hand over.

### Webhook payload

```json
{"source":"grokbot-bridge-herdr","version":"0.2.0","event":"agent_status","hostname":"mbp",
 "task_id":"demo","pane_id":"wAX:p1","workspace_id":"wAX","agent_kind":"grok","agent_name":"gb-demo",
 "origin":"launched","owner":"dot","repo":"/Users/me/repo","worktree":"/Users/me/.local/share/grokbot-bridge-herdr/worktrees/repo-demo",
 "branch":"gbb/demo","status":"done","ts":"2026-10-28T00:00:00Z","herdr_status":"done","route":"owner"}
```

`event` is one of `agent_status` (with `status` = `done` | `idle` | `blocked`), `handover`, `reclaim`, `stopped`, `pane_closed`, `test`. `owner` is null for tasks without one; `route` is `owner` | `primary` | `fallback` (+ `fallback_reason`) | `extra`. Codex `blocked` events may carry `blocked_reason` (`hooks_review`, `question`, `dialog`, `prompt_not_submitted`) and `prompt_pending`; `herdr_status` is Herdr's raw status before gbb's screen check.

### End-to-end check

```sh
gbb launch --repo ~/scratch-repo --kind grok --task e2e --prompt "Create hello.txt and commit it"
gbb wait e2e --until done --until idle --until blocked --timeout 300000
gbb result e2e && gbb stop e2e
tail ~/.local/state/grokbot-bridge-herdr/bridge.log
```

Architecture and rationale: [docs/decisions/0001-architecture.md](docs/decisions/0001-architecture.md); ChatGPT dots integration: [0003](docs/decisions/0003-dots-bridge-tools-and-extra-webhooks.md).

## License / 许可

MIT, see [LICENSE](LICENSE).
