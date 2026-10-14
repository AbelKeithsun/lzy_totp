import 'package:flutter/material.dart';

import '../services/ai_settings_service.dart';
import '../services/ai_vault_service.dart';
import '../utils/platform_utils.dart';
import 'ai_access_page.dart';

/// 设置页。目前只有一件事：AI / MCP 取码总开关。
///
/// 关于「开关」的语义（页面上也写清楚了）：MCP server 不是常驻服务，
/// 而是 MCP 客户端在需要时按需拉起的 stdio 进程；这里控制的是**取码权限的总闸**，
/// 关掉之后 CLI 读取与 MCP 的全部工具都会被拒绝，账号本身不受影响。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.aiSettings, this.aiVault});

  final AiSettingsService? aiSettings;
  final AiVaultService? aiVault;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AiSettingsService _settings =
      widget.aiSettings ?? AiSettingsService();
  late final AiVaultService _vault =
      widget.aiVault ?? AiVaultService(paths: _settings.paths);

  bool _loading = true;
  bool _error = false;
  bool _aiEnabled = true;
  int _vaultCount = 0;
  int _vaultBlocked = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppPlatform.isDesktop) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final enabled = await _settings.aiAccessEnabled();
      var count = 0;
      var blocked = 0;
      try {
        final accounts = await _vault.load();
        count = accounts.length;
        blocked = accounts.where((a) => !a.aiAllowed).length;
      } catch (_) {
        // vault 读不了不影响开关本身
      }
      if (!mounted) return;
      setState(() {
        _aiEnabled = enabled;
        _vaultCount = count;
        _vaultBlocked = blocked;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _aiEnabled = value);
    try {
      await _settings.setAiAccessEnabled(value);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(value
              ? '已允许 AI / MCP 取码'
              : '已关闭 AI / MCP 取码：CLI 与 MCP 会立刻被拒绝（账号不受影响）'),
          duration: const Duration(seconds: 4),
        ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiEnabled = !value); // 写失败就回滚显示
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('保存失败：$e'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ));
    }
  }

  void _openAiAccessPage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AiAccessPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('AI / MCP 服务',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (!AppPlatform.isDesktop)
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '当前平台不支持：AI 取码的 vault 位于桌面端用户目录，'
                        'Android 上外部 agent 读不到，因此这里不提供开关。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                else ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      value: _aiEnabled,
                      onChanged: _error ? null : _toggle,
                      secondary: Icon(
                        _aiEnabled
                            ? Icons.smart_toy_outlined
                            : Icons.smart_toy,
                        color: _aiEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                      title: const Text('允许 AI / MCP 取码'),
                      subtitle: Text(_aiEnabled
                          ? '开启中：CLI 与 MCP 可以按账号策略取码'
                          : '已关闭：CLI 读取与 MCP 全部工具都会被拒绝'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row(theme, '总开关', _aiEnabled ? '已开启' : '已关闭'),
                          _row(theme, 'vault 账号数',
                              '$_vaultCount（其中禁止取码 $_vaultBlocked）'),
                          _row(theme, '数据目录', _settings.paths.home),
                          if (_error) _row(theme, '状态', '读取设置失败，开关已禁用'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('这个开关控制什么',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(
                            '• MCP server 不是一个常驻服务：客户端（Claude Code / Cursor / DSH 等）'
                            '在需要时按需拉起 `lzy-totp mcp` 这个 stdio 进程。\n'
                            '• 所以这里控制的是**取码权限的总闸**：关闭后，CLI 的 '
                            'list / info / code 与 MCP 的 7 个工具一律被拒绝，'
                            '并在审计里记为 denied(global_disabled)。\n'
                            '• 关闭**不会**删除或隐藏任何账号——vault 与 App 数据都不动；'
                            '重新打开就恢复。\n'
                            '• 想彻底断开：把客户端里的 MCP 配置删掉即可，与本开关无关。\n'
                            '• 终端里也可以用 lzy-totp ai off 关闭；重新开启需要人工在终端确认，'
                            '防止被提示注入的 agent 自己把闸门打开。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _openAiAccessPage,
                    icon: const Icon(Icons.smart_toy_outlined, size: 18),
                    label: const Text('查看 AI 接入说明'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: Text(value, style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      );
}
