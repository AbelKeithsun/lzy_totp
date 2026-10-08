import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';
import '../services/storage_service.dart';
import '../services/totp_service.dart';
import '../utils/platform_utils.dart';
import 'add_account_page.dart';
import 'scan_page.dart';

/// 首页：账户列表 + 实时刷新的验证码
class AccountListPage extends StatefulWidget {
  const AccountListPage({super.key, required this.storage});

  final StorageService storage;

  @override
  State<AccountListPage> createState() => _AccountListPageState();
}

class _AccountListPageState extends State<AccountListPage> {
  List<TotpAccount> _accounts = [];
  Timer? _timer;

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
    if (mounted) setState(() => _accounts = accounts);
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

  Future<void> _deleteAccount(TotpAccount account) async {
    setState(() => _accounts.removeWhere((a) => a.id == account.id));
    await _persist();
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
      appBar: AppBar(title: const Text('TOTP 验证器')),
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
                  onDelete: () => _deleteAccount(account),
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

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    super.key,
    required this.account,
    required this.onCopy,
    required this.onDelete,
  });

  final TotpAccount account;
  final ValueChanged<String> onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final code = TotpService.codeFor(account);
    final remaining = TotpService.remainingSeconds(period: account.period);
    final progress = TotpService.progress(period: account.period);
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
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除账户'),
          content: Text('确定删除「${account.displayTitle}」吗？删除后无法恢复。'),
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
      ),
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: () => onCopy(code),
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
            // 桌面端提供显式复制按钮（移动端点击整行即可复制）
            if (AppPlatform.isDesktop)
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制验证码',
                onPressed: () => onCopy(code),
              ),
            Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: remaining <= 5 ? theme.colorScheme.error : null,
                ),
                Text('$remaining', style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
