# 让 AI 查询验证码（CLI + MCP）

lzy_totp 提供一个供 AI agent 调用的取码接口，形态是**一个内核两种外壳**：

- **CLI**：`lzy-totp code github --json` —— 任何能执行 shell 的 agent 都能用；
- **MCP server**：`lzy-totp mcp` —— 供 Claude Code / Cursor / DSH 等 MCP 客户端原生接入。

两者共用 `packages/totp_core` 里同一份 TOTP 实现、同一个加密 vault、同一套访问策略。

## 设计原则

| 原则 | 做法 |
|---|---|
| 默认放行 + 黑名单 | 新增账号 `ai_allowed=true`，AI 即可取码；敏感账号用 `lzy-totp deny <名称>` 关闭 |
| 只给码，不给密钥 | 工具面（含 `list_accounts`）**永不返回 secret**，只返回一次性验证码与元数据 |
| 密钥加密落盘 | vault 用 AES-256-GCM 加密，密钥文件与 vault 权限均为 `600` |
| 全程可审计 | 每次取码（成功与拒绝都算）写入 `audit.jsonl`，记录调用来源 `cli` / `mcp` |
| 本地优先 | 纯本地进程，不开网络端口，不外传任何数据 |

## 数据文件

默认目录 `~/.config/lzy_totp`（可用环境变量 `LZY_TOTP_HOME` 覆盖）：

| 文件 | 说明 | 权限 |
|---|---|---|
| `vault.json` | 账户元数据 + **密文**密钥 | `600` |
| `vault.key` | AES-256-GCM 密钥（32 字节 base64） | `600` |
| `audit.jsonl` | 审计日志（JSONL） | `600` |

> ⚠️ `vault.key` 与 `vault.json` 必须一起备份。密钥丢失后 vault 无法解密。

vault 是**独立于手机 App** 的存储：App 里的账号存在系统钥匙串（Android Keystore / macOS Keychain），
AI 侧只读取 vault 里的账号。这样做的好处是「哪些账号允许 AI 访问」这件事有明确的边界——
没进 vault 的账号，AI 连名字都看不到。

## 安装

方式一：编译成原生二进制（推荐，启动快）

```bash
cd tools/totp_cli
dart pub get
dart compile exe bin/lzy_totp.dart -o ~/.local/bin/lzy-totp
```

方式二：全局激活到 PATH

```bash
dart pub global activate --source path tools/totp_cli
# 可执行文件落在 ~/.pub-cache/bin/lzy_totp
```

## CLI 用法

```bash
# 录入账号（默认即允许 AI 取码）
lzy-totp add github --secret JBSWY3DPEHPK3PXP --issuer GitHub

# 录入时就禁止 AI 取码（敏感账号）
lzy-totp add bank --secret JBSWY3DPEHPK3PXP --issuer Bank --block-ai

# 也可以用 otpauth:// URI（扫码页二维码下方那串地址）
lzy-totp add-uri google --uri 'otpauth://totp/Google:me@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google'
# 注：uri 形式用 `lzy-totp add <名称> --uri '<otpauth://...>'`

# 查看账号（含 AI 是否可用）
lzy-totp list

# 关闭 / 恢复某个账号的 AI 取码
lzy-totp deny "Bank (me@x.com)"
lzy-totp allow "Bank (me@x.com)"

# 取码（AI 也走这条）
lzy-totp code github
lzy-totp code github --json
# {"account":"GitHub","code":"834074","remaining_seconds":18,"period":30,"expires_at":"..."}

# 运维
lzy-totp audit --tail 20
lzy-totp doctor
```

退出码：`0` 成功 / `1` 用法错误 / `2` 被策略拒绝 / `3` 未找到账户。

### 人工应急通道

终端里人为查看**已被 deny** 的账号时，会提示确认：

```
$ lzy-totp code bank
账号「Bank」已被禁止 AI 取码。确认以人工身份查看验证码？[y/N]
```

这条通道**只在 stdin 为交互终端、且用户真的输入 `y` 时才生效**；AI 以子进程/管道方式调用时
（`stdin` 非终端，读不到输入）直接拒绝，并在审计里记为 `denied`。
人工确认通过的记录会带上 `note=human-tty-override`。

## MCP 接入

启动方式（stdio 传输）：

```bash
lzy-totp mcp
```

客户端配置示例：

```json
{
  "mcpServers": {
    "lzy_totp": {
      "command": "/Users/<你>/.local/bin/lzy-totp",
      "args": ["mcp"]
    }
  }
}
```

环境变量方式指定数据目录（多环境隔离时有用）：

```json
{
  "mcpServers": {
    "lzy_totp": {
      "command": "/Users/<你>/.local/bin/lzy-totp",
      "args": ["mcp"],
      "env": { "LZY_TOTP_HOME": "/Users/<你>/.config/lzy_totp" }
    }
  }
}
```

### 工具清单

| 工具 | 作用 | 备注 |
|---|---|---|
| `list_accounts` | 列出账号与 `ai_allowed` 标记 | 不返回密钥 |
| `get_account_info` | 单个账号的元数据 | 不返回密钥 |
| `generate_totp` | 取当前验证码 | 默认放行；被 `deny` 的账号返回错误，不泄露任何码 |
| `add_account` | 录入账号 | 默认允许 AI；传 `block_ai=true` 可禁止 |
| `add_from_uri` | 从 otpauth URI 录入 | 同上 |
| `remove_account` | 删除账号 | |
| `set_ai_allowed` | 允许 / 禁止个别账号 | |

## 安全边界（务必了解）

- **能取码就等于能过 2FA**。当前策略是**默认放行**：只要账号在 vault 里，AI 就能取码。
  也就是说，vault 里放了什么账号，就等于把这些账号的第二因子交给了 AI。
- **提示注入是主要风险**：agent 的上下文里若混入恶意内容，可能诱导它去取某个账号的码。
  强烈建议把银行、主邮箱、云账号根凭据这类账号 **`lzy-totp deny` 掉**，或干脆不要放进 vault。
- 用 `lzy-totp list` 定期确认哪些账号处于放行状态。
- **不要开网络接口**。当前实现是纯 stdio / 本地进程，没有监听端口；如确需 HTTP 形态，
  必须限定 `127.0.0.1` 并自行加认证，且走 VPN/mTLS。
- **审计日志只追加不删除**，定期 `lzy-totp audit` 复查异常取码（尤其 `result=denied` 的密集出现，
  往往意味着有人在试探）。

## 开发与测试

```bash
# 共享内核
cd packages/totp_core && dart test        # RFC 6238 向量、加密 vault、策略、审计

# CLI 与 MCP
cd tools/totp_cli && dart test            # 命令行为、默认放行/黑名单、MCP 协议
```

测试覆盖的关键断言：

- RFC 6238 三套算法测试向量（SHA1/SHA256/SHA512）；
- **明文密钥不出现在 vault 文件中**、每次加密使用不同 nonce、文件权限为 600；
- 被 deny 的账号取码返回拒绝且**输出中不含任何 6 位数字**；
- 新增账号默认 `ai_allowed=true`（默认放行），`--block-ai` 后才拒绝；
- 非交互调用不会走人工确认通道；
- MCP 协议：initialize / tools/list / tools/call / 通知不响应 / 非法 JSON 返回 -32700。
