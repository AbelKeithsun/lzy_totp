import 'dart:io';

import 'package:totp_cli/cli.dart';
import 'package:totp_core/totp_core.dart';

/// lzy_totp —— 命令行 + MCP stdio 入口
///
/// 数据目录默认 `~/.config/lzy_totp`，可用环境变量 `LZY_TOTP_HOME` 覆盖。
Future<void> main(List<String> argv) async {
  final paths = TotpPaths.resolve();
  final ctx = CliContext(
    paths: paths,
    vault: VaultStore(paths: paths),
    audit: AuditLog(paths.auditFile),
    out: stdout,
    err: stderr,
    stdinIsTerminal: stdin.hasTerminal,
    stdinStream: stdin,
  );

  final code = await runCli(argv, ctx);
  await stdout.flush();
  exit(code);
}
