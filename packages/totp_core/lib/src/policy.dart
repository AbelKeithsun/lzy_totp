import 'account.dart';

/// AI / 自动化工具访问策略。
///
/// 默认**拒绝**：只有账户上显式设置了 `aiAllowed = true`（通过
/// `lzy_totp allow <名称>` 或 MCP 的 `set_ai_allowed`）才可取码。
class AiAccessPolicy {
  const AiAccessPolicy._();

  /// 全vault 级别的兜底开关：仅用于测试，生产环境保持 false。
  static const bool defaultAllow = false;

  static bool allows(TotpAccount account, {bool defaultAllowOverride = defaultAllow}) =>
      defaultAllowOverride || account.aiAllowed;

  /// 不允许时返回给调用方的说明；允许时返回 null。
  static String? denialReason(TotpAccount account) {
    if (allows(account)) return null;
    return '账号「${account.displayTitle}」未标记为允许 AI 访问（默认拒绝）。'
        '如确需让 AI 查询，请先人工确认并执行：lzy_totp allow "${account.displayTitle}"';
  }
}
