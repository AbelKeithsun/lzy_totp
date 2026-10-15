#!/usr/bin/env bash
#
# 把 lzy-totp 安装成一个普通的命令行工具（像 curl / vim 那样：
# 敲一次命令、取一次码、进程立刻退出，**不常驻、不占后台、不开端口**）。
#
# 用法：
#   tool/install_cli.sh                     # 编译并装到 ~/.local/bin/lzy-totp
#   tool/install_cli.sh --prefix /usr/local/bin
#   tool/install_cli.sh --link ~/bin        # 只做软链（已编译过时用）
#
# 说明：
#   编译产物是 AOT 原生二进制（约 6.5 MB），启动约 40~50 ms，
#   直接读 ~/.config/lzy_totp 下的加密 vault，不依赖 App 运行。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${HOME}/.local/bin"
DO_COMPILE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix 需要目录}"; shift 2 ;;
    --link) PREFIX="${2:?--link 需要目录}"; DO_COMPILE=0; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "未知参数：$1（用 --help 看用法）" >&2; exit 2 ;;
  esac
done

TARGET="$PREFIX/lzy-totp"
mkdir -p "$PREFIX"

if [[ "$DO_COMPILE" == "1" ]]; then
  echo "▶ 编译 CLI（AOT 原生二进制，启动约 40~50ms）"
  (cd "$REPO_ROOT/tools/totp_cli" && dart pub get >/dev/null && \
     dart compile exe bin/lzy_totp.dart -o "$TARGET")
else
  BUILT="$REPO_ROOT/tools/totp_cli/build/lzy-totp"
  [[ -f "$BUILT" ]] || { echo "找不到已编译产物：$BUILT" >&2; exit 1; }
  cp "$BUILT" "$TARGET"
  echo "▶ 已复制现有产物到 $TARGET"
fi

chmod +x "$TARGET"

echo "▶ 自检"
"$TARGET" doctor | sed 's/^/  /'

# PATH 检查：不在 PATH 里就给出该加哪一行
case ":$PATH:" in
  *":$PREFIX:"*) echo "✅ $PREFIX 已在 PATH 中，任意终端/脚本/agent 可直接调用 lzy-totp" ;;
  *)
    echo "⚠️  $PREFIX 不在当前 PATH 中，请把下面这行加到 ~/.zshrc（或 ~/.bashrc）后重开终端："
    echo "      export PATH=\"$PREFIX:\$PATH\""
    ;;
esac

cat <<'TIP'

日常用法（一次性取码，跑完即退，无后台进程、无监听端口）：
  lzy-totp code            # vault 只有一个账号时可直接省略名称
  lzy-totp code github     # 指定账号
  lzy-totp code github --json
  lzy-totp list / info / audit / doctor

想让 agent 以「服务」形式接入（会常驻监听本机回环），那是另一条路：
  lzy-totp serve           # 或 App 设置页里的「启动 MCP 服务」开关
TIP
