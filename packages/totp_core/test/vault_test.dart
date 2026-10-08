import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:totp_core/totp_core.dart';

void main() {
  late Directory tmp;
  late TotpPaths paths;
  late VaultStore vault;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('totp_core_test_');
    paths = TotpPaths(tmp.path);
    vault = VaultStore(paths: paths);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  TotpAccount account({bool aiAllowed = false, String secret = 'JBSWY3DPEHPK3PXP'}) =>
      TotpAccount(
        id: 'id-1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: secret,
        digits: 6,
        period: 30,
        algorithm: 'SHA1',
        aiAllowed: aiAllowed,
      );

  group('加密 vault', () {
    test('vault 不存在时返回空列表，且不创建任何文件', () async {
      expect(await vault.load(), isEmpty);
      expect(await File(paths.vaultFile).exists(), isFalse);
      expect(await File(paths.keyFile).exists(), isFalse);
    });

    test('保存后往返一致', () async {
      await vault.save([account(aiAllowed: true)]);
      final loaded = (await vault.load()).single;
      expect(loaded.issuer, 'GitHub');
      expect(loaded.secret, 'JBSWY3DPEHPK3PXP');
      expect(loaded.aiAllowed, isTrue);
    });

    test('密钥在磁盘上是密文，明文不出现在文件里', () async {
      const secret = 'JBSWY3DPEHPK3PXP';
      await vault.save([account()]);
      final raw = await File(paths.vaultFile).readAsString();
      expect(raw.contains(secret), isFalse, reason: '明文密钥不得落盘');
      expect(raw.contains('enc:v1:'), isTrue, reason: '密钥字段应为密文');
      // 但元数据仍需可读，便于 list 操作
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect((json['accounts'] as List).first['issuer'], 'GitHub');
    });

    test('每次保存使用不同 nonce（相同明文密文不同）', () async {
      await vault.save([account()]);
      final first = await File(paths.vaultFile).readAsString();
      await vault.save([account()]);
      final second = await File(paths.vaultFile).readAsString();
      expect(first == second, isFalse);
    });

    test('vault 与密钥文件权限为 600', () async {
      await vault.save([account()]);
      expect(await describePermissions(paths.vaultFile), '600');
      expect(await describePermissions(paths.keyFile), '600');
    });

    test('密钥文件丢失时报 VaultError 而不是返回空/崩溃', () async {
      await vault.save([account()]);
      await File(paths.keyFile).delete();
      expect(
        () => vault.load(),
        throwsA(isA<VaultError>().having(
            (e) => e.message, 'message', contains('密钥文件缺失'))),
      );
    });

    test('密钥被换掉后解密失败报 VaultError', () async {
      await vault.save([account()]);
      await File(paths.keyFile).writeAsString(base64Encode(List.filled(32, 7)));
      expect(() => vault.load(), throwsA(isA<VaultError>()));
    });

    test('update 事务：读改写一次完成', () async {
      await vault.save([account()]);
      await vault.update((accounts) async {
        accounts.single.aiAllowed = true;
        return null;
      });
      expect((await vault.load()).single.aiAllowed, isTrue);
    });
  });

  group('AI 访问策略：默认拒绝', () {
    test('未标记的账户被拒绝', () {
      final acc = account(aiAllowed: false);
      expect(AiAccessPolicy.allows(acc), isFalse);
      expect(AiAccessPolicy.denialReason(acc), contains('未标记为允许 AI 访问'));
    });

    test('显式放行后才允许', () {
      expect(AiAccessPolicy.allows(account(aiAllowed: true)), isTrue);
      expect(AiAccessPolicy.denialReason(account(aiAllowed: true)), isNull);
    });
  });

  group('审计日志', () {
    test('追加写入并可读取最近记录', () async {
      final audit = AuditLog(paths.auditFile);
      await audit.append(AuditEntry(action: 'generate_totp', result: 'ok', account: 'GitHub'));
      await audit.append(AuditEntry(
          action: 'generate_totp', result: 'denied', account: 'Bank', actor: 'mcp'));

      final tail = await audit.tail(10);
      expect(tail, hasLength(2));
      expect(tail.first.result, 'ok');
      expect(tail.last.result, 'denied');
      expect(tail.last.actor, 'mcp');
      expect(await describePermissions(paths.auditFile), '600');
    });

    test('tail 只返回最近 N 条', () async {
      final audit = AuditLog(paths.auditFile);
      for (var i = 0; i < 5; i++) {
        await audit.append(AuditEntry(action: 'a$i', result: 'ok'));
      }
      final tail = await audit.tail(2);
      expect(tail.map((e) => e.action), ['a3', 'a4']);
    });
  });
}
