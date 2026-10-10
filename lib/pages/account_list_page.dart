import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';
import '../services/ai_vault_service.dart';
import '../services/storage_service.dart';
import '../services/totp_service.dart';
import '../utils/platform_utils.dart';
import 'add_account_page.dart';
import 'ai_access_page.dart';
import 'scan_page.dart';

/// 首页：账户列表 + 实时刷新的验证码
class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key, required this.storage, this.aiVault});

  final StorageService storage;

  /// AI vault 桥（默认连 ~/.config/lzy_totp）；测试可注入替身
  final AiVaultService? aiVault;

  @override
  State<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<AccountListPage> {
  List<TotpAccount> _accounts = [];
  Timer? _timer;

  /// vault 里的账号快照，用来显示每行的「同步给 AI」状态
  List<TotpAccount> _vaultAccounts = [];

  late final AiVaultService _aiVault =
      widget.aiVault ?? AiVaultService();

  /// 是否启用 App→vault 同步：只在桌面端（AI agent 跑在同一台机器上）有意义，
  /// Android 上 ~/.config/lzy_totp 位于沙盒内，外部 agent 读不到。
  bool get _aiSyncEnabled => AppPlatform.isDesktop;

  @override
  void initState() {
    super.initState();
    _load();
    // 每秒刷新一次验证码和倒计时
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await widget.storage.load();
    var vaultAccounts = <TotpAccount>[];
    if (_aiSyncEnabled) {
      try {
        vaultAccounts = await _aiVault.load();
      } catch (_) {
        // vault 不可读（密钥丢失、权限等）时不阻塞列表，同步时会提示具体错误
        vaultAccounts = [];
      }
    }
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _vaultAccounts = vaultAccounts;
      });
    }
  }

  /// 重新读取 vault 快照（同步 / 取消同步后刷新每行状态）
  Future<void> _reloadVault() async {
    if (!_aiSyncEnabled) return;
    try {
      final latest = await _aiVault.load();
      if (mounted) setState(() => _vaultAccounts = latest);
    } catch (_) {
      if (mounted) setState(() => _vaultAccounts = []);
    }
  }

  Future<void> _persist() => widget.storage.save(_accounts);

  Future<void> _addAccount() async {
    // 桌面端（macOS 等）不支持扫码，直接进入手动粘贴密钥页
    final String? choice;
    if (AppPlatform.supportsScan) {
      choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('扫码添加'),
                onTap: () => Navigator.pop(ctx, 'scan'),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard),
                title: const Text('手动输入密钥'),
                onTap: () => Navigator.pop(ctx, 'manual'),
              ),
            ],
          ),
        ),
      );
    } else {
      choice = 'manual';
    }
    if (choice == null || !mounted) return;

    final TotpAccount? account = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => choice == 'scan'
            ? const ScanPage()
            : const AddAccountPage(),
      ),
    );
    if (account != null) {
      setState(() => _accounts.add(account));
      await _persist();
    }
  }

  /// 删除前的二次确认（左滑与菜单删除共用同一段文案）
  Future<bool> _confirmDelete(TotpAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text('确定删除「${account.displayTitle}」吗？删除后可用底部提示的「撤销」恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 真正落库删除，并提供「撤销」
  Future<void> _removeAccount(TotpAccount account) async {
    final index = _accounts.indexWhere((a) => a.id == account.id);
    if (index < 0) return;
    setState(() => _accounts.removeAt(index));
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('已删除「${account.displayTitle}」'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _restoreAccount(account, index),
        ),
      ));
  }

  Future<void> _restoreAccount(TotpAccount account, int index) async {
    if (_accounts.any((a) => a.id == account.id)) return;
    setState(() => _accounts.insert(index.clamp(0, _accounts.length), account));
    await _persist();
  }

  /// 点一下：把 App 里已录入的账号写进 AI vault（或按状态给出说明）
  Future<void> _toggleAiSync(TotpAccount account) async {
    final state = _aiVault.stateOf(account, _vaultAccounts);
    switch (state) {
      case VaultSyncState.notSynced:
        await _syncToVault(account);
      case VaultSyncState.syncedAllowed:
        await _unlinkFromVault(account);
      case VaultSyncState.syncedBlocked:
        _showDeniedHint(account);
    }
  }

  Future<void> _syncToVault(TotpAccount account) async {
    try {
      final created = await _aiVault.sync(account);
      await _reloadVault();
      if (!mounted) return;
      _snack(
        created
            ? '已同步给 AI：${account.displayTitle}，AI 现在可以取码'
            : '已更新 vault 里的 ${account.displayTitle}',
        // 只有新建才能撤销；覆盖已有条目的事后撤回会丢掉原有信息
        undo: created ? () => _unlinkFromVault(account) : null,
      );
    } catch (e) {
      _snackError('同步失败：${_describe(e)}');
    }
  }

  Future<void> _unlinkFromVault(TotpAccount account) async {
    try {
      final removed = await _aiVault.unlink(account);
      await _reloadVault();
      if (!mounted) return;
      _snack(
        removed
            ? '已取消 AI 读取：${account.displayTitle}（App 内仍保留）'
            : 'vault 里没有这个账号',
        undo: removed ? () => _syncToVault(account) : null,
      );
    } catch (e) {
      _snackError('取消同步失败：${_describe(e)}');
    }
  }

  /// 已在 vault 但被 CLI 的 deny 挡住：说明原因，并提供「从 vault 移除」
  void _showDeniedHint(TotpAccount account) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('「${account.displayTitle}」已被 lzy-totp deny 禁止 AI 取码；'
            '如需放开请执行 lzy-totp allow'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '从 vault 移除',
          onPressed: () => _unlinkFromVault(account),
        ),
      ));
  }

  String _describe(Object e) {
    final text = e.toString();
    return text.startsWith('VaultError: ') ? text.substring(12) : text;
  }

  void _snack(String message, {VoidCallback? undo}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: undo == null
            ? null
            : SnackBarAction(label: '撤销', onPressed: undo),
      ));
  }

  void _snackError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        backgroundColor: Theme.of(context).colorScheme.errorContainer,
      ));
  }

  void _openAiAccess() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiAccessPage()),
    );
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('验证码已复制'),
        duration: Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TOTP 验证器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'AI 接入说明',
            onPressed: _openAiAccess,
          ),
        ],
      ),
      body: _accounts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 72, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    AppPlatform.supportsScan
                        ? '还没有账户\n点击右下角 + 扫码或手动添加'
                        : '还没有账户\n点击右下角 + 粘贴密钥添加',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _openAiAccess,
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: const Text('AI 接入说明'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _accounts.length,
              itemBuilder: (context, index) {
                final account = _accounts[index];
                return _AccountTile(
                  key: ValueKey(account.id),
                  account: account,
                  onCopy: _copy,
                  // 左滑：先确认，再落库删除
                  onConfirmDelete: () => _confirmDelete(account),
                  onDelete: () => _removeAccount(account),
                  aiState: _aiSyncEnabled
                      ? _aiVault.stateOf(account, _vaultAccounts)
                      : null,
                  onAiTap: () => _toggleAiSync(account),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAccount,
        tooltip: '添加账户',
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// 列表项菜单里的操作
enum _RowAction { copy, aiSync, delete }

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.onCopy,
    required this.onConfirmDelete,
    required this.onDelete,
    required this.onAiTap,
    this.aiState,
  });

  final TotpAccount account;
  final ValueChanged<String> onCopy;

  /// 弹出删除确认框；返回是否确认删除
  final Future<bool> Function() onConfirmDelete;

  /// 已确认后真正删除
  final VoidCallback onDelete;

  /// 点一下同步给 AI / 取消同步（null 表示当前平台不提供该功能）
  final VoidCallback onAiTap;

  /// 该账号在 AI vault 里的状态；null = 当前平台不启用同步
  final VaultSyncState? aiState;

  bool get _aiEnabled => aiState != null;

  /// 同步按钮的图标与提示语
  IconData get _aiIcon => switch (aiState) {
        VaultSyncState.syncedAllowed => Icons.cloud_done,
        VaultSyncState.syncedBlocked => Icons.cloud_off,
        _ => Icons.cloud_upload_outlined,
      };

  String get _aiTooltip => switch (aiState) {
        VaultSyncState.syncedAllowed => 'AI 可读取验证码，点按取消同步',
        VaultSyncState.syncedBlocked => '已同步，但被 lzy-totp deny 禁止取码',
        _ => '同步给 AI（写入 ~/.config/lzy_totp）',
      };

  String get _aiMenuLabel => switch (aiState) {
        VaultSyncState.notSynced => '同步给 AI',
        _ => '取消 AI 读取',
      };

  IconData get _aiMenuIcon => switch (aiState) {
        VaultSyncState.notSynced => Icons.cloud_upload_outlined,
        _ => Icons.cloud_off,
      };

  Future<void> _requestDelete() async {
    if (await onConfirmDelete()) onDelete();
  }

  void _handleAction(_RowAction action, String code) {
    switch (action) {
      case _RowAction.copy:
        onCopy(code);
      case _RowAction.aiSync:
        onAiTap();
      case _RowAction.delete:
        _requestDelete();
    }
  }

  /// 移动端长按：弹出操作面板（桌面端用行尾 ⋮ 菜单）
  Future<void> _showActionsSheet(BuildContext context, String code) async {
    final action = await showModalBottomSheet<_RowAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制验证码'),
              onTap: () => Navigator.pop(ctx, _RowAction.copy),
            ),
            if (_aiEnabled)
              ListTile(
                leading: Icon(_aiMenuIcon),
                title: Text(_aiMenuLabel),
                onTap: () => Navigator.pop(ctx, _RowAction.aiSync),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除账户'),
              onTap: () => Navigator.pop(ctx, _RowAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action != null) _handleAction(action, code);
  }

  @override
  Widget build(BuildContext context) {
    final code = TotpService.codeFor(account);
    final remaining = TotpService.remainingSeconds(period: account.period);
    // 圆环显示「剩余比例」：周期开始时是满环，随倒计时逐渐排空。
    // 注意 TotpService.progress() 是「已过去比例」，直接用会让圆环在周期起点为空。
    final ringValue = remaining / account.period;
    final theme = Theme.of(context);

    // 6 位验证码中间加空格，便于阅读
    final grouped = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code;

    return Dismissible(
      key: ValueKey('dismiss_${account.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => onConfirmDelete(),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: () => onCopy(code),
        onLongPress: () => _showActionsSheet(context, code),
        title: Text(account.displayTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          grouped,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 点一下就同步给 AI（桌面端；状态用图标区分）
            if (_aiEnabled)
              IconButton(
                icon: Icon(
                  _aiIcon,
                  size: 18,
                  color: aiState == VaultSyncState.syncedAllowed
                      ? theme.colorScheme.primary
                      : null,
                ),
                tooltip: _aiTooltip,
                visualDensity: VisualDensity.compact,
                onPressed: onAiTap,
              ),
            // 桌面端提供显式复制按钮（移动端点击整行即可复制）
            if (AppPlatform.isDesktop)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制验证码',
                visualDensity: VisualDensity.compact,
                onPressed: () => onCopy(code),
              ),
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: ringValue,
                    strokeWidth: 3,
                    color: remaining <= 5 ? theme.colorScheme.error : null,
                  ),
                  Text('$remaining', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            // 显式删除入口：桌面端无法左滑，菜单与长按都可删除
            PopupMenuButton<_RowAction>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (action) => _handleAction(action, code),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: _RowAction.copy,
                  child: Row(
                    children: [
                      Icon(Icons.copy, size: 18),
                      SizedBox(width: 12),
                      Text('复制验证码'),
                    ],
                  ),
                ),
                if (_aiEnabled)
                  PopupMenuItem(
                    value: _RowAction.aiSync,
                    child: Row(
                      children: [
                        Icon(_aiMenuIcon, size: 18),
                        const SizedBox(width: 12),
                        Text(_aiMenuLabel),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: _RowAction.delete,
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18),
                      SizedBox(width: 12),
                      Text('删除账户'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
