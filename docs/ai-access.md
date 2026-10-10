# 让 AI agent 接入 lzy_totp（CLI + MCP）

lzy_totp 除了给人用的 App，还对外暴露一个**给 AI agent 调用的取码接口**。
形态是「一个内核、两种外壳」：

- **MCP server**：`lzy-totp mcp` —— Claude Code / Claude Desktop / Cursor / DSH 等 MCP 客户端原生接入，
  agent 的工具列表里直接多出 `generate_totp`、`list_accounts` 等 7 个工具（推荐）；
- **CLI**：`lzy-totp code github --json` —— 任何能执行 shell 的 agent 都能用，无需 MCP 支持。

两者共用 `packages/totp_core` 里同一份 TOTP 实现、同一个加密 vault、同一套访问策略。

## AI agent 能做什么 / 不能做什么

| | 说明 |
|---|---|
| ✅ 能 | 列出 vault 里的账号名与元数据、取当前一次性验证码（含剩余秒数）、录入/删除账号、开关某账号的 AI 权限 |
| ❌ 不能 | **任何工具都不会返回密钥（secret）**；不能读系统钥匙串里 App 的账号；不开网络端口、不外传数据 |
| ⚠️ 代价 | 能取码就等于能过 2FA。当前策略是「默认放行 + 黑名单」，见 [安全边界](#安全边界务必了解) |

## 架构

```
┌─────────────────┐   MCP stdio (JSON-RPC 2.0)   ┌──────────────────────────┐
│  AI agent        │ ───────────────────────────▶ │  lzy-totp mcp            │
│  Claude Code /   │                              │  （7 个工具）             │
│  Cursor / DSH …  │   shell 调用                 │                          │
│                  │ ───────────────────────────▶ │  lzy-totp code <名称>     │
└─────────────────┘                              └────────────┬─────────────┘
                                                              │ 同一个内核
                                                   ┌──────────▼─────────────┐
                                                   │  packages/totp_core     │
                                                   │  TOTP / 策略 / 审计      │
                                                   └──────────┬─────────────┘
                                                              │ AES-256-GCM
                                                   ┌──────────▼─────────────┐
                                                   │  ~/.config/lzy_totp     │
                                                   │  vault.json / vault.key │
                                                   │  audit.jsonl            │
                                                   └────────────────────────┘
```

App（Android / macOS）的账号存在系统钥匙串，与这个 vault **互不影响**：
想给 AI 用的账号，需要用 CLI 录入一次。

## 快速开始（5 步）

```bash
# 1. 编译原生二进制（启动快，约 6 MB）
cd tools/totp_cli && dart pub get
dart compile exe bin/lzy_totp.dart -o ~/.local/bin/lzy-totp

# 2. 确认它在 PATH 里
lzy-totp doctor

# 3. 录入一个给 AI 用的账号
lzy-totp add github --secret JBSWY3DPEHPK3PXP --issuer GitHub

# 4. 取码自测（agent 走的也是这条）
lzy-totp code github --json
# {"account":"GitHub","code":"834074","remaining_seconds":18,"period":30,"expires_at":"..."}

# 5. 接到 MCP 客户端（见下一节），然后对 agent 说：
#    「用 lzy_totp 取一下 GitHub 的验证码」
```

## 接入方式一：MCP server（推荐）

启动方式（stdio 传输，不需要端口）：

```bash
lzy-totp mcp
```

### 通用配置（多数客户端通用）

`mcpServers` 结构的客户端（Claude Desktop、Cursor、Windsurf、Cline、Continue…）把这段加进配置文件：

```json
{
  "mcpServers": {
    "lzy_totp": {
      "command": "/Users/<你的用户名>/.local/bin/lzy-totp",
      "args": ["mcp"]
    }
  }
}
```

多环境隔离时用环境变量指定数据目录：

```json
{
  "mcpServers": {
    "lzy_totp": {
      "command": "/Users/<你的用户名>/.local/bin/lzy-totp",
      "args": ["mcp"],
      "env": { "LZY_TOTP_HOME": "/Users/<你的用户名>/.config/lzy_totp" }
    }
  }
}
```

### 各客户端配置位置

| 客户端 | 配置位置 | 备注 |
|---|---|---|
| Claude Code | `claude mcp add lzy_totp -- ~/.local/bin/lzy-totp mcp`，或项目内 `.mcp.json` | 命令形式最省事，`/mcp` 可查看连接状态 |
| Claude Desktop（macOS） | `~/Library/Application Support/Claude/claude_desktop_config.json` | 顶层 `mcpServers`，改完需重启客户端 |
| Cursor | `~/.cursor/mcp.json`（全局）或项目内 `.cursor/mcp.json` | 顶层 `mcpServers` |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` | 顶层 `mcpServers` |
| Cline / Continue 等 VS Code 插件 | 插件设置里的「MCP Servers」JSON | 同一份 JSON |
| DSH（本机 harness） | `$DSH_HOME/cordis.patch.yml`（所有 profile）或 `$DSH_HOME/profiles/<name>/cordis.patch.yml` | 用 `dsh-mcp-client` 插件，见下方 YAML |

> 各客户端配置文件路径可能随版本变化，以官方文档为准；关键是「命令行 + 参数」这两项：
> `~/.local/bin/lzy-totp` 与 `mcp`。

### DSH 专用配置（Cordis patch）

DSH 走 `@deepseek-ai/dsh-mcp-client`，工具以 `mcp__<serverName>__<tool>` 形式暴露：

```yaml
# 追加到 $DSH_HOME/cordis.patch.yml（把路径换成你自己的）
- insert:
    - id: lzy-totp-mcp
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: lzy_totp
        transport: stdio
        command: /Users/<你的用户名>/.local/bin/lzy-totp
        args: ['mcp']
```

`command` 也支持 `!!js` 表达式，想跨机器复用时可以写成
`!!js process.getBuiltinModule('node:path').join(process.getBuiltinModule('node:os').homedir(), '.local/bin/lzy-totp')`。

接入后工具名形如 `mcp__lzy_totp__generate_totp`、`mcp__lzy_totp__list_accounts`。
也可以不改配置，直接用 `--patch` 传一次性 overlay 文件：

```bash
dsh web --patch /path/to/lzy-totp-mcp.cordis.yml
```

## 接入方式二：CLI（无需 MCP）

任何能执行 shell 的 agent（包括用 Bash 工具的编码 agent）都能这样取码：

```bash
lzy-totp list                 # 先看有哪些账号可用
lzy-totp code github          # 输出裸验证码，便于直接填进表单
lzy-totp code github --json   # 结构化输出，带剩余秒数
```

建议在 agent 的说明里写明：**取码前先 `list`，被拒绝时不要重试**（拒绝是策略而非故障）。
退出码：`0` 成功 / `1` 用法错误 / `2` 被策略拒绝 / `3` 未找到账户。

## MCP 工具参考

| 工具 | 必填参数 | 可选参数 | 作用 |
|---|---|---|---|
| `list_accounts` | — | — | 列出账号 + `ai_allowed` 标记（不含密钥） |
| `get_account_info` | `account` | — | 单个账号元数据（不含密钥） |
| `generate_totp` | `account` | — | 取当前验证码；被 deny 的账号返回错误且不含任何码 |
| `add_account` | `account`、`secret` | `issuer`、`label`、`digits`、`period`、`algorithm`、`block_ai` | 录入账号（`block_ai=true` 禁止 AI） |
| `add_from_uri` | `uri` | `account`、`block_ai` | 从 `otpauth://` URI 录入 |
| `remove_account` | `account` | — | 删除账号 |
| `set_ai_allowed` | `account`、`allowed` | — | 允许 / 禁止个别账号 |

`account` 参数按「名称 / issuer / label / `Issuer (label)`」模糊匹配（大小写不敏感）；
匹配到多个时会报错要求写得更精确。

`generate_totp` 返回示例：

```json
{
  "account": "GitHub (me@github.com)",
  "code": "834074",
  "remaining_seconds": 18,
  "period": 30,
  "expires_at": "2030-01-01T00:00:18.000Z"
}
```

## 数据文件

默认目录 `~/.config/lzy_totp`（可用环境变量 `LZY_TOTP_HOME` 覆盖）：

| 文件 | 说明 | 权限 |
|---|---|---|
| `vault.json` | 账户元数据 + **密文**密钥 | `600` |
| `vault.key` | AES-256-GCM 密钥（32 字节 base64） | `600` |
| `audit.jsonl` | 审计日志（JSONL，只追加） | `600` |

> ⚠️ `vault.key` 与 `vault.json` 必须一起备份。密钥丢失后 vault 无法解密。

## 访问策略：默认放行 + 黑名单

| 原则 | 做法 |
|---|---|
| 默认放行 + 黑名单 | 新增账号 `ai_allowed=true`，AI 即可取码；敏感账号用 `lzy-totp deny <名称>` 关闭 |
| 只给码，不给密钥 | 工具面（含 `list_accounts`）**永不返回 secret** |
| 密钥加密落盘 | AES-256-GCM，密钥文件与 vault 权限均为 `600` |
| 全程可审计 | 每次取码（成功与拒绝都算）写入 `audit.jsonl`，记录来源 `cli` / `mcp` |
| 本地优先 | 纯本地进程，不开网络端口，不外传任何数据 |

```bash
# 录入（默认即允许 AI 取码）
lzy-totp add github --secret JBSWY3DPEHPK3PXP --issuer GitHub

# 录入时就禁止 AI（敏感账号）
lzy-totp add bank --secret JBSWY3DPEHPK3PXP --issuer Bank --block-ai

# 后续开关某个账号
lzy-totp deny "Bank (me@x.com)"
lzy-totp allow "Bank (me@x.com)"

# 也可以直接用 otpauth:// URI（扫码页二维码下方那串地址）
lzy-totp add google --uri 'otpauth://totp/Google:me@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google'

# 运维
lzy-totp list
lzy-totp audit --tail 20
lzy-totp doctor
```

## 人工应急通道

终端里人为查看**已被 deny** 的账号时，会提示确认：

```
$ lzy-totp code bank
账号「Bank」已被禁止 AI 取码。确认以人工身份查看验证码？[y/N]
```

这条通道**只在 stdin 为交互终端、且用户真的输入 `y` 时才生效**；AI 以子进程/管道方式调用时
（`stdin` 非终端，读不到输入）直接拒绝，并在审计里记为 `denied`。
人工确认通过的记录会带上 `note=human-tty-override`。

## 安全边界（务必了解）

- **能取码就等于能过 2FA**。当前策略是**默认放行**：只要账号在 vault 里，AI 就能取码。
  也就是说，vault 里放了什么账号，就等于把这些账号的第二因子交给了 AI。
- **提示注入是主要风险**：agent 的上下文里若混入恶意内容（网页、issue、邮件），可能诱导它去取某个账号的码。
  强烈建议把银行、主邮箱、云账号根凭据这类账号 **`lzy-totp deny` 掉**，或干脆不要放进 vault。
- 用 `lzy-totp list` 定期确认哪些账号处于放行状态。
- **不要开网络接口**。当前实现是纯 stdio / 本地进程，没有监听端口；如确需 HTTP 形态，
  必须限定 `127.0.0.1` 并自行加认证，且走 VPN/mTLS。
- **审计日志只追加不删除**，定期 `lzy-totp audit` 复查异常取码（尤其 `result=denied` 的密集出现，
  往往意味着有人在试探）。

## 排错

| 现象 | 原因与处理 |
|---|---|
| 客户端里看不到工具 | 先确认 `~/.local/bin/lzy-totp` 存在且可执行；多数客户端只认**绝对路径**，把配置里的路径写全 |
| `command not found` | 客户端启动的子进程不继承你的 shell PATH；改用绝对路径，或 `dart pub global activate --source path tools/totp_cli` 后用 `~/.pub-cache/bin/lzy_totp` |
| agent 说取码被拒绝 | 该账号被 `deny` 了：`lzy-totp list` 看 `ai_allowed`，需要就 `lzy-totp allow <名称>` |
| 提示「未找到账户」 | 账号在 App 里但不在 vault 里——App 用的是系统钥匙串，需要用 CLI 重新录入 |
| `vault.json` 读不了 / 解密失败 | `vault.key` 丢了或权限不对：确认两文件同在 `~/.config/lzy_totp` 且为 `600`，`lzy-totp doctor` 会自检 |
| 接入了但机器上原来有服务 | MCP server 由客户端按需拉起，退出客户端即结束进程；不存在常驻端口 |
| 想换数据目录 | 设 `LZY_TOTP_HOME`（客户端配置里的 `env`） |

`lzy-totp doctor` 会输出：数据目录、vault/密钥/审计三个文件是否存在及权限、账号数量、
其中被禁止取码的数量，以及当前策略一句话说明。

## App 内的入口

macOS / Android App 首页右上角的机器人图标（空列表时是「AI 接入说明」按钮）打开**AI 接入**页，
里面有三步接入说明、可直接复制的 MCP 配置 JSON 与 CLI 命令、7 个工具清单和安全提示。

![AI 接入说明页](images/app-ai-access.png)

## 开发与测试

```bash
# 共享内核
cd packages/totp_core && dart test        # RFC 6238 向量、加密 vault、策略、审计

# CLI 与 MCP
cd tools/totp_cli && dart test            # 命令行为、默认放行/黑名单、MCP 协议

# App（含 AI 接入页与删除交互）
flutter analyze && flutter test
```

测试覆盖的关键断言：

- RFC 6238 三套算法测试向量（SHA1/SHA256/SHA512）；
- **明文密钥不出现在 vault 文件中**、每次加密使用不同 nonce、文件权限为 600；
- 被 deny 的账号取码返回拒绝且**输出中不含任何 6 位数字**；
- 新增账号默认 `ai_allowed=true`（默认放行），`--block-ai` 后才拒绝；
- 非交互调用不会走人工确认通道；
- MCP 协议：initialize / tools/list / tools/call / 通知不响应 / 非法 JSON 返回 -32700；
- App：⋮ 菜单 / 长按 / 左滑三条路径都能删账号，删除先确认、可撤销、并且落库。
