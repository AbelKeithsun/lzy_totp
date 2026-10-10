import 'package:lzy_totp/services/ai_vault_service.dart';
import 'package:totp_core/totp_core.dart';

/// 内存版 AI vault：跳过真实 `~/.config/lzy_totp`，仅供 widget 测试使用。
///
/// `stateOf` 沿用真实实现（纯逻辑），所以状态显示与线上一致。
class FakeAiVaultService extends AiVaultService {
  FakeAiVaultService([List<TotpAccount>? initial])
      : _accounts = [...?initial],
        // 只为构造对象，不落盘（所有方法都被覆写）
        super(paths: TotpPaths('/tmp/lzy_totp_fake_vault'));

  final List<TotpAccount> _accounts;

  /// 设为非 null 时，所有方法都抛出该异常，用于验证界面错误提示
  Object? failWith;

  List<TotpAccount> get accounts => List.unmodifiable(_accounts);

  int syncCount = 0;
  int unlinkCount = 0;

  @override
  Future<List<TotpAccount>> load() async {
    if (failWith != null) throw failWith!;
    return List.of(_accounts);
  }

  @override
  Future<bool> sync(TotpAccount account) async {
    syncCount++;
    if (failWith != null) throw failWith!;
    final index = _accounts.indexWhere((a) =>
        a.secret == account.secret || a.displayTitle == account.displayTitle);
    if (index >= 0) {
      final existing = _accounts[index];
      _accounts[index] = TotpAccount(
        id: existing.id,
        issuer: account.issuer,
        label: account.label,
        secret: account.secret,
        digits: account.digits,
        period: account.period,
        algorithm: account.algorithm,
        aiAllowed: existing.aiAllowed,
      );
      return false;
    }
    _accounts.add(account.copyWith(aiAllowed: true));
    return true;
  }

  @override
  Future<bool> unlink(TotpAccount account) async {
    unlinkCount++;
    if (failWith != null) throw failWith!;
    final before = _accounts.length;
    _accounts.removeWhere(
        (a) => a.secret == account.secret || a.id == account.id);
    return _accounts.length != before;
  }
}
