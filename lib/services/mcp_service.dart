import 'package:totp_core/totp_core.dart';

import 'ai_settings_service.dart';

/// App 内的 MCP 服务宿主：按设置启动 / 停止本机 HTTP MCP 服务。
///
/// 与 CLI 的 `lzy-totp serve` 是同一份实现（内核里的 [McpHttpServer]），
/// 因此开关状态与服务地址（含 token、端口）都记在 `~/.config/lzy_totp/settings.json`，
/// 两边可以互相接管：App 里开着，命令行 `ai status`/`serve` 看到的是同一个服务配置。
///
/// 方法都可以被测试替身覆写（widget 测试里不能做真实网络 I/O）。
class McpService {
  McpService({AiSettingsService? settings, TotpPaths? paths})
      : settings = settings ?? AiSettingsService(paths: paths);

  final AiSettingsService settings;

  McpHttpServer? _server;

  McpHttpServer get _ensure => _server ??= McpHttpServer(
        vault: VaultStore(paths: settings.paths),
        audit: AuditLog(settings.paths.auditFile),
        settings: SettingsStore(paths: settings.paths),
      );

  bool get isRunning => _server?.isRunning ?? false;

  McpHttpStatus get status =>
      _server?.status ??
      const McpHttpStatus(
        running: false,
        port: 0,
        token: '',
        requestCount: 0,
        startedAt: null,
      );

  /// 复制即用的客户端配置片段（服务未运行时 url 为空）
  McpClientSnippets get snippets => McpClientSnippets(status.url);

  /// App 启动时调用：按设置决定是否拉起服务
  Future<void> applyFromSettings() async {
    try {
      if ((await settings.load()).mcpHttpEnabled) {
        await start();
      } else {
        await stop();
      }
    } catch (_) {
      // 启动失败（端口被占等）不应影响 App 启动，设置页会显示错误
    }
  }

  Future<McpHttpStatus> start() => _ensure.start();

  Future<void> stop() async {
    await _server?.stop();
  }

  /// 开关：持久化设置并同步启停
  Future<void> setEnabled(bool value) async {
    await settings.setMcpHttpEnabled(value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }
}
