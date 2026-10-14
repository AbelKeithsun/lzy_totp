import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../audit.dart';
import '../settings.dart';
import '../vault.dart';
import 'mcp_server.dart';

/// 服务状态快照（给界面显示用）
class McpHttpStatus {
  const McpHttpStatus({
    required this.running,
    required this.port,
    required this.token,
    required this.requestCount,
    required this.startedAt,
    this.lastError,
  });

  final bool running;
  final int port;
  final String token;
  final int requestCount;
  final DateTime? startedAt;
  final String? lastError;

  /// 给 MCP 客户端用的完整地址（含 token）；未运行时为空串
  String get url => running ? 'http://127.0.0.1:$port/mcp/$token' : '';
}

/// MCP 的 HTTP 传输（Streamable HTTP 的最小子集）：POST 一个 JSON-RPC 消息，
/// 直接返回 JSON-RPC 响应；通知返回 202。
///
/// 与 stdio 版 [McpServer] 共用同一份工具实现与策略/审计。
///
/// 安全设计（本地监听必须做的三件事）：
/// 1. 只绑 `127.0.0.1`，且校验来源地址是回环；
/// 2. 地址里带随机 token（`/mcp/<token>`），token 不匹配一律 404；
/// 3. 校验 `Host` 必须是回环地址（防 DNS rebinding），并**拒绝带 Origin 的请求**
///    （浏览器跨源请求才会带 Origin，MCP 客户端不会）——避免网页偷偷调用本机取码。
class McpHttpServer {
  McpHttpServer({
    required this.vault,
    required this.audit,
    SettingsStore? settings,
    this.serverName = 'lzy_totp',
    this.defaultPort = 45763,
  })  : settings = settings ?? SettingsStore(paths: vault.paths),
        mcp = McpServer(
          vault: vault,
          audit: audit,
          settings: settings ?? SettingsStore(paths: vault.paths),
          serverName: serverName,
        );

  final VaultStore vault;
  final AuditLog audit;
  final SettingsStore settings;
  final McpServer mcp;
  final String serverName;

  /// 默认端口；被占用时自动向后找
  final int defaultPort;

  HttpServer? _server;
  String _token = '';
  int _port = 0;
  int _requests = 0;
  DateTime? _startedAt;
  String? _lastError;

  bool get isRunning => _server != null;

  McpHttpStatus get status => McpHttpStatus(
        running: isRunning,
        port: _port,
        token: _token,
        requestCount: _requests,
        startedAt: _startedAt,
        lastError: _lastError,
      );

  /// 启动服务（幂等）：token 与端口会写进 settings.json，
  /// 这样粘贴到 agent 里的配置在 App 重启后依然有效。
  Future<McpHttpStatus> start() async {
    if (isRunning) return status;

    final current = await settings.load();
    _token = current.mcpHttpToken.isNotEmpty
        ? current.mcpHttpToken
        : _generateToken();

    HttpServer? bound;
    var usedPort = 0;
    // 先试上次用过的端口，再试默认端口及其后 20 个，最后退回系统分配
    final candidates = <int>[
      if (current.mcpHttpPort > 0) current.mcpHttpPort,
      defaultPort,
      for (var i = 1; i <= 20; i++) defaultPort + i,
      0,
    ];
    for (final candidate in candidates) {
      try {
        bound = await HttpServer.bind(InternetAddress.loopbackIPv4, candidate);
        usedPort = bound.port;
        break;
      } on SocketException {
        continue;
      }
    }
    if (bound == null) {
      _lastError = '无法在本机端口上启动 MCP 服务';
      throw StateError(_lastError!);
    }

    _server = bound;
    _port = usedPort;
    _requests = 0;
    _startedAt = DateTime.now();
    _lastError = null;

    await settings.save(current.copyWith(
      mcpHttpToken: _token,
      mcpHttpPort: usedPort,
    ));

    unawaited(bound.listen(_handle).asFuture<void>().catchError((_) {}));
    return status;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_isLocal(request)) {
        return _plain(response, HttpStatus.forbidden);
      }
      // 浏览器跨源请求会带 Origin；MCP 客户端不会。一律拒绝，挡掉网页偷偷调用
      if (request.headers.value('origin') != null) {
        return _plain(response, HttpStatus.forbidden);
      }
      if (request.uri.path != '/mcp/$_token') {
        return _plain(response, HttpStatus.notFound);
      }
      if (request.method != 'POST') {
        // 本实现是无状态的最小集：不提供 SSE 流与 session 删除
        response.headers.set(HttpHeaders.allowHeader, 'POST');
        return _plain(response, HttpStatus.methodNotAllowed);
      }

      final body = await utf8.decoder.bind(request).join();
      if (body.length > 1 << 20) {
        return _plain(response, HttpStatus.requestEntityTooLarge);
      }

      Map<String, dynamic> message;
      try {
        final decoded = jsonDecode(body);
        if (decoded is! Map<String, dynamic>) {
          return _json(response, _error(null, -32600, '请求体必须是单个 JSON-RPC 对象'));
        }
        message = decoded;
      } catch (_) {
        return _json(response, _error(null, -32700, 'JSON 解析失败'));
      }

      _requests++;
      final result = await mcp.handle(message);
      if (result == null) {
        // 通知：按规范返回 202 且无正文
        response.statusCode = HttpStatus.accepted;
        await response.close();
        return;
      }
      return _json(response, result);
    } catch (e) {
      _lastError = e.toString();
      return _plain(response, HttpStatus.internalServerError);
    }
  }

  /// 只接受回环来源，且 Host 头必须是回环地址（防 DNS rebinding）
  bool _isLocal(HttpRequest request) {
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null || !remote.isLoopback) return false;
    final host = request.headers.host ?? '';
    final hostname = host.contains(':') && !host.startsWith('[')
        ? host.split(':').first
        : host;
    return hostname == '127.0.0.1' ||
        hostname == 'localhost' ||
        hostname == '::1' ||
        hostname == '[::1]';
  }

  Future<void> _json(HttpResponse response, Map<String, dynamic> body) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _plain(HttpResponse response, int status) async {
    response.statusCode = status;
    await response.close();
  }

  Map<String, dynamic> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };
}
