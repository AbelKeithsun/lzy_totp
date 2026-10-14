import 'dart:convert';
import 'dart:io';

import 'fs_utils.dart';
import 'paths.dart';

/// 本地设置（App、CLI、MCP 共用同一份文件）。
///
/// 目前只有一项：AI / MCP 取码总开关。放在数据目录而不是系统钥匙串里，
/// 是为了让 CLI 与 MCP（无 GUI、可能是 AI 子进程）也能读到它。
class TotpSettings {
  const TotpSettings({
    this.aiAccessEnabled = true,
    this.mcpHttpEnabled = false,
    this.mcpHttpToken = '',
    this.mcpHttpPort = 0,
  });

  /// AI / MCP 取码总开关。
  ///
  /// `false` = 关闭：CLI 的读取/取码与 MCP 的所有工具都会被拒绝（fail closed），
  /// 但不会删除 vault 里的任何账号。默认 `true`（保持既有行为）。
  final bool aiAccessEnabled;

  /// 是否让 App 启动本机 MCP 服务（HTTP，仅回环）。
  ///
  /// 默认关闭：不开监听是更安全的默认值，需要时在 App 设置页一键启动。
  final bool mcpHttpEnabled;

  /// 服务地址里的随机 token（持久化，保证粘贴给 agent 的配置重启后依然有效）
  final String mcpHttpToken;

  /// 上次实际监听的端口（持久化，尽量让地址保持稳定）
  final int mcpHttpPort;

  static const TotpSettings enabled = TotpSettings();

  Map<String, dynamic> toJson() => {
        'version': 1,
        'aiAccessEnabled': aiAccessEnabled,
        'mcpHttpEnabled': mcpHttpEnabled,
        'mcpHttpToken': mcpHttpToken,
        'mcpHttpPort': mcpHttpPort,
      };

  factory TotpSettings.fromJson(Map<String, dynamic> json) => TotpSettings(
        aiAccessEnabled: json['aiAccessEnabled'] as bool? ?? true,
        mcpHttpEnabled: json['mcpHttpEnabled'] as bool? ?? false,
        mcpHttpToken: json['mcpHttpToken'] as String? ?? '',
        mcpHttpPort: json['mcpHttpPort'] as int? ?? 0,
      );

  TotpSettings copyWith({
    bool? aiAccessEnabled,
    bool? mcpHttpEnabled,
    String? mcpHttpToken,
    int? mcpHttpPort,
  }) =>
      TotpSettings(
        aiAccessEnabled: aiAccessEnabled ?? this.aiAccessEnabled,
        mcpHttpEnabled: mcpHttpEnabled ?? this.mcpHttpEnabled,
        mcpHttpToken: mcpHttpToken ?? this.mcpHttpToken,
        mcpHttpPort: mcpHttpPort ?? this.mcpHttpPort,
      );
}

/// 设置读写：文件不存在或损坏时回退到默认值（总开关=开），
/// 绝不因为读不到设置就把用户锁在外面（读不到设置时按既有默认行为走）。
class SettingsStore {
  SettingsStore({required this.paths});

  final TotpPaths paths;

  Future<TotpSettings> load() async {
    final file = File(paths.settingsFile);
    if (!await file.exists()) return TotpSettings.enabled;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map<String, dynamic>) return TotpSettings.enabled;
      return TotpSettings.fromJson(raw);
    } catch (_) {
      return TotpSettings.enabled;
    }
  }

  /// 原子写入并保持 600 权限
  Future<void> save(TotpSettings settings) async {
    await ensurePrivateDir(paths.home);
    await writeFileAtomic(
      paths.settingsFile,
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
    await restrictFilePermissions(paths.settingsFile);
  }

  /// 读改写（避免覆盖其它字段）
  Future<TotpSettings> update(
      TotpSettings Function(TotpSettings current) mutate) async {
    final next = mutate(await load());
    await save(next);
    return next;
  }

  /// 只改 AI 取码总开关
  Future<TotpSettings> setAiAccessEnabled(bool enabled) =>
      update((current) => current.copyWith(aiAccessEnabled: enabled));

  /// 只改「本机 MCP 服务」开关
  Future<TotpSettings> setMcpHttpEnabled(bool enabled) =>
      update((current) => current.copyWith(mcpHttpEnabled: enabled));
}
