import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/account.dart';

/// 恢复码（备用码）面板。
///
/// 恢复码是「绕过 TOTP 直接登录」的钥匙，敏感度不低于密钥：
/// - 点一下复制（不主动展示明文列表前先给个提示）——这里默认直接列出，方便人工抄写；
/// - 可以「标记已用」：网站用掉一个就作废一个，划掉后不再重复使用；
/// - 可以删除：录错了、或想整体作废。
class RecoveryCodesSheet extends StatefulWidget {
  const RecoveryCodesSheet({
    super.key,
    required this.account,
    required this.onChanged,
  });

  final TotpAccount account;

  /// 恢复码变化后回调（调用方负责落库）
  final Future<void> Function(TotpAccount updated) onChanged;

  @override
  State<RecoveryCodesSheet> createState() => _RecoveryCodesSheetState();
}

class _RecoveryCodesSheetState extends State<RecoveryCodesSheet> {
  late TotpAccount _account;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
  }

  Future<void> _apply(TotpAccount updated) async {
    setState(() => _account = updated);
    await widget.onChanged(updated);
  }

  void _copy(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('恢复码已复制'),
        duration: Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unused = _account.recoveryCodes;
    final used = _account.usedRecoveryCodes;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('恢复码 · ${_account.displayTitle}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              unused.isEmpty && used.isEmpty
                  ? '这个账号还没录恢复码。可在「编辑账户」里补录。'
                  : '还有 ${unused.length} 个可用${used.isEmpty ? '' : '，${used.length} 个已用'}。'
                      '恢复码能绕过验证码登录，请勿分享。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (unused.isEmpty && used.isEmpty)
              const SizedBox(height: 8)
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final code in unused)
                      _codeTile(code, theme, used: false),
                    if (used.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text('已用掉',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ),
                      for (final code in used)
                        _codeTile(code, theme, used: true),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeTile(String code, ThemeData theme, {required bool used}) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        code,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontFamily: 'monospace',
          letterSpacing: 1,
          decoration: used ? TextDecoration.lineThrough : null,
          color: used ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: '复制恢复码',
        visualDensity: VisualDensity.compact,
        onPressed: () => _copy(code),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: '更多操作',
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) async {
          if (action == 'used') {
            await _apply(_account.markRecoveryCodeUsed(code));
          } else if (action == 'delete') {
            await _apply(_account.removeRecoveryCode(code));
          }
        },
        itemBuilder: (_) => [
          if (!used)
            const PopupMenuItem(
              value: 'used',
              child: Row(
                children: [
                  Icon(Icons.task_alt, size: 18),
                  SizedBox(width: 12),
                  Text('标记已用'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18),
                SizedBox(width: 12),
                Text('删除'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
