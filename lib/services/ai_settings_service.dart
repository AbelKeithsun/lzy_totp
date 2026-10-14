import 'package:totp_core/totp_core.dart';

/// App 侧的设置读写（目前只有 AI / MCP 取码总开关）。
///
/// 设置落在与 CLI / MCP 共用的数据目录（`~/.config/lzy_totp/settings.json`），
/// 所以 App 里一关，agent 那边下一次调用立刻就会被拒绝。
class AiSettingsService {
  AiSettingsService({TotpPaths? paths}) : paths = paths ?? TotpPaths.resolve();

  final TotpPaths paths;

  late final SettingsStore _store = SettingsStore(paths: paths);

  String get settingsFile => paths.settingsFile;

  Future<TotpSettings> load() => _store.load();

  Future<bool> aiAccessEnabled() async => (await _store.load()).aiAccessEnabled;

  Future<void> setAiAccessEnabled(bool value) =>
      _store.setAiAccessEnabled(value);
}
