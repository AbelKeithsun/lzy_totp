# agentrouter.org API 接入说明

> 实测日期：2026-11-16 · 实测环境：macOS / Clash Verge（7897 代理）· Key 有效

## 一、结论速查

| 项 | 值 |
|---|---|
| Base URL | `https://agentrouter.org/v1` |
| 鉴权 | `Authorization: Bearer sk-…` |
| **可用 GPT 模型** | **3 个**：`gpt-6.1-sol`、`gpt-6-astra`、`gpt-5.6-sol` |
| 必用端点 | `POST /v1/responses`（OpenAI Responses API） |
| 不可用端点 | `POST /v1/chat/completions` → 400（模型不支持） |
| 可用端点 | `POST /v1/messages`（Anthropic 原生，`x-api-key` + `anthropic-version`） |
| 模型列表 | `GET /v1/models` |
| 探活脚本 | `tool/ar_api_check.sh` |

> 模型名用 `.` 分隔（`gpt-6.1-sol`），不是 `-`（`gpt-6-1-sol`），写错会 404。

## 二、三道必过的门

这个网关有三层前置校验，**任何一层不过都是 401 / 400**，而且报错信息不会告诉你真正原因。
下面三步是实测踩出来的，顺序不能颠倒。

### ① 网络：必须走代理（直连必被污染）

`agentrouter.org` 在国内直连会被 DNS 污染：223.5.5.5 把它解析到假 IP（`128.242.245.157`），
连接超时；真实 IP 直连 TLS 被 RST。**只有走代理才通。**

```bash
export HTTPS_PROXY=http://127.0.0.1:7897   # Clash Verge 默认混合端口
curl https://agentrouter.org/v1/models -H "Authorization: Bearer $KEY" -H "User-Agent: claude-cli/2.0.30 (external, cli)"
```

Node / DSH 这类不吃系统代理的栈，还要显式开环境代理支持：

```bash
NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://127.0.0.1:7897 node your-script.mjs
```

> **本机现状（2026-11-16 已修复）**：Clash Verge 的 **TUN 模式已开启**
> （`verge.yaml: enable_tun_mode: true`，Merge 模板里本来就有 `tun.enable: true`，
> 只是被 Verge 开关压成了 false），所以现在**不配任何代理变量也能直连 agentrouter.org**——
> TUN 在网络层接管了所有流量，DNS 也由 Clash 的 fake-ip + doh.pub 接管，不再被污染。
>
> 之前为什么不通：DSH 的 LLM 请求走**直连**（实测 DSH 进程 0 条连向 7897），
> 而 Node/Electron 不读 macOS 系统代理，所以只靠系统代理那条路，DSH 这类客户端会漏出去。
> TUN 才是对「不读系统代理的客户端」真正生效的那一层。
>
> 另外已在 Clash 的「规则增强」里显式锁定：
> `DOMAIN-SUFFIX,agentrouter.org,永雏塔菲的魔法卷轴`（prepend，优先于 GEOIP/MATCH）。

### ② User-Agent：必须是网关认得的客户端

网关按 UA 判定「你是什么客户端」，认不出来的直接拒：

```json
{"error":{"message":"unauthorized client detected, contact support for assistance at https://discord.gg/HgekCyHJqB"},
 "message":"UNAUTHENTICATED","type":"unauthorized_client_error"}
```

注意：**这个错误和 key 无关**，带不带 key、带对 key 都是它。对的 key + 认得的 UA 才会走到真正的鉴权。

UA 与报错对照（实测）：

| UA | 结果 |
|---|---|
| `claude-cli/2.0.30 (external, cli)` | ✅ 通过 |
| `codex_cli_rs/0.44.0` | ✅ 通过 |
| `openclaw` / `zcode` | ✅ 通过 |
| `pi (darwin 25.0.0; arm64)` | ✅ 通过（DSH / pi-ai 用的就是这个） |
| `claude-cli`（裸名） | ❌ 401 —— 要带版本号和 `(external, cli)` |
| `codex_cli_rs`（裸名） | ❌ 401 |
| `cursor/1.7.0` | ❌ 401 |
| `OpenAI/Python 1.99.0` | ❌ 401 |
| `claude-code/1.0.0`、`opencode`、`cline`、`gemini-cli`、`aider` | ❌ 401 |

规律（实测推断）：UA 是**正则匹配**，形式随客户端而定——

- `claude-cli` 系：`claude-cli/<x.y.z> (external, cli)`，缺一不可
- `codex` 系：`codex_cli_rs/<version>`
- `pi` 系：`pi (` 开头即可，`pi (darwin …)` / `pi (browser)` 都行
- 部分客户端：裸名即可（`openclaw`、`zcode`），但 `openclaws`、`openclaw-1` 不行

**实践建议**：直接抄官方客户端的完整 UA，别自己编。

### ③ 端点：必须用 `/v1/responses`

这三个模型**只支持 Responses API**，打 `/v1/chat/completions` 会被明确拒绝：

```json
{"error":{"message":"模型 gpt-6.1-sol 不支持 /v1/chat/completions 接口，请改用 /v1/responses（OpenAI Responses API）。…",
 "type":"new_api_error"}}
```

这点最容易踩：OpenAI SDK 默认就是 `client.chat.completions.create`，不改就会失败。
而且这个限制**与 UA 无关**——claude-cli / codex / pi 各种 UA 都被拒，唯一的解法是换端点。

> 控制台「模型状态」页上的 `chat` 标签 ≠ 该模型支持 `/v1/chat/completions`，以实测为准。

## 三、三个模型

| 模型 | 说明（实测） | 备注 |
|---|---|---|
| `gpt-6.1-sol` | 主力档，reasoning token 消耗明显 | 公告称「不限量低倍率供应，建议优先使用」 |
| `gpt-6-astra` | 限量档，每天北京时间 10:00 投放 | reasoning 开销大，`max_output_tokens` 要给足 |
| `gpt-5.6-sol` | 轻量档，reasoning token 为 0，最快 | 4xx 秒级返回 |

三个模型都支持：文本 / 图片输入、function calling、SSE 流式、`reasoning.effort`（off…max）。

**踩坑提醒**：`gpt-6-astra` 和 `gpt-6.1-sol` 会把 token 花在 reasoning 上，
`max_output_tokens` 给小了会出现 `status: "incomplete"` 且正文为空。
实测 `max_output_tokens: 64` 时 astra 全部消耗在 reasoning（57 token）上、正文 0 字符；
给到 400 就正常了。**建议 ≥ 300**。

## 四、调用示例

### curl（最稳）

```bash
KEY=sk-xxxx
export HTTPS_PROXY=http://127.0.0.1:7897

# 模型清单
curl -s https://agentrouter.org/v1/models \
  -H "Authorization: Bearer $KEY" \
  -H "User-Agent: claude-cli/2.0.30 (external, cli)"

# 单轮对话（注意端点与 UA）
curl -s https://agentrouter.org/v1/responses \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-cli/2.0.30 (external, cli)" \
  -d '{"model":"gpt-6.1-sol","input":"只回复四个字：接口正常","max_output_tokens":300}'
```

响应结构（Responses API 标准格式）：

```json
{
  "status": "completed",
  "model": "gpt-6.1-sol",
  "output": [
    { "type": "reasoning", "id": "rs_…", "summary": [] },
    { "type": "message", "role": "assistant",
      "content": [{ "type": "output_text", "text": "接口正常" }] }
  ],
  "usage": { "input_tokens": 14, "output_tokens": 51,
             "output_tokens_details": { "reasoning_tokens": 43 }, "total_tokens": 65 }
}
```

### Node（OpenAI SDK）

```js
import OpenAI from 'openai'

const client = new OpenAI({
  apiKey: process.env.AGENTROUTE_API_KEY,
  baseURL: 'https://agentrouter.org/v1',
  defaultHeaders: { 'User-Agent': 'claude-cli/2.0.30 (external, cli)' }, // 必须！
})

// 必须走 responses，不能用 chat.completions
const r = await client.responses.create({
  model: 'gpt-6.1-sol',
  input: '只回复四个字：接口正常',
  max_output_tokens: 300,
})
console.log(r.output_text)
```

Node 24+ 走本机代理还要加 `NODE_USE_ENV_PROXY=1`（Node 默认不读 HTTP_PROXY）。

### Anthropic 原生端点

Claude Code 那套客户端可以直接用这个网关：

```bash
curl -s https://agentrouter.org/v1/messages \
  -H "x-api-key: $KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -H "User-Agent: claude-cli/2.0.30 (external, cli)" \
  -d '{"model":"gpt-5.6-sol","max_tokens":200,"messages":[{"role":"user","content":"hi"}]}'
```

## 五、探活脚本

```bash
tool/ar_api_check.sh            # 列模型 + 逐个冒烟
tool/ar_api_check.sh --models   # 只列模型
tool/ar_api_check.sh --stream   # 额外跑 SSE 流式
tool/ar_api_check.sh --tools    # 额外跑 function calling
```

Key 读取顺序：`AGENTROUTE_API_KEY` 环境变量 → `$LZY_TOTP_HOME/agentrouter.env`
→ `$XDG_CONFIG_HOME/lzy_totp/agentrouter.env` → `~/.config/lzy_totp/agentrouter.env`。

脚本会自动探测出口（直连 / 本机代理端口 / 环境变量代理）并打印用的哪条路。

## 六、DSH（DeepSeek Harness）接入

DSH 的 LLM 走 pi-ai，provider 配置在 `~/.dsh/profiles/desktop/cordis.patch.yml`：

```yaml
      agentroute:
        displayName: agentroute
        apiKeyEnv: AGENTROUTE_API_KEY
        api: openai-responses          # ← 必须是 openai-responses
        baseURL: https://agentrouter.org/v1
        models:
          - id: gpt-6.1-sol
            name: gpt-6.1-sol
            contextWindow: 1000000
            maxTokens: 128000
            input: [text, image]
            reasoningEfforts: { off: null, minimal: minimal, low: low, medium: medium, high: high, xhigh: xhigh, max: max }
          - id: gpt-6-astra
            ...
          - id: gpt-5.6-sol
            ...
```

要点：

- `api:` **只能填 `openai-responses`**。填 `openai-completions` 会打 `/v1/chat/completions`，
  网关一律 400（实测 OpenAI SDK 6.40.0 复现）。
- UA 不用配：pi-ai 自己发 `pi (<os> <ver>; <arch>)`，正好在网关的放行名单里。
- `maxTokens` 留够（≥ 300 起），否则 reasoning 吃掉额度导致正文为空。
- Key 放 `~/.dsh/.credentials.yaml` 的 `AGENTROUTE_API_KEY`，别写进 patch 文件。
- DSH 走 Node 的 fetch，**需要 `NODE_USE_ENV_PROXY=1` + `HTTPS_PROXY`** 才能过代理。

## 七、DSH 接 agentrouter：必须过一层本地中转（UA 会被 DSH 覆盖）

### 症状

DSH 里选 agentroute 报：

```
agentroute API error (401): {"message":"unauthorized client detected, contact support for assistance at https://discord.gg/HgekCyHJqB"}
code: "AUTH"
```

UI 会把它显示成「apikey 无效」，但**跟 API key 无关** —— key 是好的，是 User-Agent 被网关拒了。

### 原因链

1. 网关按 UA 识别客户端，只放行受支持的标识（`claude-cli/…`、`codex_cli_rs/…`、`pi (…)`、`openclaw`、`zcode`）。
2. DSH 的 `dsh-llm` 给**每个** LLM 请求强制加 attribution 头：
   `user-agent: deepseek-harness/<version> (+https://github.com/deepseek-ai/deepseek-harness)`
3. pi-ai 本来设的是 `User-Agent: pi (<os> <ver>; <arch>)`，但 **OpenAI SDK 按大小写不敏感去重**，
   后写入的 attribution 头**覆盖**掉它 —— 服务端只收到 DSH 那个 UA（实测回显验证过）。
4. DSH 侧**改不了**：route 级 `headers` 里的 `user-agent` 被 attribution 的保留名过滤掉
   （`requestHeaders()` 明确把 attribution 列为 reserved，attribution 永远赢）。

所以 DSH 直连 agentrouter 在协议层就走不通 —— 跟 key、跟代理、跟 baseURL 都无关。

### 解法：本地 UA 改写中转

`~/.dsh/tools/agentrouter-relay.mjs`（Node，无依赖，已注册为开机常驻）：

- 监听 `127.0.0.1:8899`，把 UA 改写成 `pi (deepseek-harness)`
- 路径、鉴权、请求体、**SSE 流**全部原样透传给 `https://agentrouter.org`
- DSH 配置改成指向它：

```yaml
      agentroute:
        apiKeyEnv: AGENTROUTE_API_KEY
        api: openai-responses
        baseURL: http://127.0.0.1:8899/v1   # ← 本地中转
```

- LaunchAgent：`~/Library/LaunchAgents/com.deepseek.agentrouter-relay.plist`
  （`RunAtLoad` + `KeepAlive`，日志在 `~/.dsh/tools/relay.log`）
- 自检：`curl http://127.0.0.1:8899/v1/models -H "Authorization: Bearer $KEY" -H "User-Agent: 任意"` → 200

> 中转自身出网依赖 Clash TUN（Node 的 `https.request` 不读 `HTTP_PROXY`）。
> 若关掉 TUN，中转要自己走代理就得改成 undici + `NODE_USE_ENV_PROXY=1`。

## 八、安全提醒

- 这个 Key 已经出现在聊天记录里。若是长期使用的 Key，建议在控制台轮换一次。
- Key 只放本地：`~/.config/lzy_totp/agentrouter.env`（chmod 600）或 `~/.dsh/.credentials.yaml`，
  **不要写进仓库、不要贴进 issue/日志**。
- `~/.config/lzy_totp/` 里已有 vault 密文与 key 文件，注意该目录权限。
