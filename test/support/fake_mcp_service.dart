import 'package:lzy_totp/services/ai_settings_service.dart';
import 'package:lzy_totp/services/mcp_service.dart';
import 'package:totp_core/totp_core.dart';

import 'fake_ai_settings.dart';

/// 假的 MCP 服务宿主：不做任何真实网络 I/O，供 widget 测试使用。
class FakeMcpService extends McpService {
  /// 内部用内存版设置服务：widget 测试里不能出现真实文件 I/O
  /// （fake-async 时区里它永不完成，会让界面卡在 busy 态）
  FakeMcpService({this.running = false, this.failWith, AiSettingsService? settings})
      : super(settings: settings ?? FakeAiSettingsService(mcpEnabled: running));

  static const _token = 'deadbeefdeadbeefdeadbeefdeadbeef';

  /// 当前是否「运行中」
  bool running;

  /// 设为非 null 时 start 抛错，用于验证失败回滚
  Object? failWith;

  int startCount = 0;
  int stopCount = 0;

  @override
  bool get isRunning => running;

  @override
  McpHttpStatus get status => running
      ? const McpHttpStatus(
          running: true,
          port: 45763,
          token: _token,
          requestCount: 3,
          startedAt: null,
        )
      : const McpHttpStatus(
          running: false,
          port: 0,
          token: '',
          requestCount: 0,
          startedAt: null,
        );

  @override
  Future<void> applyFromSettings() async {}

  @override
  Future<McpHttpStatus> start() async {
    startCount++;
    if (failWith != null) throw failWith!;
    running = true;
    return status;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    running = false;
  }

  @override
  Future<void> setEnabled(bool value) async {
    await settings.setMcpHttpEnabled(value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }
}
