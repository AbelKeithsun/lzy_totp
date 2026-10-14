import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:totp_core/totp_core.dart';

/// 一次 HTTP 往返的结果
class _Res {
  _Res(this.status, this.headers, this.body);

  final int status;
  final HttpHeaders headers;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

void main() {
  late Directory tmp;
  late TotpPaths paths;
  late VaultStore vault;
  late AuditLog audit;
  late SettingsStore settings;
  late McpHttpServer server;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('totp_http_test_');
    paths = TotpPaths(tmp.path);
    vault = VaultStore(paths: paths);
    audit = AuditLog(paths.auditFile);
    settings = SettingsStore(paths: paths);
    server = McpHttpServer(
      vault: vault,
      audit: audit,
      settings: settings,
      defaultPort: 45871,
    );
  });

  tearDown(() async {
    await server.stop();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<_Res> send(
    String path, {
    Object? message,
    String? method,
    Map<String, String> headers = const {},
    String? rawBody,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method ?? 'POST',
        Uri.parse('http://127.0.0.1:${server.status.port}$path'),
      );
      headers.forEach(request.headers.set);
      if (rawBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(rawBody);
      } else if (message != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(message));
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return _Res(response.statusCode, response.headers, body);
    } finally {
      client.close(force: true);
    }
  }

  Future<_Res> rpc(Object message) =>
      send('/mcp/${server.status.token}', message: message);

  group('MCP over HTTP（Streamable HTTP 最小集）', () {
    test('启动后给出带 token 的地址，token 与端口会持久化', () async {
      final status = await server.start();
      expect(status.running, isTrue);
      expect(status.port, greaterThan(0));
      expect(status.token, hasLength(32));
      expect(status.url, 'http://127.0.0.1:${status.port}/mcp/${status.token}');

      final saved = await settings.load();
      expect(saved.mcpHttpToken, status.token);
      expect(saved.mcpHttpPort, status.port);

      // 重启后地址保持不变（粘贴给 agent 的配置不会失效）
      await server.stop();
      final again = await server.start();
      expect(again.token, status.token);
      expect(again.port, status.port);
    });

    test('initialize / tools/list / tools/call 都可用', () async {
      await server.start();
      await vault.save([
        TotpAccount(
            id: '1', issuer: 'Jenkins', label: 'prod', secret: 'JBSWY3DPEHPK3PXP')
      ]);

      final init = await rpc({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18', 'capabilities': {}},
      });
      expect(init.status, 200);
      expect(init.headers.contentType?.mimeType, 'application/json');
      expect((init.json['result'] as Map)['serverInfo']['name'], 'lzy_totp');

      final tools = await rpc({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      expect((tools.json['result'] as Map)['tools'], hasLength(7));

      final call = await rpc({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'generate_totp',
          'arguments': {'account': 'prod'},
        },
      });
      final text =
          ((call.json['result'] as Map)['content'] as List).first['text'] as String;
      expect(jsonDecode(text)['code'], hasLength(6));
      expect(server.status.requestCount, 3);
    });

    test('token 不对返回 404，不泄露服务存在', () async {
      await server.start();
      final response = await send('/mcp/deadbeef',
          message: {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'});
      expect(response.status, 404);
    });

    test('GET / DELETE 返回 405 且带 Allow: POST（本实现无 SSE 流）', () async {
      await server.start();
      final get = await send('/mcp/${server.status.token}', method: 'GET');
      expect(get.status, 405);
      expect(get.headers.value('allow'), 'POST');
      final delete = await send('/mcp/${server.status.token}', method: 'DELETE');
      expect(delete.status, 405);
    });

    test('带 Origin 的请求一律 403（挡掉网页偷偷调用本机取码）', () async {
      await server.start();
      final response = await send(
        '/mcp/${server.status.token}',
        message: {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
        headers: {'origin': 'https://evil.example'},
      );
      expect(response.status, 403);
    });

    test('Host 头不是回环地址时 403（防 DNS rebinding）', () async {
      await server.start();
      // Host 头不能通过 HttpClient 伪造，这里直接写原始 HTTP 请求
      final token = server.status.token;
      final body = '{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}';
      final socket = await Socket.connect('127.0.0.1', server.status.port);
      socket.write('POST /mcp/$token HTTP/1.1\r\n'
          'Host: evil.example\r\n'
          'Content-Type: application/json\r\n'
          'Content-Length: ${body.length}\r\n'
          'Connection: close\r\n\r\n'
          '$body');
      await socket.flush();
      final raw = await utf8.decoder.bind(socket).join();
      await socket.close();
      expect(raw, startsWith('HTTP/1.1 403'));
    });

    test('通知（无 id）返回 202 且无正文', () async {
      await server.start();
      final response = await send(
        '/mcp/${server.status.token}',
        message: {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
      );
      expect(response.status, 202);
      expect(response.body, isEmpty);
    });

    test('非法 JSON 返回 -32700，数组请求返回 -32600', () async {
      await server.start();
      final bad = await send('/mcp/${server.status.token}',
          rawBody: '{ not valid json');
      expect(bad.json['error']['code'], -32700);

      final batch = await rpc([
        {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}
      ]);
      expect(batch.json['error']['code'], -32600);
    });

    test('总开关关闭时，HTTP 上的工具调用同样被拒绝', () async {
      await server.start();
      await settings.setAiAccessEnabled(false);
      final call = await rpc({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {
          'name': 'list_accounts',
          'arguments': <String, dynamic>{},
        },
      });
      expect((call.json['result'] as Map)['isError'], isTrue);
      expect(
        ((call.json['result'] as Map)['content'] as List).first['text'],
        contains('总开关已关闭'),
      );
    });

    test('stop 之后端口不再接受连接', () async {
      final status = await server.start();
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(server.status.url, isEmpty);
      await expectLater(
        HttpClient()
            .postUrl(Uri.parse(
                'http://127.0.0.1:${status.port}/mcp/${status.token}'))
            .then((r) => r.close()),
        throwsA(isA<SocketException>()),
      );
    });

    test('端口被占用时自动换端口', () async {
      final blocker = await HttpServer.bind(InternetAddress.loopbackIPv4, 45871);
      addTearDown(() => blocker.close(force: true));
      final status = await server.start();
      expect(status.running, isTrue);
      expect(status.port, isNot(45871));
    });
  });
}
