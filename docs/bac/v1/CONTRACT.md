# BotAsCollie v1 契约

状态：v1 已实现。相对 `ae859908` 的修订列在下面，字段名没有另起一套。

## v1 修订（相对 ae859908，供参谋长同步）

哈希输入没有变，仍是 `bac.callback.v1`、pane、event、status、generation。变的是 generation 的寿命和投递保证的说法。

1. **generation 持久化。** 计数写在状态目录的 `event-seq.json`，进程退出、`reclaim`、同一 pane id 再次 handover 都不清零。下一次逻辑事件用下一个整数，因此 `event_id` 不会和旧事件相撞。去抖丢掉的重复状态仍然不加。并发更新由 `bin/bac-lock` 在一次 `fcntl` 独占里读改写 `event-seq.json`。锁文件不按名字删除或改名。`flock` 命令不是依赖。这是隔离候选，不是生产切换。
2. **投递保证。** 每个目标最多一次 HTTP 尝试，所以每份 JSON 里的 `attempt` 恒为 1。这是「该目标的尝试次数」，不是「这个逻辑事件一共送出几次」。owner 超时或非 2xx 时，同一 `event_id` 还会再送给 primary。一个同时看着两边的消费者可能收到两份。重启不重放尚未盖章的事件，因此也会丢。这不是端到端的至多一次，也不是至少一次。消费者用 `event_id` 去重。登记表改动和 generation 在同一次 fcntl 里提交。helper 干净失败（超时、jq、父进程消失、generation 到了 JSON 整数上限）时两个文件都不替换，不发 webhook，不写成功 history，命令不是 `ok: true`。HTTP 在这次提交之后才后台发出，`ok: true` 只表示本地提交已完成并且发送已启动，不表示 HTTP 已成功，也不把失败回执当成回滚。进程在 `commit-pending.json` 写下之后被杀掉时，下一次拿锁会把两个文件补齐，但不会补发回调；重试不再盖一次新章。
3. **`--owner` 不是认证。** 能在这台机器上执行 `bac` 的人就是受信操作者，可以自己填 owner 字符串。bac 不另做登录服务。Dots 适配器必须用桥自己已经认证的主体写入 `--owner`（今天的 `DOTS_BRIDGE_GBB_OWNER`，切换后由桥配置绑定），不能把工具参数里的 owner 当成调用方身份。
4. **extras 和 primary fallback 是有意的受信元数据接收者。** 它们收到 id 和状态，不收到终端正文。文档不把这条路径叫做硬隔离。
5. **模型配置。** 默认不读 `~/.codex/config.toml`。只有 `BAC_ALLOW_CODEX_CONFIG=1` 时才读该文件顶层的 `model` 这一个键。回调和日志仍然不放 header、token 或这个文件里的其他行。这和「不读凭据」是两件事。

## 给协调方

BotAsCollie（BAC）是本仓库的破坏性下一身份。命令行固定为小写 `bac`。用户经参谋长委派，参谋长和 Dot 都只通过 `bac` 子命令接触窗格；没有第二条直控 `hc` 的工具面。

- 契约版本：整数 `1`。回调 `source` 固定为 `bot-as-collie`。
- 基线：`bbdfc4bbaece3ddafa3a9363b1d0f43b230aa5a6`（短 SHA `bbdfc4b` 唯一），即已安装的 0.3.3，也是 [PR #2](https://github.com/Phoobobo/grokbot-bridge-herdr/pull/2) 的头。不是 `main`（`92e801a451555891cd1af41bf0f0abfc39adab8a`）。
- 机器可读面：`contracts/bac/v1/`。人工契约是本文。迁移清单是 `docs/bac/v1/MIGRATION.md`。决策是 `docs/decisions/0008-bac-v1-contract.md`。
- 仓库名不改，本轮不发布、不安装、不开 PR。
- 旧名 `gbb` / `grokbot-bridge-herdr` 只出现在迁移说明和离线 fixture 工具里。目标运行身份不保留 `gbb` 别名。

## 身份（已冻结）

| 项 | 目标 | 本树在切换前仍是 |
|---|---|---|
| 命令 | `bac` | `gbb` |
| 回调 `source` | `bot-as-collie` | `grokbot-bridge-herdr` |
| 回调 `version` | 整数 `1` | 字符串 `"0.3.3"` |
| 插件 id | `phoobobo.bot-as-collie` | `phoobobo.grokbot-bridge` |
| 配置目录 | `~/.config/bot-as-collie/` | `~/.config/grokbot-bridge-herdr/` |
| 状态目录 | `~/.local/state/bot-as-collie/` | `~/.local/state/grokbot-bridge-herdr/` |
| 数据目录 | `~/.local/share/bot-as-collie/` | `~/.local/share/grokbot-bridge-herdr/` |
| 环境变量 | `BAC_OWNER` 等 `BAC_` | `GBB_OWNER` 等 `GBB_` |
| hc 标签 | `bac=managed`、`bac_task=<id>` | `grokbot=managed`、`gbb_task=<id>` |
| 终端名 | `bac-<task>`，截到 32，字符集 `a-z 0-9 - _` | `gb-<task>` |
| 标签标题 | `bac · <task>` | `gbb · <task>` |
| 新 worktree 分支 | `bac/<task>` | `gbb/<task>` |
| MCP 工具 | `bac_*` | `gbb_*` |

`source` 用 `bot-as-collie` 而不是短名 `bac`：它和配置/状态目录是同一个产品字符串，和命令名分开，避免和参数、标签里的 `bac` 混在一起。owner 正则与 0.3.3 和 Dots 桥相同：`^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$`。`dot` 与 `canmouzhang` 仍然合法。

GitHub 仓库保持 `Phoobobo/grokbot-bridge-herdr`。

## 命令

标准输出恰好一份 JSON。成功退出码 0。错误退出码 1，形如 `{"ok":false,"error":{"code":"...","message":"..."}}`。唯一的 `ok:false` 且退出码 0 是 launch 的 `state:"startup_blocked"`（沿用 0.3.3，调用方接着 `bac answer`）。

`bac launch` 省略 `--kind` 是 `kind_required`，不再默认成 grok 或 codex。

```
bac launch --repo <path> --kind <codex|grok> --task <id> (--prompt <text> | --prompt-file <path>) [--worktree <branch> | --no-worktree] [--base <ref>] [--owner <name>] [--backend auto|herdr|hc] [-- <agent-arg>...]
bac send <task|pane> [--owner <name>] (--pending | <text>)
bac handover --pane <id> [--note <text>] [--owner <name>] [--backend herdr|hc]
bac read <task|pane> [--owner <name>] [--lines <n>] [--visible]
bac status <task|pane> [--owner <name>]
bac stop <task|pane> [--owner <name>]
bac list [--owner <name>]
bac answer <task|pane> [--owner <name>] <option-number|label>
bac keys <task|pane> [--owner <name>] <key>...
bac owner <task|pane> [--owner <caller>] (<name> | --clear)
bac wait <task|pane> [--owner <name>] [--until <status>]... [--timeout <ms>]
bac result <task|pane> [--owner <name>]
bac reclaim --pane <id> [--owner <name>]
bac doctor
bac report [--owner <name>]
bac capabilities
bac test-webhook [--owner <name>]
bac version
bac hook
bac action handover|reclaim
bac hc-watch
```

`bac hook`、`bac action`、`bac hc-watch` 是内部入口，不是 MCP 工具。`bac owner` 和 `bac test-webhook` 也不是 Dot 的工具。`bac hc-watch` 只跟随登记表里的终端，不构成绕过 `bac` 去操作 `hc` 的调用面。

Dots 桥在切换后必须按 `contracts/bac/v1/dots-argv.json` 的 argv 列表调用，不得再猜参数顺序。`bac_launch` 的 argv 里必须有调用方传入的 `--kind`。

### owner

`--owner` 和 `BAC_OWNER` 是本机调用者自己填写的标签，不是认证结果。bac 不校验这个字符串属于哪个已登录主体。

- 行上已有 owner 时，`read`、`send`、`answer`、`keys`、`stop`、`reclaim`、`handover`、`owner` 必须带同一个 owner。没带是 `owner_required`。不一致是 `owner_mismatch`。两条路径都不读终端，也不改登记表。
- 行上没有 owner 时，这些命令允许本机调用者不带 `--owner`。这是主 webhook 任务。
- `status`、`result`、`wait` 不返回终端正文。带了不匹配的 `--owner` 时返回 `owner_mismatch`，并且不先读屏幕。不带 `--owner` 时本机操作者可以看元数据。
- `list` 和 `report` 不带 `--owner` 时返回全部行的元数据。带了 `--owner` 时只留下这个 owner 的行，不把别人的行报成错误，也不附带终端正文。`doctor` 和 `capabilities` 是机器级的，没有任务 owner。
- `bac owner` 移交或 `--clear` 同样要求当前 owner。错误的调用方不会改登记表。Dot 没有这个工具，桥也不能把客户端传入的 owner 当成已认证主体。

### 错误码

0.3.3 已有的码全部保留，见 `contracts/bac/v1/errors.json`。新增：

| code | 何时 |
|---|---|
| `kind_required` | launch 没有 `--kind` |
| `kind_unsupported` | kind 不是 codex 或 grok。`error.kind` 是原字符串，`error.kind_support` 为 `rejected`（pi、antigravity）或 `unknown` |
| `owner_required` | 行有 owner，但这条命令没带调用方 owner |
| `owner_mismatch` | 调用方 owner 与行 owner 不同。登记表字节不变 |

`agent_start_failed` 和 `pane_not_found` 的 JSON **没有** `pane_id` 字段。

## pane id

`pane_id` 只由后端分配，命令在后端返回之后才写入响应和登记表。

- hc：`hc run --bg --json` 或 `hc get` 的 `address`。`pane_id_source` 为 `hc.address`。离线测试桩用过 `t9`（`tests/hc-backend-test.sh`）。这是桩的返回值，不是 bac 预分配的号。
- herdr：`herdr workspace create` 的 `.result.root_pane.pane_id`。`pane_id_source` 为 `herdr.root_pane.pane_id`。形状如 `w1:p1`。
- 后端没给 id：退出码 1，`agent_start_failed` 或 `pane_not_found`，响应里不出现 `pane_id`，登记表不新增行。禁止的假 id：`planned`、`pending`、`unknown`、`fake`、`placeholder`。
- `herdr_space`（`sp` + 32 位十六进制）和 `herdr_tab`（`tb` + 32 位十六进制）是 bac 为了在 Herdr.app 里摆放而生成的，**不是** pane id，不能写进 `pane_id`。

成功的 hc launch 示例（`contracts/bac/v1/fixtures/cli/launch-hc-ok.json`）：

```json
{"ok":true,"task_id":"fix-login","pane_id":"t9","pane_id_source":"hc.address","backend":"hc","kind":"codex","owner":"dot","workspace_id":null,"agent_name":"bac-fix-login","herdr_space":"sp0123456789abcdef0123456789abcdef","created_herdr_space":false,"herdr_tab":"tb0123456789abcdef0123456789abcdef","created_herdr_tab":true}
```

没有 address 时（`fixtures/cli/launch-no-address.json`）：

```json
{"ok":false,"error":{"code":"agent_start_failed","message":"hc returned no address"}}
```

## kind

以 `contracts/bac/v1/kinds.json` 为准，并已对照基线 `bin/gbb` 的 `case "$kind" in grok | codex)`。

| kind | v1 | 依据 |
|---|---|---|
| `codex` | 支持。做屏幕分类。页脚模型只作观测 | 基线接受分支；`codex_model_line` |
| `grok` | 支持。状态以程序上报为准，不从屏幕猜 | 基线接受分支；ADR 0005 |
| `pi` | 明确拒绝，`kind_support: rejected` | 基线代码没有这个分支 |
| `antigravity` | 明确拒绝，`kind_support: rejected` | 基线代码没有这个分支 |
| 其他 | `kind_unsupported`，`kind_support: unknown` | 不得改写成 codex 或 grok |

`bac capabilities` 返回这张表，外加 `model_freshness_sec: 900` 和额度 `provenance: unknown`。

```json
{"ok":false,"error":{"code":"kind_unsupported","message":"kind pi is not implemented","kind":"pi","kind_support":"rejected"}}
```

```json
{"ok":false,"error":{"code":"kind_required","message":"--kind is required (codex or grok)"}}
```

接管时，后端报告的 agent 名只有 `codex` 或 `grok` 才写入 `kind`。报告为 `pi`、`antigravity` 或其他字符串时，handover 失败，码为 `kind_unsupported`，不登记。迁移旧登记表时不删行：`kind` 置 `null`，`kind_reported` 保留原字符串，`kind_support` 为 `rejected` 或 `unknown`。

## 回调

回调只含 id 和状态。禁止字段：`text`、`screen`、`prompt`、`output`、`stdout`、`stderr`、`env`、`token`、`header`、`header_value`、`secret`、`password`、`model`、`quota`、`args`、`agent_args`、`raw`。模型和额度只出现在 `bac status` / `bac doctor` / `bac capabilities`，不进回调，这样 `[[extra_webhooks]]` 镜像不到它们。

必有字段：

| 字段 | 值 |
|---|---|
| `version` | 整数 `1` |
| `source` | `bot-as-collie` |
| `event_id` | 64 位小写十六进制，算法见下 |
| `generation` | 该 pane 的逻辑事件序号，从 1 起 |
| `attempt` | v1 恒为 `1` |
| `event` | `agent_status`、`handover`、`reclaim`、`stopped`、`pane_closed`、`test` |
| `status` | `agent_status` 时为 `done`、`idle` 或 `blocked`。不发送 `working`。其他事件可为 null |
| `owner` | 字符串或 null |
| `route` | `owner`、`primary`、`fallback`、`extra` |
| `ts` | 观测到该逻辑事件的 UTC 时间，重试不变 |
| `task_id`、`pane_id` | 字符串。`test` 的 pane 可为 null |
| `backend` | `herdr` 或 `hc` |
| `agent_kind` | `codex`、`grok` 或 null |

沿用且仍允许的可选字段：`hostname`、`workspace_id`、`agent_name`、`origin`（`launched` 或 `handover`）、`repo`、`worktree`、`branch`、`herdr_status`、`blocked_reason`、`fallback_reason`、`prompt_pending`、`note`。`note` 只是 handover 参数，最长 500，不是屏幕。

`blocked_reason` 在 v1 生产者只发出基线已有的：`hooks_review`、`question`、`dialog`、`prompt_not_submitted`、`permission`、`auth`、`error`。消费方遇到不认识的值应忽略该字段，不要整包拒绝。`fallback_reason` 同理，已知值：`owner_not_configured`、`owner_config_insecure`、`dots_unavailable`、`owner_url_invalid`、`owner_delivery_failed`。

### event_id

UTF-8 文本的 SHA-256，十六进制小写：

```
bac.callback.v1
<pane_id>
<event>
<status 或空串>
<generation 的十进制>
```

四行之间各一个 `\n`，末尾没有额外的 `\n`。同一逻辑事件的 owner 投递和 primary 回退共用一个 `event_id`。`route`、`attempt`、`ts` 不参与计算。generation 只在真正发出一条新通知时加一；被 15 秒去抖丢掉的重复状态不加、也不发送。计数保存在 `event-seq.json`，`reclaim` 和进程重启都不把它清掉。同一后端 pane id 再次接管时，generation 从上次的下一个整数继续，所以新的 `event_id` 和旧的不同。去重范围是这个状态目录里的 pane id，不是进程内存。写入在持有 `fcntl` 锁的 `bin/bac-lock` 进程里完成。会发布回调的登记表改动和 generation 同一次提交。helper 在写出 `commit-pending.json` 之前退出时，两个文件都保持原样。jq 或提交失败时旧文件保留。进程死后内核释放锁，不靠 pid 回收。`flock` 不是依赖。`bac doctor` 的 `generation_lock` 是 `fcntl`，`lock_helper` 是 `python3`，`flock_required` 是 false。回调字段没有因此改变。

示例：pane `t9`、`agent_status`、`done`、generation `3` → `5cb0047d8b5de61f00884bcd7272a2330f697d3e91e836002c6a8144d794f0f8`。

### 路由、超时、重试、重启

与 ADR 0004 相同，不把失败的 owner 吞掉：

| 情况 | 投到 | route |
|---|---|---|
| 无 owner | 主 webhook | `primary` |
| owner 目标 2xx | 只投 owner | `owner` |
| owner 超时、连接失败或非 2xx | 再投主 webhook 一次 | `fallback`，`fallback_reason=owner_delivery_failed` |
| 没配 owner、URL 非法、配置不是 600/400 | 主 webhook | `fallback` 加对应 reason |
| dots 模块关闭且目标是 dots 端口 | 主 webhook | `fallback_reason=dots_unavailable` |
| 每个事件 | 每个 `[[extra_webhooks]]`，与 owner URL 相同的跳过 | `extra` |

超时是 `webhook_timeout_sec`，默认 5 秒，`curl --max-time`。同一个 URL 不自动再试，所以每一份回调里的 `attempt` 都是 1，表示这个目标的尝试次数。owner 失败后还会把同一 `event_id` 送给 primary，那是第二个目标，不是同一次尝试的第二次。一个逻辑消费者如果同时接收 owner 和 primary，会看到两份，必须用 `event_id` 去重。HTTP 2xx 算成功，包括 Dots 在无订阅时返回的 202。该 202 不会触发 fallback，桥也不排队。进程重启不重放还没盖章的事件，所以可能丢失；重启后只有观测状态与 `last_status` 不同时才用新的 generation 发一条。钩子仍然马上返回，POST 在后台，不阻塞 Herdr。

### 本机操作者与受信接收者

- 每个目标自己的 header，经 curl 的 stdin 配置传入，不进 argv，不进日志，不进 JSON。日志只有主机名。
- 配置文件模式不是 600 或 400 则不发。
- owner 目标只收这个 owner 的事件。
- 主 webhook 是受信任的操作者回退（今天的 Grok Bot）。fallback 会把同一份 id/状态交给它，这是 ADR 0004 的要求，不是终端正文泄漏。
- `[[extra_webhooks]]` 收到所有 owner 的同一份元数据。它**不是**隔离边界。不要把第二个主体配成 extra。需要隔离就给每个主体单独的 `[[owners]]`，并且不要用 extra 镜像。
- 回调里没有 header 值。`bac doctor` / `bac report` 仍然只打印目标名字和主机，不打印 header、token 或完整 URL。

## 模型与额度

`bac status` 上的对象，不进回调：

```json
"model": {"id": null, "provenance": "unknown", "observed_at": null, "freshness": "unknown", "freshness_sec": null}
"quota": {"value": null, "unit": null, "provenance": "unknown", "observed_at": null, "freshness": "unknown"}
```

| provenance | 含义 | freshness |
|---|---|---|
| `unknown` | 没有读到。`id` 必须为 null。禁止用 kind 名、默认值或训练知识填 | `unknown`，`freshness_sec` 为 null |
| `observed` | Codex 页脚在 ` · ` 之前的那一段，原样，最长 80。基线函数是 `codex_model_line`。`observed_at` 是读屏幕的时间 | `freshness_sec` ≤ 900 为 `fresh`，否则 `stale`。900 是契约常数 `model_freshness_sec`，不是对模型本身的猜测 |
| `config` | 操作者写在 Codex 配置顶层 `model` 键里的字面量。这不是“当前会话正在用的模型” | 恒为 `not_a_session_observation` |

两者同时存在时，`model` 用 observed，另给 `model_config` 放 config，不合并成一个 id。

v1 的 `quota` 只能是 `unknown`。屏幕上的 `Context N% used` 是终端正文，不是额度，不得写进 `quota`。基线代码没有额度解析。

## 接管

`bac launch` 只创建新终端或新 workspace，不附着到已有窗格。

已有会话只通过 `bac handover --pane <id>` 登记。按 task 扫描、按目录发现、或直接 `hc` 认领都不在契约里。

- 窗格尚无登记：写入一行，`origin` 为 `handover`，`created_terminal` / `created_workspace` 为 false。`bac stop` 只注销，不杀进程，不 `space.close` / `tab.close`。
- 已是同一 owner：返回原行，不第二行。
- 已是别的 owner：`owner_mismatch`，登记表不变。这和 0.3.3 不同；0.3.3 会把原行返回给任何调用方。
- 报告的 kind 不是 codex/grok：`kind_unsupported`，不登记。
- 不执行 `herdr server stop` 或 `hc server stop`。

Codex 对话框仍然只接受 `bac answer` 或 `bac keys`。不把提示打进对话框。不替用户点 “Help improve Grok” 的 Opt in。不自动信任 hooks。

## 双调用方验收（定义在本轮，未对真实环境执行）

机器可读步骤：`contracts/bac/v1/acceptance.json`。每条的 `ran` 都是 false，`environment` 都是 `fixture`。

1. **Grok Bot（主 webhook，可不带 owner）**：`bac launch` → 响应里的真实 `pane_id` → `bac status` / `bac result` → 回调 `source=bot-as-collie`、`version=1`、`route=primary`。
2. **Dots（owner `dot`）**：同样的 launch（argv 带 `--kind` 和 `--owner dot`）以及 `bac handover`（herdr 的 `w1:p1` 和 hc 的 `t9`）→ `bac status` / `bac result` → 回调 `route=owner`。桥把 `event_id` 当作去重键，经 `app.message.created` 推送。无订阅仍是 202 且不排队。
3. **跨 owner**：`dot` 对 `canmouzhang` 的任务 `send` 或 `read`，得到 `owner_mismatch`，登记表不变。
4. **重复 / 超时**：同一 `event_id` 先 `route=owner` 再 `route=fallback`，`attempt` 都是 1，没有第三次。
5. **重启**：不重放未送达事件。

Mock/fixture 与真机的差别：fixture 检查 JSON、argv、迁移和基线源码。真机还要有 Herdr 或 hc、两边 webhook、ChatGPT Refresh tools，以及桥先接受新的 `source`。本轮没有做真机，也没有做 Dots 端到端。

## 本轮实际检查

`sh tests/run.sh` 会跑契约检查和 `tests/bac-callers-test.sh`。后者用临时 HOME、假 header 和 stub `hc` 真正执行 `bin/bac`：stub 分配 pane id，本地 HTTP 接收回调。这不是真实 Herdr、hc、Dots 或 ChatGPT。

契约检查仍然核对用法字符串、`event_id` 算法、终端正文字段、kind/模型/额度示例，以及隔离 fixture 上的登记表迁移：保留 owner 与 pane，失败不改源文件，已有目标拒绝覆盖，活状态目录拒绝。
