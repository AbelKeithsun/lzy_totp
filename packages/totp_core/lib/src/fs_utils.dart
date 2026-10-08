import 'dart:io';
import 'dart:math';

/// 把文件权限收紧到 600（仅属主可读写）。Windows 上为空操作。
Future<void> restrictFilePermissions(String path) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', ['600', path]);
}

/// 创建目录并把权限收紧到 700。
Future<void> ensurePrivateDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  if (!Platform.isWindows) {
    await Process.run('chmod', ['700', path]);
  }
}

/// 检查文件权限是否为 600（用于 doctor 自检）。Windows 返回 null（不适用）。
Future<String?> describePermissions(String path) async {
  if (Platform.isWindows) return null;
  final result = await Process.run('stat', ['-f', '%Lp', path]);
  if (result.exitCode != 0) return null;
  return (result.stdout as String).trim();
}

/// 密码学安全随机字节
List<int> randomBytes(int length) {
  final rnd = Random.secure();
  return List<int>.generate(length, (_) => rnd.nextInt(256));
}

/// 原子写文件：先写临时文件再 rename，避免中途崩溃导致文件损坏。
Future<void> writeFileAtomic(String path, String contents) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsString(contents, flush: true);
  await restrictFilePermissions(tmp.path);
  await tmp.rename(path);
}
