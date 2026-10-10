#!/usr/bin/env bash
#
# 本地升级：构建 →（可选）签名 → 停掉旧版 → 安装到 /Applications → 启动。
#
# 用法：
#   tool/macos/upgrade_local.sh                 # 完整流程
#   tool/macos/upgrade_local.sh --no-sign       # 不重签（保持 ad-hoc）
#   tool/macos/upgrade_local.sh --no-build      # 用现有构建产物，只做安装
#   tool/macos/upgrade_local.sh --no-launch     # 装完不自动打开
#
# 说明：
#   本项目的既定取舍是**接受每次升级点一次钥匙串授权**（不引入 Apple 证书，
#   原因见 README「关于…弹窗」）。升级后第一次打开若弹
#   「lzy_totp 想使用您钥匙串中的机密信息」，点「允许」即可，同一版本不会重复弹。
#   本脚本**不修改钥匙串条目**——授权交给你在弹窗上点一次，避免脚本碰你的机密数据。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DO_BUILD=1
DO_SIGN=1
DO_LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --no-sign) DO_SIGN=0 ;;
    --no-launch) DO_LAUNCH=0 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "未知参数：$arg（用 --help 看用法）" >&2; exit 2 ;;
  esac
done

APP="$REPO_ROOT/build/macos/Build/Products/Release/lzy_totp.app"
INSTALLED="/Applications/lzy_totp.app"

if [[ "$DO_BUILD" == "1" ]]; then
  echo "▶ 构建 macOS Release（国内镜像拉取引擎产物）"
  FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}" \
    flutter build macos --release
fi

if [[ ! -d "$APP" ]]; then
  echo "找不到构建产物：$APP（先去掉 --no-build 跑一次）" >&2
  exit 1
fi

if [[ "$DO_SIGN" == "1" ]]; then
  echo "▶ 重新签名（有 Apple 证书会自动用它，否则用本机自签名）"
  "$REPO_ROOT/tool/macos/sign_local.sh" "$APP" || {
    rc=$?
    [[ $rc -eq 2 ]] || exit $rc
    echo "  （未做签名，继续以现有签名安装）"
  }
fi

echo "▶ 停掉正在运行的旧版"
osascript -e 'tell application "lzy_totp" to quit' >/dev/null 2>&1 || true
sleep 2
pkill -f "lzy_totp.app/Contents/MacOS/lzy_totp" >/dev/null 2>&1 || true
sleep 1

echo "▶ 安装到 $INSTALLED"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
xattr -dr com.apple.quarantine "$INSTALLED" 2>/dev/null || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALLED/Contents/Info.plist")"
TEAM="$(codesign -dvv "$INSTALLED" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
AUTHORITY="$(codesign -dvv "$INSTALLED" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
codesign --verify --deep --strict "$INSTALLED" >/dev/null 2>&1 && VERIFY="签名完整" || VERIFY="签名校验未通过"
if [[ "${TEAM:-not set}" == "not set" ]]; then VERIFY="${VERIFY}（非 Apple 签发，系统不信任它，Gatekeeper 行为与 ad-hoc 一致）"; fi

cat <<EOF
✅ 已安装 lzy_totp $VERSION
   签名：${AUTHORITY:-未知}（TeamIdentifier=${TEAM:-not set}，${VERIFY}）
   位置：$INSTALLED

ℹ️  升级后第一次打开若弹「lzy_totp 想使用您钥匙串中的机密信息」，
   点「允许」即可（每次升级一次，同一版本不会重复弹）。
   AI 侧（lzy-totp CLI / MCP）不读钥匙串，永远不会有这个弹窗。
EOF

if [[ "$DO_LAUNCH" == "1" ]]; then
  echo "▶ 启动"
  open -a "$INSTALLED"
fi
