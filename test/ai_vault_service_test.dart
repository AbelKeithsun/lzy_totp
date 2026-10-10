import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/services/ai_vault_service.dart';
import 'package:totp_core/totp_core.dart';

import 'support/fake_storage.dart';

void main() {
  late Directory dir;
  late AiVaultService service;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('lzy_vault_sync_test');
    service = AiVaultService(paths: TotpPaths(dir.path));
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('AiVaultService 真实 vault（临时目录）', () {
    test('同步后 CLI 侧能读到账号，且密钥加密落盘', () async {
      final account = testAccount('1', 'GitHub', 'me@github.com');
      final created = await service.sync(account);
      expect(created, isTrue);

      final loaded = await service.load();
      expect(loaded.length, 1);
      expect(loaded.single.displayTitle, 'GitHub (me@github.com)');
      expect(loaded.single.secret, account.secret);
      // 同步的意图就是让 AI 能取码
      expect(loaded.single.aiAllowed, isTrue);
      expect(service.stateOf(account, loaded), VaultSyncState.syncedAllowed);

      // 明文密钥不得出现在 vault 文件里，且权限为 600
      final raw = File(service.vaultFile).readAsStringSync();
      expect(raw.contains(account.secret), isFalse);
      expect(raw.contains('enc:v1:'), isTrue);
      expect(raw.contains('"aiAllowed": true'), isTrue);
    });

    test('重复同步不会产生重复条目，只更新元数据', () async {
      await service.sync(testAccount('1', 'GitHub', 'me@github.com'));
      final createdAgain = await service.sync(
        testAccount('2', 'GitHub', 'me@github.com', secret: 'JBSWY3DPEHPK3PXP'),
      );
      expect(createdAgain, isFalse);

      final loaded = await service.load();
      expect(loaded.length, 1);
      // 保留 vault 侧的 id，避免每次同步都换身份
      expect(loaded.single.id, isNot('2'));
    });

    test('不会覆盖 CLI 的 deny（同步前已禁止取码则保持禁止）', () async {
      final vault = VaultStore(paths: TotpPaths(dir.path));
      final account = testAccount('1', 'Bank', 'me@bank.com');
      await vault.save([account.copyWith(aiAllowed: false)]);

      await service.sync(testAccount('9', 'Bank', 'me@bank.com'));

      final loaded = await service.load();
      expect(loaded.single.aiAllowed, isFalse);
      expect(service.stateOf(account, loaded), VaultSyncState.syncedBlocked);
    });

    test('显示名相同但密钥不同的账号视为同一个（避免重名条目）', () async {
      await service.sync(testAccount('1', 'GitHub', 'me@github.com'));
      await service.sync(
        testAccount('2', 'GitHub', 'me@github.com', secret: 'GEZDGNBVGY3TQOJQ'),
      );

      final loaded = await service.load();
      expect(loaded.length, 1);
      expect(loaded.single.secret, 'GEZDGNBVGY3TQOJQ');
    });

    test('取消同步后 vault 里消失，未同步的账号状态为 notSynced', () async {
      final account = testAccount('1', 'GitHub', 'me@github.com');
      expect(service.stateOf(account, const []), VaultSyncState.notSynced);

      await service.sync(account);
      expect(await service.unlink(account), isTrue);

      final loaded = await service.load();
      expect(loaded, isEmpty);
      expect(service.stateOf(account, loaded), VaultSyncState.notSynced);
      // 重复取消不会报错
      expect(await service.unlink(account), isFalse);
    });

    test('写入审计日志，actor 标记为 app', () async {
      final account = testAccount('1', 'GitHub', 'me@github.com');
      await service.sync(account);
      await service.unlink(account);

      final entries = await AuditLog(service.paths.auditFile).tail(10);
      expect(entries.length, 2);
      expect(entries.first.action, 'add_account');
      expect(entries.first.actor, 'app');
      expect(entries.first.note, 'source=app');
      expect(entries.last.action, 'remove_account');
    });

    test('vault 目录与文件权限为 600/700', () async {
      await service.sync(testAccount('1', 'GitHub', 'me@github.com'));
      final mode = File(service.vaultFile).statSync().mode & 0x1FF;
      expect(mode, 0x180); // 0600
      final dirMode = Directory(dir.path).statSync().mode & 0x1FF;
      expect(dirMode, 0x1C0); // 0700
    });
  });
}
