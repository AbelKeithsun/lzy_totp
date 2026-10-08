import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:totp_cli/mcp_server.dart';
import 'package:totp_core/totp_core.dart';

/// 收集输出的 IOSink（便于断言 CLI/MCP 的文本输出）
///
/// 使用同步 StreamController：IOSink.flush() 返回时数据已进入缓冲区，
/// 否则异步投递会晚于断言。
class CaptureSink {
  CaptureSink() {
    _controller.stream.listen(_buffer.addAll);
  }

  final List<int> _buffer = [];
  final StreamController<List<int>> _controller =
      StreamController<List<int>>(sync: true);
  late final IOSink sink = IOSink(_controller.sink);

  String get text => utf8.decode(_buffer);

  /// 清空已收集的输出（一次测试内跑多条命令时，避免把上一条的输出算进来）
  void clear() => _buffer.clear();

  Future<void> close() async {
    await sink.flush();
    await _controller.close();
  }
}

void main() {
  late Directory tmp;
  late TotpPaths paths;
  late VaultStore vault;
  late AuditLog audit;
  late McpServer server;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('totp_cli_test_');
    paths = TotpPaths(tmp.path);
    vault = VaultStore(paths: paths);
    audit = AuditLog(paths.auditFile);
    server = McpServer(vault: vault, audit: audit);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> call(
    Map<String, dynamic> message,
  ) async {
    final response = await server.handle(message);
    return response!;
  }

  Future<Map<String, dynamic>> callTool(
    String name, [
    Map<String, dynamic> args = const {},
  ]) =>
      call({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': name, 'arguments': args},
      });

  /// 取出 tools/call 的文本内容
  Map<String, dynamic> toolJson(Map<String, dynamic> response) {
    final result = response['result'] as Map<String, dynamic>;
    expect(result['isError'], isNot(true), reason: '不应是错误响应：$result');
    final text = ((result['content'] as List).first as Map)['text'] as String;
    return jsonDecode(text) as Map<String, dynamic>;
  }

  String toolText(Map<String, dynamic> response) =>
      (((response['result'] as Map)['content'] as List).first as Map)['text']
          as String;

  group('MCP 协议', () {
    test('initialize 返回协议版本与工具能力', () async {
      final r = await call({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2024-11-05', 'capabilities': {}},
      });
      final result = r['result'] as Map<String, dynamic>;
      expect(result['protocolVersion'], '2024-11-05');
      expect((result['capabilities'] as Map)['tools'], isNotNull);
      expect((result['serverInfo'] as Map)['name'], 'lzy_totp');
    });

    test('tools/list 暴露 7 个工具且不含密钥读取工具', () async {
      final r = await call({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      final tools = (r['result'] as Map)['tools'] as List;
      final names = tools.map((t) => (t as Map)['name']).toList();
      expect(names, containsAll([
        'list_accounts',
        'get_account_info',
        'generate_totp',
        'add_account',
        'add_from_uri',
        'remove_account',
        'set_ai_allowed',
      ]));
      expect(names, isNot(contains('get_secret')));
    });

    test('通知类消息不产生响应', () async {
      final r = await server.handle({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      expect(r, isNull);
    });

    test('未知方法返回 -32603 错误', () async {
      final r = await call({'jsonrpc': '2.0', 'id': 3, 'method': 'no/such'});
      expect((r['error'] as Map)['message'], contains('不支持的方法'));
    });
  });

  group('默认拒绝策略', () {
    test('未放行的账号取码被拒绝，且不返回验证码', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
      });

      final r = await callTool('generate_totp', {'account': 'github'});
      final result = r['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      expect(toolText(r), contains('拒绝取码'));
      expect(toolText(r), isNot(matches(RegExp(r'\b\d{6}\b'))),
          reason: '拒绝时不得泄露任何验证码');
    });

    test('拒绝行为会写入审计日志', () async {
      await callTool('add_account', {
        'account': 'bank',
        'secret': 'JBSWY3DPEHPK3PXP',
      });
      await callTool('generate_totp', {'account': 'bank'});

      final entries = await audit.tail(10);
      final denied = entries.where((e) => e.result == 'denied').toList();
      expect(denied, hasLength(1));
      expect(denied.single.actor, 'mcp');
      expect(denied.single.action, 'generate_totp');
    });

    test('add_account 默认不允许 AI，显式 allow_ai 才放行', () async {
      final added = toolJson(await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
      }));
      expect(added['ai_allowed'], isFalse);

      final allowed = toolJson(await callTool('add_account', {
        'account': 'gitlab',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitLab',
        'allow_ai': true,
      }));
      expect(allowed['ai_allowed'], isTrue);
    });

    test('set_ai_allowed 放行后可以取码，撤销后再次拒绝', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
      });

      await callTool('set_ai_allowed', {'account': 'github', 'allowed': true});
      final ok = toolJson(await callTool('generate_totp', {'account': 'github'}));
      expect(ok['code'], matches(RegExp(r'^\d{6}$')));
      expect(ok['remaining_seconds'], inInclusiveRange(1, 30));

      await callTool('set_ai_allowed', {'account': 'github', 'allowed': false});
      final denied = await callTool('generate_totp', {'account': 'github'});
      expect((denied['result'] as Map)['isError'], isTrue);
    });
  });

  group('工具行为', () {
    test('list_accounts 只返回元数据，不含密钥', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
      });
      final list = toolJson(await callTool('list_accounts'));
      final accounts = list['accounts'] as List;
      expect(accounts, hasLength(1));
      final first = accounts.first as Map;
      expect(first['account'], 'GitHub');
      expect(first['ai_allowed'], isFalse);
      expect(jsonEncode(list).contains('JBSWY3DPEHPK3PXP'), isFalse,
          reason: '工具输出绝不能带出密钥');
    });

    test('add_from_uri 解析 otpauth URI', () async {
      final added = toolJson(await callTool('add_from_uri', {
        'account': 'google',
        'uri':
            'otpauth://totp/Google:bob@gmail.com?secret=JBSWY3DPEHPK3PXP&issuer=Google',
      }));
      expect(added['issuer'], 'Google');
      expect(added['label'], 'bob@gmail.com');
    });

    test('非法 URI 与非法密钥被拒绝', () async {
      final bad = await callTool('add_from_uri', {
        'account': 'x',
        'uri': 'https://example.com',
      });
      expect((bad['result'] as Map)['isError'], isTrue);

      final badSecret = await callTool('add_account', {
        'account': 'x',
        'secret': '不是base32!!',
      });
      expect((badSecret['result'] as Map)['isError'], isTrue);
    });

    test('缺少必填参数返回错误', () async {
      final r = await callTool('generate_totp');
      expect((r['result'] as Map)['isError'], isTrue);
      expect(toolText(r), contains('缺少必填参数 account'));
    });

    test('重名添加被拒绝', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
      });
      final dup = await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
      });
      expect((dup['result'] as Map)['isError'], isTrue);
      expect(toolText(dup), contains('已存在同名账户'));
    });

    test('remove_account 删除后不可再取码', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
        'allow_ai': true,
      });
      toolJson(await callTool('remove_account', {'account': 'github'}));
      final r = await callTool('generate_totp', {'account': 'github'});
      expect((r['result'] as Map)['isError'], isTrue);
      expect(toolText(r), contains('未找到账户'));
    });

    test('成功取码写入审计日志', () async {
      await callTool('add_account', {
        'account': 'github',
        'secret': 'JBSWY3DPEHPK3PXP',
        'issuer': 'GitHub',
        'allow_ai': true,
      });
      await callTool('generate_totp', {'account': 'github'});
      final entries = await audit.tail(10);
      expect(entries.any((e) => e.action == 'generate_totp' && e.result == 'ok'),
          isTrue);
    });
  });
}
