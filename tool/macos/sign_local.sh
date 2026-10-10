#!/usr/bin/env bash
#
# 用「固定的本机自签名证书」给已构建好的 macOS App 重新签名。
#
# 为什么需要：
#   Flutter 默认用 ad-hoc 签名（`Signature=adhoc`），其身份就是 cdhash——每次重新构建
#   都会变。macOS 钥匙串条目的 ACL 记的是应用身份，于是**每次升级都会弹一次**
#   「lzy_totp 想使用您钥匙串中的机密信息」。
#   换成固定证书签名后，ACL 记的是「identifier + 证书指纹」，重建不再触发弹窗。
#
# 用法：
#   tool/macos/sign_local.sh build/macos/Build/Products/Release/lzy_totp.app
#   tool/macos/sign_local.sh <app> "别的证书名"
#
# 前置条件（一次性，见 README「macOS 签名」一节）：
#   ~/.lzy_totp-signing/ 下有自签名证书与私钥，并已导入登录钥匙串。
#   没有该证书时本脚本会给出提示并以 2 退出，正常 ad-hoc 流程不受影响。
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "用法：$(basename "$0") <lzy_totp.app> [identity]" >&2
  exit 2
fi

IDENTITY="${2:-lzy_totp Local Signing}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENTITLEMENTS="$REPO_ROOT/macos/Runner/Release.entitlements"

if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "未在钥匙串中找到证书「$IDENTITY」——请先按 README 生成并导入本机签名证书。" >&2
  echo "（不做这一步也能用：保持 ad-hoc 签名的 App 照常运行，只是升级后可能要点一次钥匙串授权。）" >&2
  exit 2
fi

echo "使用身份：$IDENTITY"
echo "entauths ：$ENTITLEMENTS"

# 由内向外签名：先签内嵌 framework / dylib，最后签主 bundle（带 entitlements）
while IFS= read -r -d '' fw; do
  echo "  签 framework: ${fw#"$APP"/}"
  codesign --force --sign "$IDENTITY" "$fw"
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 2>/dev/null)

while IFS= read -r -d '' lib; do
  echo "  签 dylib: ${lib#"$APP"/}"
  codesign --force --sign "$IDENTITY" "$lib"
done < <(find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null)

codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"

echo "--- 签名结果"
codesign -dvv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true
codesign -d --entitlements - "$APP" 2>&1 | grep -A2 "app-sandbox" || true
codesign --verify --deep --strict "$APP" && echo "✅ 签名校验通过（自签名未被系统信任，Gatekeeper 行为与 ad-hoc 时一致）"
