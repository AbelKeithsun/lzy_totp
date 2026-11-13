#!/usr/bin/env bash
#
# 本地升级：构建 →（默认不重签）→ 停掉旧版 → 安装到 /Applications → 启动。
#
# 用法：
#   tool/macos/upgrade_local.sh              # 完整流程；签名=auto（有 Apple 签发身份就自动签）
#   tool/macos/upgrade_local.sh --sign       # 强制重签（没有 Apple 身份时会退回本机自签名）
#   tool/macos/upgrade_local.sh --no-sign    # 强制不重签（保持 ad-hoc）
#   tool/macos/upgrade_local.sh --no-build   # 用现有构建产物，只做安装
#   tool/macos/upgrade_local.sh --no-launch  # 装完不自动打开
#
# 签名策略 auto（推荐）：
#   · 钥匙串里有 Apple Development / Developer ID 身份 → 用它重签（团队 ID 稳定，弹窗消失）；
#   · 没有 → 跳过重签，保持 ad-hoc（不碰本机自签名，避免 codesign 取私钥的额外弹窗）。
#
# 为什么默认不重签（2026-10-15 实测）：
#   用本机**自签名证书**重签不但减少不了 App 读钥匙串的授权弹窗（分区仍按 cdhash 判定，
#   实测同一 cdhash 在同一会话里还会被二次询问），反而会让 codesign 每次构建都去取签名私钥，
#   **额外**触发 4~8 次钥匙串授权（一天实测 12 次弹窗里有 8 次来自 /usr/bin/codesign）。
#   要真正免掉弹窗只能用 Apple 签发的证书（团队 ID 稳定）——见 README「关于钥匙串弹窗」。
#
# 关于弹窗：
#   新 cdhash（即重新构建过）第一次打开会弹一次；同一版本重复打开不会弹。
#   本脚本**不修改钥匙串条目**——授权交给你在弹窗上点，避免脚本碰你的机密数据。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DO_BUILD=1
DO_SIGN=auto       # auto=有 Apple 签发身份才重签；1=强制签；0=不签
DO_LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=0 ;;
    --sign) DO_SIGN=1 ;;
    --no-sign) DO_SIGN=0 ;;
    --sign) DO_SIGN=1 ;;
    --no-launch) DO_LAUNCH=0 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "未知参数：${arg}（用 --help 看用法）" >&2; exit 2 ;;
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
  echo "找不到构建产物：${APP}（先去掉 --no-build 跑一次）" >&2
  exit 1
fi

if [[ "$DO_SIGN" == "auto" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null \
      | grep -qE 'Apple Development|Developer ID Application'; then
    echo "▶ 检测到 Apple 签发身份 → 自动重签（团队 ID 稳定，升级后不再弹钥匙串）"
    DO_SIGN=1
  else
    echo "▶ 未检测到 Apple 签发身份 → 跳过重签，保持 ad-hoc（本机自签名不再默认使用）"
    echo "  · 自签名既消不掉弹窗，还会让 codesign 每次取私钥多弹几次"
    echo "  · 想彻底免弹窗：Xcode ▸ Settings ▸ Accounts 用免费 Apple ID 登录，"
    echo "    再 Manage Certificates ▸ + ▸ Apple Development（步骤见 README）"
    DO_SIGN=0
  fi
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

if [[ "${TEAM:-not set}" != "not set" ]]; then
  PROMPT_NOTE="✅ 已用 Apple 证书签名（TeamIdentifier=\${TEAM}）：钥匙串分区走 teamid，
   重新构建/升级后**不会再弹**授权（2026-11-13 实测：重建后启动 0 次弹窗）。"
else
  PROMPT_NOTE="ℹ️  当前是 ad-hoc 签名：重新构建（新 cdhash）后第一次打开会弹一次授权，
   点「允许」即可；同一版本重复打开不弹。想彻底免弹窗：用免费 Apple ID 生成
   Apple Development 证书（见 README「用 Apple ID 生成证书」一节）。
   AI 侧（lzy-totp CLI / MCP）不读钥匙串，永远不会有这个弹窗。"
fi

cat <<EOF
✅ 已安装 lzy_totp \$VERSION
   签名：${AUTHORITY:-未知}（TeamIdentifier=${TEAM:-not set}，${VERIFY}）
   位置：\$INSTALLED

\${PROMPT_NOTE}
EOF

if [[ "$DO_LAUNCH" == "1" ]]; then
  echo "▶ 启动"
  open -a "$INSTALLED"
fi
