#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# agentrouter.org API 探活脚本
#
#   用法：
#     tool/ar_api_check.sh              # 列出模型 + 逐个冒烟
#     tool/ar_api_check.sh --models     # 只列模型
#     tool/ar_api_check.sh --stream     # 额外跑一次 SSE 流式
#     tool/ar_api_check.sh --tools      # 额外跑一次 function calling
#
#   API Key 读取顺序（都不写进仓库）：
#     1. 环境变量 AGENTROUTE_API_KEY
#     2. $LZY_TOTP_HOME/agentrouter.env
#     3. $XDG_CONFIG_HOME/lzy_totp/agentrouter.env
#     4. ~/.config/lzy_totp/agentrouter.env
#
#   三个必过的门（否则一律 401「unauthorized client detected」）：
#     ① 网络：agentrouter.org 直连被 DNS 污染，必须走代理（本机 Clash 7897）
#     ② User-Agent：必须是网关认得的客户端标识（见 docs/agentrouter-api.md）
#     ③ 端点：这三个模型只支持 /v1/responses，不支持 /v1/chat/completions
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

BASE="${AGENTROUTE_BASE_URL:-https://agentrouter.org/v1}"
# 网关按 UA 识别客户端；官方支持列表里的标识都能过（见 docs/agentrouter-api.md）
UA="${AGENTROUTE_UA:-claude-cli/2.0.30 (external, cli)}"
MODE="${1:-all}"

# ── 取 key ──────────────────────────────────────────────────────────────────
key_from_file() {
  local f v
  for f in \
    "${LZY_TOTP_HOME:-}/agentrouter.env" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/lzy_totp/agentrouter.env" \
    "$HOME/.config/lzy_totp/agentrouter.env"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    v="$(python3 - "$f" <<'PYEOF'
import re, sys
for line in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    m = re.match(r"(AGENTROUTE_API_KEY|API_KEY)\s*=\s*(.+)$", line)
    if m:
        print(m.group(2).strip().strip("\"'"), end="")
        break
PYEOF
)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  return 1
}

KEY="${AGENTROUTE_API_KEY:-}"
if [ -z "$KEY" ]; then
  KEY="$(key_from_file)" || {
    echo "✗ 找不到 API Key：请设 AGENTROUTE_API_KEY，或在 ~/.config/lzy_totp/agentrouter.env 写一行" >&2
    echo "  AGENTROUTE_API_KEY=sk-..." >&2
    exit 2
  }
fi
[ -n "$KEY" ] || { echo "✗ API Key 为空" >&2; exit 2; }

# ── 选出口 ──────────────────────────────────────────────────────────────────
# 三种候选：环境变量里已有的代理 → 本机常见代理端口 → 真·直连
# （agentrouter.org 直连会被 DNS 污染成假 IP，连接超时）
probe() { # probe <http_code>
  [ "$1" = "200" ]
}
try_env_proxy() {
  local code
  code="$(env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy \
    curl -s --max-time 8 -o /dev/null -w '%{http_code}' "$BASE/models" \
      -H "Authorization: Bearer $KEY" -H "User-Agent: $UA" 2>/dev/null)"
  if probe "$code"; then
    echo "直连 ✓（无代理，DNS 未被污染）"; return 0
  fi
  return 1
}
try_local_proxy() {
  local port code
  for port in "${AGENTROUTE_PROXY_PORT:-7897}" 7890 1080 10809 8888; do
    nc -z -G 1 127.0.0.1 "$port" 2>/dev/null || continue
    code="$(HTTPS_PROXY="http://127.0.0.1:$port" HTTP_PROXY="http://127.0.0.1:$port" \
      curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$BASE/models" \
        -H "Authorization: Bearer $KEY" -H "User-Agent: $UA" 2>/dev/null)"
    if probe "$code"; then
      export HTTPS_PROXY="http://127.0.0.1:$port" HTTP_PROXY="http://127.0.0.1:$port"
      echo "本地代理 ✓ (127.0.0.1:$port)"; return 0
    fi
  done
  return 1
}
try_inherited_proxy() {
  [ -n "${HTTPS_PROXY:-}${HTTP_PROXY:-}${https_proxy:-}${http_proxy:-}" ] || return 1
  local code
  code="$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' "$BASE/models" \
    -H "Authorization: Bearer $KEY" -H "User-Agent: $UA" 2>/dev/null)"
  if probe "$code"; then
    echo "环境变量代理 ✓ (${HTTPS_PROXY:-$http_proxy})"; return 0
  fi
  return 1
}

pick_route() {
  try_env_proxy && return 0
  try_local_proxy && return 0
  try_inherited_proxy && return 0
  echo "✗ 三种出口都失败：直连被 DNS 污染，本机也没找到可用代理" >&2
  return 1
}

api() { # api <method> <path> [body]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s --max-time 180 -X "$method" "$BASE$path" \
      -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
      -H "User-Agent: $UA" -d "$body"
  else
    curl -s --max-time 180 -X "$method" "$BASE$path" \
      -H "Authorization: Bearer $KEY" -H "User-Agent: $UA"
  fi
}

echo "▶ base=$BASE"
echo "▶ UA=$UA"
echo -n "▶ 出口 "; pick_route || exit 3
echo

# ── 模型清单 ────────────────────────────────────────────────────────────────
MODELS_JSON="$(api GET /models)"
MODELS="$(printf '%s' "$MODELS_JSON" | python3 -c "$(cat <<'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print(""); raise SystemExit
if "data" not in d:
    print(""); raise SystemExit
print(" ".join(m["id"] for m in d["data"]))
PYEOF
)" 2>/dev/null)"

if [ -z "$MODELS" ]; then
  echo "✗ /v1/models 没返回模型列表，原始响应："
  printf '%s\n' "$MODELS_JSON" | head -c 500; echo
  exit 4
fi

echo "▶ 可用模型（$(printf '%s\n' $MODELS | wc -l | tr -d ' ') 个）：$(printf '%s ' $MODELS)"
echo

if [ "$MODE" = "--models" ]; then exit 0; fi

# ── 逐个冒烟（走 /v1/responses，不是 chat/completions）────────────────────────
for m in $MODELS; do
  printf '%-16s ' "$m"
  t0=$(date +%s)
  out="$(api POST /responses "{\"model\":\"$m\",\"input\":\"只回复四个字：接口正常\",\"max_output_tokens\":400}")"
  t1=$(date +%s)
  printf '%s' "$out" | python3 -c "$(cat <<'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("✗ 响应不是 JSON"); raise SystemExit
if d.get("error"):
    print("✗", str(d["error"])[:140]); raise SystemExit
txt = ""
for o in d.get("output", []):
    if o.get("type") == "message":
        for c in o.get("content", []):
            txt += c.get("text", "")
u = d.get("usage", {})
print("✓ status=%s out=%s tok  reply=%r" % (d.get("status"), u.get("output_tokens"), txt.strip()[:24]))
PYEOF
)"
  echo "   ⏱  $((t1-t0))s"
done

# ── 可选：流式 ──────────────────────────────────────────────────────────────
if [ "$MODE" = "--stream" ]; then
  echo; echo "▶ SSE 流式（gpt-6.1-sol）"
  curl -sN --max-time 180 -X POST "$BASE/responses" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -H "User-Agent: $UA" \
    -d '{"model":"gpt-6.1-sol","input":"用一句话介绍你自己","stream":true,"max_output_tokens":400}' \
  | python3 -c "$(cat <<'PYEOF'
import json, sys
for line in sys.stdin:
    if line.startswith("data: "):
        try:
            d = json.loads(line[6:])
        except Exception:
            continue
        if d.get("type") == "response.output_text.delta":
            sys.stdout.write(d.get("delta", ""))
print()
PYEOF
)"
fi

# ── 可选：function calling ─────────────────────────────────────────────────
if [ "$MODE" = "--tools" ]; then
  echo; echo "▶ Function calling（gpt-6.1-sol）"
  api POST /responses '{"model":"gpt-6.1-sol","input":"北京天气怎么样？用工具查。","max_output_tokens":300,"tools":[{"type":"function","name":"get_weather","description":"查询城市天气","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}]}' \
  | python3 -c "$(cat <<'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("✗ 响应不是 JSON"); raise SystemExit
if d.get("error"):
    print("✗", str(d["error"])[:200]); raise SystemExit
hit = False
for o in d.get("output", []):
    if o.get("type") == "function_call":
        hit = True
        print("  ✓ function_call %s(%s)" % (o.get("name"), o.get("arguments")))
if not hit:
    print("  （本次没有产生工具调用）")
PYEOF
)"
fi
