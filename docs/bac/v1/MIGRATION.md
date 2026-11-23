# BotAsCollie v1 迁移清单

本文件给协调方。本轮不改 Dots 桥、不改 super-bot、不在用户机器上安装。旧名只在这份清单和 `contracts/bac/v1/migrate-fixture.sh` 里出现。

已只读核验的桥：`Phoobobo/dots-tunnel-bridge` @ `a4b8e597060da1f3a714bc3b608278c3a2f219b0`（`src/dots_bridge/herdr_tools.py`、`docs/HERDR.md`、`AGENTS.md`）。Grok Bot 与 super-bot 没有单独的公开仓库被读到，下面它们的行是待协调项，不是已验证的实现。

## 消费方

| 消费方 | 今天 | 要改成 | 本轮是否改了代码 |
|---|---|---|---|
| 本仓库 CLI | `gbb`，`source` `grokbot-bridge-herdr` | `bac`，`source` `bot-as-collie`，`version` 整数 1 | 否。运行身份未切 |
| 本仓库插件 | `phoobobo.grokbot-bridge` | `phoobobo.bot-as-collie` | 否 |
| 本仓库配置 / 状态 | `~/.config/grokbot-bridge-herdr/`、`~/.local/state/grokbot-bridge-herdr/managed.json` | `bot-as-collie` 目录。先复制后停旧进程，不先删 | 否。只在 fixture 上证明了算法 |
| Grok Bot | 主 webhook。例行程序直接或经例程调 CLI | 仍是主 webhook，直到协调方决定是否改成具名 owner。回调要认新的 `source` 和整数 `version`，并用 `event_id` 去重 | 否。无单独仓库可核 |
| Dots MCP 桥 | `DOTS_BRIDGE_HERDR_TOOLS=1` 才注册 13 个 `gbb_*`。`DOTS_BRIDGE_GBB_BIN` 默认 `~/.local/bin/gbb`。argv 调 CLI。`gbb_launch` 的 Python 默认 kind 是 `codex`。`POST /herdr/webhook` 要求 `source == grokbot-bridge-herdr`，否则 422。字段白名单不含 `backend` / `event_id`。去重是整包 SHA-256。无订阅 202 且不排队。handover 的 `PANE_RE` 要求冒号，hc 的 `t9` 这种 address 会被桥拒绝 | 新环境变量 `DOTS_BRIDGE_BAC_BIN`。工具改为 `bac_*`（13 个改名 + `bac_capabilities`）。argv 以 `contracts/bac/v1/dots-argv.json` 为准，`--kind` 由调用方传入、桥不再默认 codex。`source` 必须是 `bot-as-collie` 且 `version` 为整数 1。白名单加上 `event_id`、`generation`、`attempt`、`backend`、`version`。去重改用 `event_id`。handover 同时接受 herdr `w1:p1` 和 hc address。`metadata.source` 第一刀仍为 `herdr`，与 Dot 提示语一起改。不保留 `gbb_*` 作为目标身份 | 否 |
| ChatGPT Dot | 只能调 MCP、收事件，不能开 shell。工具列表要在插件页 Refresh | 切换当天 Refresh。旧 `gbb_*` 消失、`bac_*` 出现之前，不要宣称两端可用 | 否 |
| super-bot / 参谋长 | 未核到仓库。它委派 Grok Bot 或 Dot，不直接控 hc | 只通过 `bac` 子命令。owner 名和 webhook 由协调方填写，本契约不猜测 | 否 |
| 本地登记与标签 | 行按 pane id。hc 标签 `grokbot=managed`、`gbb_task` | 迁移保留 pane id 与 owner。新进程还要能看见旧标签，直到另一次显式改标签（那一步会碰活终端，不属于离线工具） | 算法仅在 fixture 上跑过 |

## 桥上已核到、切换时必须对上的约束

- 启用开关今天是 `DOTS_BRIDGE_HERDR_TOOLS=1`。关掉时 MCP 和 `/herdr/webhook` 都不注册。
- 子进程是 argv 列表，没有 shell。stdin 关闭，有超时。`bac_wait` 仍不得超过 120 秒。
- launch 仍在提示末尾附加“只开 draft PR”的策略段。策略不是权限。
- 受保护 workspace 默认 `wAS`、`wAT`。`send` / `keys` / `stop` / `reclaim` 先 `list` 再动手。
- 回调认证仍是环回地址加 `X-Dots-Herdr-Token` 与 token 文件的常量时间比较。bac 不读取这个文件。
- owner 投递失败仍要到达主 webhook。extra 不是隔离边界：它会镜像每个 owner 的 id 和状态。不要把第二个主体配进 extra。
- 无订阅的 202 对 bac 来说是成功，不会 fallback，也不会排队。Dot 必须先订阅 `app.message.created`。

## 验证顺序

1. 协调方阅读本契约和 `contracts/bac/v1/acceptance.json`。此步不改任何运行中的服务。
2. 在桥的独立分支上实现 `bac_*` 与新的 `source` 检查，默认仍关闭或仍指向现有 `gbb`。跑桥自己的测试。不要在 bac 尚未安装时把默认二进制改成 `bac`。
3. super-bot 按 `commands.json` 的 argv 改委派。kind 必须显式传递。
4. 本仓库下一阶段在**同一分支**实现 `bac`，`identity.json` 的 `runtime_implemented` 改为 true，并打开 draft PR。实现前再跑 `sh tests/bac-contract-test.sh`。
5. 人在维护窗口安装。顺序：桥先接受 `bot-as-collie`，再把机器上的命令从 `gbb` 换成 `bac`，然后 ChatGPT Refresh tools。两边没对齐时，新回调会被桥 422，旧 `gbb_*` 会找不到二进制。
6. 用隔离副本跑 `contracts/bac/v1/migrate-fixture.sh` 确认 owner 与 pane 仍在，再对真实 `managed.json` 的副本做同一次迁移。不要让 `gbb` 的 hc-watch 和 `bac` 的 hc-watch 同时看同一批终端。
7. 最后才停用 `gbb_*` 和旧 `source`。第一刀保留 Dot 事件的 `metadata.source = herdr`。

## 回退

- 代码：不安装 `bac`，或把 `~/.local/bin` 的符号链接指回基线 `bbdfc4bbaece3ddafa3a9363b1d0f43b230aa5a6` 的 `bin/gbb`。不改 PR #1 / #2 的历史。
- 状态：迁移写入新目录。旧 `~/.local/state/grokbot-bridge-herdr/` 在确认前不删除。失败的迁移不得改源文件；fixture 测试锁的就是这一点。
- 桥：把 `source` 检查和工具名改回 `gbb`，再 Refresh tools。
- 不使用 `herdr server stop` 或 `hc server stop` 作为回退。

## 离线迁移工具

`contracts/bac/v1/migrate-fixture.sh <src-dir> <dst-dir>`

- `src-dir` 必须有第一行是 `bac-migrate-fixture` 的 `FIXTURE_OK`，以及 `managed.json`。
- 拒绝活的配置、状态、数据目录（`grokbot-bridge-herdr` 和 `bot-as-collie`），即使放了标记。
- 不读 `config.toml`、token 文件、`secret.env`、`bridge.toml`。登记表里若出现 `header_value` / `token` / `secret` / `password` / `authorization` 字段，整次失败。
- 成功：按 pane id 保留 `owner`、`task_id`、`backend`（缺省视为 `herdr`）。`codex`/`grok` 保持。`pi`/`antigravity` 的 `kind` 变为 null，`kind_support` 为 `rejected`。其他 kind 变为 null，`kind_support` 为 `unknown`，绝不写成 codex。
- 失败：退出码 1，不写目标 `managed.json`，源文件字节不变。拒绝活路径或缺少标记时退出码 2。

示例输入在 `contracts/bac/v1/fixtures/registry-ok/` 与 `fixtures/registry-bad/`。`pane_id` 为 `planned` 的坏 fixture 必须失败。
