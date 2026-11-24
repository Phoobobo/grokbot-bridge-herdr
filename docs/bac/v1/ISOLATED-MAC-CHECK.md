# Mac mini 隔离安装与最小闭环

这是给操作者的步骤，不是已经在 Mac mini `0df4e466` 上跑过的验收。作者没有操作那台机器。不要把本文里的预期输出写成已通过。

`install.sh` 会把 `bac` 链到 `~/.local/bin`、删掉 `~/.local/bin/gbb`，并在有 `herdr` 时执行 `herdr plugin link`。隔离检查不要运行 `install.sh` 或 `uninstall.sh`。不要改 `~/.config/bot-as-collie`、`~/.local/state/bot-as-collie`、`~/.local/share/bot-as-collie`，不要链现网插件，不要动 Dots、默认桥或正在用的会话。

## 调用接口

程序是检出目录里的 `bin/bac`。锁在同目录的 `bin/bac-lock`，用 `python3` 标准库 `fcntl`。用绝对路径调用，不要把这个检出插到现网 `PATH` 前面。

| 变量 | 作用 |
|---|---|
| `BAC_CONFIG` | 这次检查专用的 `config.toml`。不设则是 `~/.config/bot-as-collie/config.toml` |
| `BAC_STATE_DIR` | `managed.json`、`event-seq.json`、`generation.lock`、`commit-pending.json`、`history.jsonl`、`bridge.log` |
| `BAC_DATA_DIR` | worktree 根。不设则落在现网数据目录 |

`bac doctor` 的 `config.path` 和 `registry` 必须等于上面这两个隔离路径。`owner` 只是本机标签，不是登录。回调 URL 由操作者填入 `webhook_url`，作者没有 `SUPERBOT_BOT_URL`，也不能代填。配置模式必须是 `600` 或 `400`，否则不发。`doctor` 只显示主机名和 header 是否已设置，不显示 header 的值。

`plugin_linked: true` 只说明现网 Herdr 里已经有同名插件，不说明这次检出被链上。隔离检查不要执行 `herdr plugin link`。

## 取出这个提交

保全包里的 bundle 需要本地已经有 `4211de848dc82defd57b71a067c500f79340ace7`。在隔离目录：

```sh
git bundle verify 10e1d2b.bundle
git fetch 10e1d2b.bundle HEAD:refs/heads/recover-bac
git checkout recover-bac
git rev-parse HEAD
```

`HEAD` 必须等于包内 `HEAD` 文件。对不上就停。不要在这台机器上 merge 到 `main`。

## 最小闭环

下面每一步都由 Mac mini 上的人执行。作者这一轮没有执行。

1. 建空的隔离配置、状态和数据目录，模式 `700`。从 `config.example.toml` 复制配置，`chmod 600`。`webhook_url` 先留空。
2. `bin/bac doctor`。确认 `ok` 为 true，`source` 为 `bot-as-collie`，`generation_lock` 为 `fcntl`，`python3` 为 true，`registry` 和 `config.path` 都在隔离目录里。这一步不发回调。
3. `SUPERBOT_BOT_URL` 还没有时停在这里。不要跑 `bac test-webhook`。URL 为空时该命令仍可能盖章并打印 `ok: true`，日志是 webhook skipped。那不是 SuperBot 收到了事件。
4. URL 和 header 由操作者写入隔离配置之后，才跑 `bin/bac test-webhook --owner <操作者定的标签>`。验收要同时满足：日志里有 `webhook POST host=<该主机>` 且 HTTP 为 2xx；SuperBot 看到 `source=bot-as-collie`、`version=1`、`event=test`、`attempt=1`。只看命令的 `ok: true` 不算通过。
5. Grok 登录还没有时不要 `launch`。登录只存在于这台 mini 的 Herdr 会话里以后，再用一个临时 git 仓库：`launch --repo <临时仓库> --kind grok --task bac-iso-1 --owner <同一标签>`，然后 `wait`、`result`、`stop`。回调要带新的 `event_id`。不要把 webhook 指到现网 Grok routine，不要配置 Dots extra。

`commit-pending.json` 若损坏，后续拿锁的命令会失败并且不会删这个文件。先把文件复制出来，再从隔离状态目录里移走。不要对现网状态目录做这件事。
