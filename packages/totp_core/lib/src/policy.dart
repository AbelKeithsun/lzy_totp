import 'account.dart';

/// AI / 自动化工具访问策略。
///
/// **默认放行（default-allow）**：账号新增后 `aiAllowed = true`，AI 立即可取码。
/// 如需关闭个别账号（例如银行、主邮箱），用 `lzy-totp deny <名称>` 或 MCP 的
/// `set_ai_allowed(false)` —— 即“默认放行 + 黑名单”。
class AiAccessPolicy {
  const AiAccessPolicy._();

  /// 新增账号时的默认值：是否允许 AI 取码。
  static const bool defaultAllow = TotpAccount.defaultAiAllowed;

  static bool allows(TotpAccount account) => account.aiAllowed;

  /// 不允许时返回给调用方的说明；允许时返回 null。
  static String? denialReason(TotpAccount account) {
    if (allows(account)) return null;
    return '账号「${account.displayTitle}」已被显式禁止 AI 取码（lzy-totp deny）。'
        '如确需放开：lzy-totp allow "${account.displayTitle}"';
  }
}
