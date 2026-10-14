import 'package:lzy_totp/services/ai_settings_service.dart';
import 'package:totp_core/totp_core.dart';

/// 内存版设置：跳过真实 `~/.config/lzy_totp/settings.json`，仅供 widget 测试使用。
class FakeAiSettingsService extends AiSettingsService {
  FakeAiSettingsService({this.enabled = true, this.mcpEnabled = false})
      // 只为构造对象，不落盘（读写方法都被覆写）
      : super(paths: TotpPaths('/tmp/lzy_totp_fake_settings'));

  /// 当前是否允许 AI / MCP 取码
  bool enabled;

  /// 是否要求 App 启动本机 MCP 服务
  bool mcpEnabled;

  /// 写入次数，用来断言「开关确实被持久化」
  int writeCount = 0;

  /// 设为非 null 时写入抛错，用于验证回滚
  Object? failWith;

  @override
  Future<TotpSettings> load() async =>
      TotpSettings(aiAccessEnabled: enabled, mcpHttpEnabled: mcpEnabled);

  @override
  Future<void> setMcpHttpEnabled(bool value) async {
    writeCount++;
    if (failWith != null) throw failWith!;
    mcpEnabled = value;
  }

  @override
  Future<bool> aiAccessEnabled() async => enabled;

  @override
  Future<void> setAiAccessEnabled(bool value) async {
    writeCount++;
    if (failWith != null) throw failWith!;
    enabled = value;
  }
}
