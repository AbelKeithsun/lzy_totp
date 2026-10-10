import 'dart:convert';
import 'dart:io';

import 'package:totp_core/totp_core.dart';

/// MCP 工具调用失败（会以 isError 形式回给客户端，而非协议错误）
class McpToolError implements Exception {
  McpToolError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 极简 MCP（Model Context Protocol）stdio server。
///
/// 只实现 AI 客户端真正需要的部分：initialize / tools/list / tools/call / ping。
/// 传输为换行分隔的 JSON-RPC 2.0（即 MCP stdio transport）。
///
/// 安全设计：
/// - 工具面**永不返回密钥**，只返回一次性验证码与元数据；
/// - 取码前强制走 [AiAccessPolicy]（默认放行，被 deny 的账号拒绝）；
/// - 每次取码（无论成功或拒绝）都写审计日志。
class McpServer {
  McpServer({
    required this.vault,
    required this.audit,
    this.serverName = 'lzy_totp',
    this.serverVersion = '0.1.0',
  });

  final VaultStore vault;
  final AuditLog audit;
  final String serverName;
  final String serverVersion;

  static const supportedProtocolVersion = '2025-06-18';

  /// 处理单条 JSON-RPC 消息；返回 null 表示无需响应（通知）。
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> message) async {
    final id = message['id'];
    final method = message['method'] as String?;
    if (method == null) return null;
    // 通知类消息一律不响应
    if (method.startsWith('notifications/')) return null;

    final rawParams = message['params'];
    final params = rawParams is Map
        ? rawParams.cast<String, dynamic>()
        : <String, dynamic>{};

    try {
      final result = await _dispatch(method, params);
      if (id == null) return null;
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on McpToolError catch (e) {
      if (id == null) return null;
      if (method == 'tools/call') {
        // MCP 规范：工具的业务失败放在 result 里，标记 isError
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'content': [
              {'type': 'text', 'text': e.message}
            ],
            'isError': true,
          },
        };
      }
      return _error(id, -32603, e.message);
    } catch (e) {
      if (id == null) return null;
      return _error(id, -32603, '内部错误: $e');
    }
  }

  /// 常驻 stdio 循环
  Future<void> serve(Stream<List<int>> input, IOSink output) async {
    final lines = input
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> message;
      try {
        message = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        await _write(output, _error(null, -32700, 'JSON 解析失败'));
        continue;
      }
      final response = await handle(message);
      if (response != null) await _write(output, response);
    }
  }

  Future<Map<String, dynamic>> _dispatch(
    String method,
    Map<String, dynamic> params,
  ) async {
    switch (method) {
      case 'initialize':
        final requested = params['protocolVersion'] as String?;
        return {
          'protocolVersion': requested ?? supportedProtocolVersion,
          'capabilities': {
            'tools': {'listChanged': false}
          },
          'serverInfo': {'name': serverName, 'version': serverVersion},
          'instructions':
              'lzy_totp 一次性验证码（TOTP）服务。用 list_accounts 查看可用账号，'
                  '用 generate_totp 取当前验证码（默认放行；被 deny 的账号会拒绝并说明原因）。',
        };
      case 'ping':
        return <String, dynamic>{};
      case 'tools/list':
        return {'tools': _toolDefinitions};
      case 'tools/call':
        final name = params['name'] as String?;
        if (name == null) throw McpToolError('缺少参数 name');
        final args = params['arguments'] is Map
            ? (params['arguments'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        return _callTool(name, args);
      default:
        throw McpToolError('不支持的方法: $method');
    }
  }

  Future<Map<String, dynamic>> _callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'list_accounts':
        return _text(await _listAccounts());
      case 'get_account_info':
        return _text(await _accountInfo(_requireString(args, 'account')));
      case 'generate_totp':
        return _text(await _generateTotp(_requireString(args, 'account')));
      case 'add_account':
        return _text(await _addAccount(args));
      case 'add_from_uri':
        return _text(await _addFromUri(args));
      case 'remove_account':
        return _text(await _removeAccount(_requireString(args, 'account')));
      case 'set_ai_allowed':
        return _text(await _setAiAllowed(args));
      default:
        throw McpToolError('未知工具: $name');
    }
  }

  // ---------------------------------------------------------------- 工具实现

  Future<String> _listAccounts() async {
    final accounts = await vault.load();
    if (accounts.isEmpty) {
      return jsonEncode({
        'accounts': <dynamic>[],
        'hint': 'vault 为空。请先执行 lzy_totp add <名称> --secret <Base32> 录入账号。',
      });
    }
    return _encode({
      'accounts': accounts.map(_metadata).toList(),
      'note': '默认放行；ai_allowed=false 表示该账号已被显式禁止，调用 generate_totp 会被拒绝。',
    });
  }

  Future<String> _accountInfo(String query) async {
    final account = await _requireAccount(query);
    return _encode(_metadata(account));
  }

  Future<String> _generateTotp(String query) async {
    final account = await _requireAccount(query);

    final denial = AiAccessPolicy.denialReason(account);
    if (denial != null) {
      await audit.append(AuditEntry(
        action: 'generate_totp',
        account: account.displayTitle,
        result: 'denied',
        actor: 'mcp',
        note: 'ai_blocked',
      ));
      throw McpToolError('拒绝取码：$denial');
    }

    final now = DateTime.now();
    final code = TotpService.codeFor(account, now: now);
    final remaining = TotpService.remainingSeconds(period: account.period, now: now);
    await audit.append(AuditEntry(
      action: 'generate_totp',
      account: account.displayTitle,
      result: 'ok',
      actor: 'mcp',
    ));
    return _encode({
      'account': account.displayTitle,
      'code': code,
      'remaining_seconds': remaining,
      'period': account.period,
      'expires_at': now.add(Duration(seconds: remaining)).toUtc().toIso8601String(),
    });
  }

  Future<String> _addAccount(Map<String, dynamic> args) async {
    final name = _requireString(args, 'account');
    final secret = _normalizeSecret(_requireString(args, 'secret'));
    _validateSecret(secret);

    final accounts = await vault.load();
    if (accounts.any((a) => a.matches(name))) {
      throw McpToolError('已存在同名账户「$name」，如需覆盖请先 remove_account。');
    }

    final account = TotpAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      // account 参数就是「账户名」，必须保留下来，否则后续按名字查不到它
      issuer: args['issuer'] as String? ?? '',
      label: args['label'] as String? ?? name,
      secret: secret,
      digits: args['digits'] as int? ?? 6,
      period: args['period'] as int? ?? 30,
      algorithm: (args['algorithm'] as String? ?? 'SHA1').toUpperCase(),
      // 默认放行：只有显式传 block_ai=true 才禁止
      aiAllowed: !(args['block_ai'] as bool? ?? false),
      note: args['note'] as String? ?? '',
    );
    accounts.add(account);
    await vault.save(accounts);
    await audit.append(AuditEntry(
      action: 'add_account',
      account: account.displayTitle,
      result: 'ok',
      actor: 'mcp',
      note: 'ai_allowed=${account.aiAllowed}',
    ));
    return _encode(_metadata(account));
  }

  Future<String> _addFromUri(Map<String, dynamic> args) async {
    final name = _requireString(args, 'uri');
    final parsed = TotpAccount.fromOtpAuthUri(
      name,
      aiAllowed: !(args['block_ai'] as bool? ?? false),
    );
    if (parsed == null) {
      throw McpToolError('otpauth URI 解析失败（仅支持 otpauth://totp/... 且需包含 secret）。');
    }

    final accounts = await vault.load();
    final label = (args['account'] as String?) ?? parsed.displayTitle;
    if (accounts.any((a) => a.matches(label))) {
      throw McpToolError('已存在同名账户「$label」，如需覆盖请先 remove_account。');
    }
    final account = TotpAccount(
      id: parsed.id,
      issuer: parsed.issuer,
      label: parsed.label,
      secret: parsed.secret,
      digits: parsed.digits,
      period: parsed.period,
      algorithm: parsed.algorithm,
      aiAllowed: parsed.aiAllowed,
      note: args['note'] as String? ?? '',
    );
    accounts.add(account);
    await vault.save(accounts);
    await audit.append(AuditEntry(
      action: 'add_from_uri',
      account: account.displayTitle,
      result: 'ok',
      actor: 'mcp',
      note: 'ai_allowed=${account.aiAllowed}',
    ));
    return _encode(_metadata(account));
  }

  Future<String> _removeAccount(String query) async {
    final account = await _requireAccount(query);
    await vault.update((accounts) async {
      accounts.removeWhere((a) => a.id == account.id);
      return null;
    });
    await audit.append(AuditEntry(
      action: 'remove_account',
      account: account.displayTitle,
      result: 'ok',
      actor: 'mcp',
    ));
    return _encode({'removed': account.displayTitle});
  }

  Future<String> _setAiAllowed(Map<String, dynamic> args) async {
    final account = await _requireAccount(_requireString(args, 'account'));
    final allowed = args['allowed'];
    if (allowed is! bool) {
      throw McpToolError('参数 allowed 必须是布尔值');
    }
    await vault.update((accounts) async {
      final target = accounts.firstWhere((a) => a.id == account.id);
      target.aiAllowed = allowed;
      return null;
    });
    await audit.append(AuditEntry(
      action: 'set_ai_allowed',
      account: account.displayTitle,
      result: 'ok',
      actor: 'mcp',
      note: 'allowed=$allowed',
    ));
    return _encode({'account': account.displayTitle, 'ai_allowed': allowed});
  }

  // ------------------------------------------------------------------ 辅助

  Map<String, dynamic> _metadata(TotpAccount a) => {
        'account': a.displayTitle,
        'id': a.id,
        'issuer': a.issuer,
        'label': a.label,
        'digits': a.digits,
        'period': a.period,
        'algorithm': a.algorithm,
        'ai_allowed': a.aiAllowed,
        'note': a.note,
      };

  Future<TotpAccount> _requireAccount(String query) async {
    final accounts = await vault.load();
    final matches = accounts.where((a) => a.matches(query)).toList();
    if (matches.isEmpty) {
      final available = accounts.map((a) => a.displayTitle).join('、');
      throw McpToolError(
        '未找到账户「$query」。${available.isEmpty ? 'vault 为空。' : '可用账号：$available'}',
      );
    }
    if (matches.length > 1) {
      throw McpToolError('「$query」匹配到 ${matches.length} 个账户，请使用更精确的名称。');
    }
    return matches.single;
  }

  static String _requireString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.trim().isEmpty) {
      throw McpToolError('缺少必填参数 $key');
    }
    return value.trim();
  }

  static String _normalizeSecret(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'\s'), '');

  static void _validateSecret(String secret) {
    if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(secret)) {
      throw McpToolError('密钥格式不正确：应为 Base32（字母 A-Z 与数字 2-7）。');
    }
    try {
      TotpService.codeFor(TotpAccount(
        id: 'validate',
        issuer: '',
        label: '',
        secret: secret,
      ));
    } catch (_) {
      throw McpToolError('密钥无法解码，请检查是否完整。');
    }
  }

  static Map<String, dynamic> _text(String text) => {
        'content': [
          {'type': 'text', 'text': text}
        ],
      };

  static String _encode(Object value) =>
      const JsonEncoder.withIndent('  ').convert(value);

  Map<String, dynamic> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  Future<void> _write(IOSink output, Map<String, dynamic> message) async {
    output.writeln(jsonEncode(message));
    await output.flush();
  }
}

/// 暴露给 MCP 客户端的工具清单
const List<Map<String, dynamic>> _toolDefinitions = [
  {
    'name': 'list_accounts',
    'description': '列出 vault 中全部 TOTP 账号及其是否允许 AI 取码（不返回密钥）。',
    'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
  },
  {
    'name': 'get_account_info',
    'description': '查看单个账号的安全元数据（不含密钥）。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string', 'description': '账号名称（或 id / issuer / label）'},
      },
      'required': ['account'],
    },
  },
  {
    'name': 'generate_totp',
    'description': '生成指定账号当前的一次性验证码（30 秒内有效）。'
        '默认放行；若该账号被显式禁止（ai_allowed=false）则返回错误。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string', 'description': '账号名称'},
      },
      'required': ['account'],
    },
  },
  {
    'name': 'add_account',
    'description': '添加一个 TOTP 账号（默认允许 AI 取码；传 block_ai=true 可禁止）。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string', 'description': '账号名称（唯一）'},
        'secret': {'type': 'string', 'description': 'Base32 密钥'},
        'issuer': {'type': 'string'},
        'label': {'type': 'string'},
        'digits': {'type': 'integer', 'enum': [6, 8]},
        'period': {'type': 'integer', 'enum': [30, 60]},
        'algorithm': {'type': 'string', 'enum': ['SHA1', 'SHA256', 'SHA512']},
        'block_ai': {'type': 'boolean', 'description': '是否禁止 AI 取码，默认 false（即允许）'},
      },
      'required': ['account', 'secret'],
    },
  },
  {
    'name': 'add_from_uri',
    'description': '从 otpauth:// URI 添加账号（默认允许 AI 取码）。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string', 'description': '账号名称'},
        'uri': {'type': 'string', 'description': 'otpauth://totp/... 完整 URI'},
        'block_ai': {'type': 'boolean', 'description': '是否禁止 AI 取码'},
      },
      'required': ['account', 'uri'],
    },
  },
  {
    'name': 'remove_account',
    'description': '从 vault 删除账号。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string'},
      },
      'required': ['account'],
    },
  },
  {
    'name': 'set_ai_allowed',
    'description': '允许或禁止某个账号的 AI 取码权限（默认允许）。',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'account': {'type': 'string'},
        'allowed': {'type': 'boolean'},
      },
      'required': ['account', 'allowed'],
    },
  },
];
