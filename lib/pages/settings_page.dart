import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_settings_service.dart';
import '../services/ai_vault_service.dart';
import '../services/mcp_service.dart';
import '../utils/platform_utils.dart';
import 'ai_access_page.dart';

/// 设置页：MCP 服务的启停 + 取码总开关。
///
/// 两个开关的分工（页面上也写清楚了）：
/// - **MCP 服务**：在 App 里直接启停一个只监听本机的 MCP 服务（HTTP/Streamable HTTP）。
///   开着才有地址可粘贴给 agent；关掉服务立即停止，agent 立刻连不上。
/// - **允许 AI / MCP 取码**：取码权限总闸。即使服务开着，这里关掉也会拒绝取码。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.aiSettings,
    this.aiVault,
    this.mcpService,
  });

  final AiSettingsService? aiSettings;
  final AiVaultService? aiVault;
  final McpService? mcpService;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AiSettingsService _settings =
      widget.aiSettings ?? AiSettingsService();
  late final AiVaultService _vault =
      widget.aiVault ?? AiVaultService(paths: _settings.paths);
  late final McpService _mcp = widget.mcpService ??
      McpService(settings: _settings);

  bool _loading = true;
  bool _error = false;
  bool _busy = false;
  bool _aiEnabled = true;
  bool _mcpEnabled = false;
  String? _mcpError;
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
      final current = await _settings.load();
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
        _aiEnabled = current.aiAccessEnabled;
        _mcpEnabled = current.mcpHttpEnabled;
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

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor:
            error ? Theme.of(context).colorScheme.errorContainer : null,
      ));
  }

  Future<void> _toggleAi(bool value) async {
    setState(() => _aiEnabled = value);
    try {
      await _settings.setAiAccessEnabled(value);
      if (!mounted) return;
      _toast(value
          ? '已允许 AI / MCP 取码'
          : '已关闭 AI / MCP 取码：CLI 与 MCP 会立刻被拒绝（账号不受影响）');
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiEnabled = !value); // 写失败就回滚显示
      _toast('保存失败：$e', error: true);
    }
  }

  Future<void> _toggleMcp(bool value) async {
    setState(() {
      _busy = true;
      _mcpError = null;
    });
    try {
      await _mcp.setEnabled(value);
      if (!mounted) return;
      setState(() {
        _mcpEnabled = value;
        _busy = false;
      });
      _toast(value
          ? 'MCP 服务已启动：${_mcp.status.url}'
          : 'MCP 服务已停止：已粘贴的客户端配置会连不上');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mcpEnabled = false;
        _mcpError = '$e';
        _busy = false;
      });
      _toast('启动 MCP 服务失败：$e', error: true);
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('$what 已复制');
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
          : !AppPlatform.isDesktop
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '当前平台不支持：MCP 服务与 AI vault 都在桌面端用户目录下，'
                          'Android 上外部 agent 读不到，因此这里不提供开关。',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('MCP 服务（本机 HTTP）',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _mcpCard(theme),
                    const SizedBox(height: 16),
                    Text('取码权限',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: _aiEnabled,
                        onChanged: _error ? null : _toggleAi,
                        secondary: Icon(
                          _aiEnabled ? Icons.smart_toy_outlined : Icons.smart_toy,
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
                            _row(theme, '服务地址',
                                _mcp.status.url.isEmpty ? '（未启动）' : _mcp.status.url),
                            _row(theme, '取码权限', _aiEnabled ? '允许' : '已关闭'),
                            _row(theme, 'vault 账号数',
                                '$_vaultCount（其中禁止取码 $_vaultBlocked）'),
                            _row(theme, '数据目录', _settings.paths.home),
                            if (_error) _row(theme, '状态', '读取设置失败，开关已禁用'),
                            if (_mcpError != null)
                              _row(theme, '服务错误', _mcpError!),
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
                ),
    );
  }

  Widget _mcpCard(ThemeData theme) {
    final running = _mcp.isRunning;
    final snippets = _mcp.snippets;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _mcpEnabled,
              onChanged: _busy ? null : _toggleMcp,
              secondary: Icon(
                running ? Icons.cloud_done : Icons.cloud_off,
                color: running
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: const Text('启动 MCP 服务'),
              subtitle: Text(running
                  ? '运行中，agent 可以用下面地址接入'
                  : '已停止：agent 无法连接（不影响 App 正常使用）'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (running) ...[
              const Divider(height: 20),
              Text('把地址粘贴到 agent 即可接入：',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _snippet(theme, 'Claude Code', snippets.claudeCode),
              _snippet(theme, '通用 JSON（Cursor 等）', snippets.jsonConfig),
              _snippet(theme, 'DSH（cordis.patch.yml）', snippets.dshYaml),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () =>
                          _copy(snippets.summary, '全部接入说明'),
                      icon: const Icon(Icons.copy_all, size: 16),
                      label: const Text('复制全部'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• 地址里的随机 token 就是凭据：只监听本机回环，'
                '不携带 token 或带浏览器 Origin 的请求一律拒绝。\n'
                '• 关掉上面的开关 = 服务停止，已粘贴的配置立刻连不上；'
                '在 agent 里删掉该 MCP 配置即彻底移除接入。\n'
                '• 也可以不用 App，直接跑 `lzy-totp serve` 得到同样的地址。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '• MCP 客户端通常自己拉起 stdio 进程（`lzy-totp mcp`），那种方式不需要这个服务。\n'
                  '• 打开这个开关后，App 会在本机 127.0.0.1 上常驻一个 MCP 服务，'
                  '把生成的地址粘贴进客户端即可接入，无需安装别的程序。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _snippet(ThemeData theme, String label, String code) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制「$label」',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(code, label),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      );

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
