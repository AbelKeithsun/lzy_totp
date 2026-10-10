import 'package:totp_core/totp_core.dart';

/// App 里的账号相对 AI vault 的同步状态
enum VaultSyncState {
  /// 不在 vault 里 —— AI 看不到这个账号
  notSynced,

  /// 已在 vault 里，且允许 AI 取码
  syncedAllowed,

  /// 已在 vault 里，但被 `lzy-totp deny` 显式禁止取码
  syncedBlocked,
}

/// App 账号 ↔ AI vault（`~/.config/lzy_totp`）之间的桥。
///
/// App 的账号存在系统钥匙串（Android Keystore / macOS Keychain），
/// AI 侧的 CLI / MCP 只读这个加密 vault。本服务把 App 里**已经录入**的账号
/// 写进 vault，使 AI agent 可以直接取码——即「点一下同步给 AI」。
///
/// 设计要点：
/// - 单向、可撤销：同步只是把账号写进 vault，App 内的数据不动；取消同步也不会删 App 数据。
/// - **不覆盖 deny**：vault 里若已有同一账号且被 `lzy-totp deny` 禁止，同步不会把
///   `aiAllowed` 改回 true，避免误点一下就放开了敏感账号。
/// - 只写码不写日志内容以外的信息：vault 里仍以 AES-256-GCM 加密存储密钥。
class AiVaultService {
  AiVaultService({TotpPaths? paths, VaultStore? vault})
      : paths = paths ?? TotpPaths.resolve(),
        _vaultOverride = vault;

  /// vault / 密钥 / 审计所在目录
  final TotpPaths paths;

  final VaultStore? _vaultOverride;

  /// 延迟创建，避免在不需要 vault 的平台（如 Android 上没打开此功能时）做任何磁盘动作
  late final VaultStore _lazyVault = VaultStore(paths: paths);

  VaultStore get vault => _vaultOverride ?? _lazyVault;

  /// vault 文件路径，用于界面提示
  String get vaultFile => paths.vaultFile;

  /// 读取 vault 现有账号（vault 不存在时返回空列表）
  Future<List<TotpAccount>> load() => vault.load();

  /// 按密钥匹配；密钥不同但显示名相同时视为同一个账号（避免 vault 里出现重名条目）
  int _indexOf(List<TotpAccount> accounts, TotpAccount account) {
    final bySecret = accounts.indexWhere((a) => a.secret == account.secret);
    if (bySecret >= 0) return bySecret;
    final title = account.displayTitle;
    if (title.isEmpty) return -1;
    return accounts.indexWhere((a) => a.displayTitle == title);
  }

  /// 把 App 账号写进 vault。
  ///
  /// 返回 true 表示 vault 里新建了条目，false 表示更新了已有条目。
  Future<bool> sync(TotpAccount account) async {
    var created = false;
    await vault.update((accounts) async {
      final index = _indexOf(accounts, account);
      if (index >= 0) {
        final existing = accounts[index];
        accounts[index] = TotpAccount(
          // 保留 vault 侧的 id 与 aiAllowed：CLI 的 deny 不该被 App 同步覆盖
          id: existing.id,
          issuer: account.issuer,
          label: account.label,
          secret: account.secret,
          digits: account.digits,
          period: account.period,
          algorithm: account.algorithm,
          aiAllowed: existing.aiAllowed,
        );
      } else {
        created = true;
        accounts.add(TotpAccount(
          id: account.id,
          issuer: account.issuer,
          label: account.label,
          secret: account.secret,
          digits: account.digits,
          period: account.period,
          algorithm: account.algorithm,
          // 同步的意图就是「让 AI 能取码」
          aiAllowed: true,
        ));
      }
      return null;
    });
    await _audit(created ? 'add_account' : 'update_account', account,
        note: 'source=app');
    return created;
  }

  /// 从 vault 移除（App 内仍保留该账号）。
  Future<bool> unlink(TotpAccount account) async {
    var removed = false;
    await vault.update((accounts) async {
      final before = accounts.length;
      accounts.removeWhere(
          (a) => a.secret == account.secret || a.id == account.id);
      removed = accounts.length != before;
      return null;
    });
    if (removed) {
      await _audit('remove_account', account, note: 'source=app');
    }
    return removed;
  }

  /// 计算某个 App 账号在给定 vault 快照里的同步状态
  VaultSyncState stateOf(TotpAccount account, List<TotpAccount> vaultAccounts) {
    final index = _indexOf(vaultAccounts, account);
    if (index < 0) return VaultSyncState.notSynced;
    return vaultAccounts[index].aiAllowed
        ? VaultSyncState.syncedAllowed
        : VaultSyncState.syncedBlocked;
  }

  /// 审计：记录是 App 侧发起的变化（actor=app），失败不影响同步结果
  Future<void> _audit(String action, TotpAccount account,
      {String? note, String result = 'ok'}) async {
    try {
      await AuditLog(paths.auditFile).append(AuditEntry(
        action: action,
        account: account.displayTitle,
        result: result,
        actor: 'app',
        note: note,
      ));
    } catch (_) {
      // 审计写不进去（如目录不可写）不应阻断同步
    }
  }
}
