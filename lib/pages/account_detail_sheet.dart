import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/ai_vault_service.dart';

/// 账户详情面板：把「不参与取码、但需要看清楚」的信息集中展示。
///
/// 只读——要改请走「编辑账户」。重点是把类型与时间三类字段亮出来：
/// 类型（TOTP / HOTP + 计数器）、创建时间、最近取码时间、失效日期。
class AccountDetailSheet extends StatelessWidget {
  const AccountDetailSheet({
    super.key,
    required this.account,
    this.aiState,
  });

  final TotpAccount account;

  /// 该账号在 AI vault 里的状态；null = 当前平台不启用同步
  final VaultSyncState? aiState;

  String _date(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  String get _typeLabel =>
      account.isHotp ? 'HOTP（按计数器，用一次 +1）' : 'TOTP（按时间）';

  String get _params =>
      account.isHotp
          ? '${account.digits} 位 / 计数器 ${account.counter} / ${account.algorithm}'
          : '${account.digits} 位 / ${account.period} 秒 / ${account.algorithm}';

  String get _aiLabel {
    return switch (aiState) {
      null => '未启用（当前平台不支持同步）',
      VaultSyncState.notSynced => '未同步给 AI',
      VaultSyncState.syncedAllowed => '已同步，AI 可读取验证码',
      VaultSyncState.syncedBlocked => '已同步，但被 lzy-totp deny 禁止取码',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expired = account.isExpired;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('账户详情', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(account.displayTitle,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _row(context, '发行方', account.issuer.isEmpty ? '（未填）' : account.issuer),
                  _row(context, '账户名', account.label.isEmpty ? '（未填）' : account.label),
                  _row(context, '备注', account.note.isEmpty ? '（无）' : account.note),
                  _row(context, '类型', _typeLabel),
                  _row(context, '参数', _params),
                  _row(context, '创建时间', _date(account.createdAtTime)),
                  _row(context, '最近取码', _date(account.lastUsedAtTime)),
                  _row(
                    context,
                    '失效日期',
                    account.expiresAtTime == null
                        ? '未设置'
                        : _date(account.expiresAtTime),
                    warning: expired,
                  ),
                  _row(
                    context,
                    '恢复码',
                    account.hasRecoveryCodes
                        ? '${account.recoveryCodeCount} 个可用'
                            '${account.usedRecoveryCodes.isEmpty ? '' : '，${account.usedRecoveryCodes.length} 个已用'}'
                        : '未录入',
                  ),
                  _row(context, 'AI 取码', _aiLabel),
                  if (expired) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '已过有效期：这个密钥可能已被网站轮换，建议确认后重新录入。',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
          {bool warning = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: warning ? Theme.of(context).colorScheme.error : null,
                    ),
              ),
            ),
          ],
        ),
      );
}
