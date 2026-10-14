import 'account.dart';
import 'settings.dart';

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

  /// 总开关（App 的「AI / MCP 服务」开关）判定：关闭时返回拒绝理由，开启时返回 null。
  ///
  /// 与单账号策略分开：总开关是「一刀切」的闸门，优先于账号级的 aiAllowed。
  static String? globalSwitchDenial(TotpSettings settings) {
    if (settings.aiAccessEnabled) return null;
    return 'AI / MCP 取码总开关已关闭（在 App 的「设置 → AI / MCP 服务」里打开；'
        '或在终端执行 lzy-totp ai on 并确认）。';
  }

  /// 单账号策略：不允许时返回给调用方的说明；允许时返回 null。
  static String? denialReason(TotpAccount account) {
    if (allows(account)) return null;
    return '账号「${account.displayTitle}」已被显式禁止 AI 取码（lzy-totp deny）。'
        '如确需放开：lzy-totp allow "${account.displayTitle}"';
  }
}
