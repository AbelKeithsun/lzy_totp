import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 「AI 接入」说明页。
///
/// 面向上手用户介绍：AI agent（Claude Code / Cursor / DSH 等）如何通过
/// CLI 或 MCP 查询本机验证码，以及默认放行 + 黑名单的安全边界。
/// 内容与 docs/ai-access.md 保持一致。
class AiAccessPage extends StatelessWidget {
  const AiAccessPage({super.key});

  /// 编译安装命令（文档同步：docs/ai-access.md「安装」）
  static const String installSnippet = '''
cd tools/totp_cli && dart pub get
dart compile exe bin/lzy_totp.dart -o ~/.local/bin/lzy-totp''';

  /// MCP 客户端配置（把 <你的用户名> 换成真实用户名）
  static const String mcpConfigSnippet = '''{
  "mcpServers": {
    "lzy_totp": {
      "command": "/Users/<你的用户名>/.local/bin/lzy-totp",
      "args": ["mcp"]
    }
  }
}''';

  /// 录入 / 取码 / 黑名单
  static const String cliSnippet = '''# 录入账号（默认即允许 AI 取码）
lzy-totp add github --secret JBSWY3DPEHPK3PXP --issuer GitHub

# 敏感账号：显式禁止 AI 取码
lzy-totp add bank --secret JBSWY3DPEHPK3PXP --issuer Bank --block-ai

# 取码（AI agent 走的也是这条）
lzy-totp code github --json

# 复查：谁被放行、谁取过码
lzy-totp list
lzy-totp audit --tail 20''';

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('AI 接入')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _Intro(theme: theme),
          const SizedBox(height: 16),
          _StepCard(
            index: 1,
            title: '编译命令行工具',
            subtitle: 'CLI 与 MCP server 同一个可执行文件，装一次即可。',
            code: installSnippet,
            onCopy: (code) => _copy(context, code, '安装命令已复制'),
          ),
          _StepCard(
            index: 2,
            title: '录入账号',
            subtitle: '账号存进独立加密 vault；默认即允许 AI 取码，敏感账号加 --block-ai。',
            code: cliSnippet,
            onCopy: (code) => _copy(context, code, 'CLI 命令已复制'),
          ),
          _StepCard(
            index: 3,
            title: '配置 MCP 客户端',
            subtitle: '把下面这段 JSON 加进客户端的 MCP 配置，重启后即可用 '
                'list_accounts / generate_totp 等工具。',
            code: mcpConfigSnippet,
            onCopy: (code) => _copy(context, code, 'MCP 配置已复制'),
          ),
          const SizedBox(height: 8),
          _ToolTable(theme: theme),
          const SizedBox(height: 16),
          _SecurityCard(theme: theme),
          const SizedBox(height: 16),
          _DocFooter(theme: theme),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    _toast(context, message);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.smart_toy_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '让 AI agent 帮你取验证码',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'lzy_totp 除了给人用的 App，还提供一个给 AI agent 调用的取码接口——'
          '同一个加密 vault，两种外壳：',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        _Bullet(
          title: 'MCP server（推荐）',
          body: 'lzy-totp mcp —— Claude Code、Cursor、DSH 等 MCP 客户端原生接入，'
              'agent 直接看到 7 个工具。',
        ),
        _Bullet(
          title: '命令行 CLI',
          body: 'lzy-totp code github --json —— 任何能执行 shell 的 agent 都能用。',
        ),
        const SizedBox(height: 12),
        Text(
          '两者共用同一份 TOTP 实现、同一个 vault、同一套访问策略；'
          '接口只返回一次性验证码，永不返回密钥。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '$title：',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一步接入：标题 + 说明 + 可复制的代码块
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.code,
    required this.onCopy,
  });

  final int index;
  final String title;
  final String subtitle;
  final String code;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            CodeBlock(code: code, onCopy: () => onCopy(code)),
          ],
        ),
      ),
    );
  }
}

/// 等宽代码块 + 复制按钮
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.code, this.onCopy});

  final String code;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            tooltip: '复制',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

class _ToolTable extends StatelessWidget {
  const _ToolTable({required this.theme});

  final ThemeData theme;

  static const List<List<String>> rows = [
    ['list_accounts', '列出账号与 ai_allowed 标记（不含密钥）'],
    ['get_account_info', '单个账号元数据（不含密钥）'],
    ['generate_totp', '取当前验证码'],
    ['add_account', '录入账号（block_ai=true 可禁止 AI）'],
    ['add_from_uri', '从 otpauth:// URI 录入'],
    ['remove_account', '删除账号'],
    ['set_ai_allowed', '允许 / 禁止个别账号'],
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MCP 工具清单（7 个）',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(
                        row[0],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(row[1], style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  '安全边界（务必了解）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• 当前策略是「默认放行 + 黑名单」：账号一旦进入 vault，AI 就能取码，'
              '等于把它的第二因子交给了 AI。\n'
              '• 银行、主邮箱、云账号根凭据这类账号，请用 lzy-totp deny 排除，'
              '或干脆不要放进 vault。\n'
              '• 提示注入是主要风险：agent 上下文里混入恶意内容，可能诱导它去取码。\n'
              '• 每次取码（成功与被拒绝）都写入审计日志，定期用 lzy-totp audit 复查。\n'
              '• 纯本地 stdio 进程，不开任何网络端口，数据不外传。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocFooter extends StatelessWidget {
  const _DocFooter({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '完整文档',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'docs/ai-access.md（仓库内）——安装、MCP 客户端配置、工具参数、'
          '人工应急通道与排错。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Text(
          '注意：App 里的账号存在系统钥匙串，AI 读取的是独立 vault，'
          '两者互不影响——想给 AI 用的账号需要用 CLI 录入一次。',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
