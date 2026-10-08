import 'package:test/test.dart';
import 'package:totp_core/totp_core.dart';

void main() {
  group('otpauth URI 解析', () {
    test('完整 URI', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/GitHub:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30',
      );
      expect(acc, isNotNull);
      expect(acc!.issuer, 'GitHub');
      expect(acc.label, 'user@example.com');
      expect(acc.secret, 'JBSWY3DPEHPK3PXP');
      expect(acc.digits, 6);
      expect(acc.period, 30);
      expect(acc.algorithm, 'SHA1');
      expect(acc.aiAllowed, isFalse, reason: '默认拒绝 AI 访问');
    });

    test('无 issuer 参数时从 label 前缀取', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/Google:bob@gmail.com?secret=JBSWY3DPEHPK3PXP',
      );
      expect(acc!.issuer, 'Google');
      expect(acc.label, 'bob@gmail.com');
    });

    test('secret 容忍空格与小写', () {
      final acc = TotpAccount.fromOtpAuthUri(
        'otpauth://totp/a:b?secret=jbsw y3dp ehpk 3pxp',
      );
      expect(acc!.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('非 otpauth / hotp / 缺 secret 均拒绝', () {
      expect(TotpAccount.fromOtpAuthUri('https://example.com'), isNull);
      expect(
        TotpAccount.fromOtpAuthUri('otpauth://hotp/a:b?secret=JBSWY3DPEHPK3PXP'),
        isNull,
      );
      expect(TotpAccount.fromOtpAuthUri('otpauth://totp/a:b'), isNull);
    });
  });

  group('TOTP 计算（RFC 6238 附录 B 测试向量，8 位）', () {
    TotpAccount acc(String seedBase32, String algo) => TotpAccount(
          id: 't',
          issuer: '',
          label: '',
          secret: seedBase32,
          digits: 8,
          algorithm: algo,
        );

    final at59 = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);

    test('SHA1, T=59s → 94287082', () {
      expect(
        TotpService.codeFor(
          acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 'SHA1'),
          now: at59,
        ),
        '94287082',
      );
    });

    test('SHA256, T=59s → 46119246', () {
      expect(
        TotpService.codeFor(
          acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA', 'SHA256'),
          now: at59,
        ),
        '46119246',
      );
    });

    test('SHA512, T=59s → 90693936', () {
      expect(
        TotpService.codeFor(
          acc(
              'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA',
              'SHA512'),
          now: at59,
        ),
        '90693936',
      );
    });

    test('剩余秒数与进度', () {
      final at10 = DateTime.fromMillisecondsSinceEpoch(10 * 1000, isUtc: true);
      expect(TotpService.remainingSeconds(period: 30, now: at10), 20);
      expect(TotpService.progress(period: 30, now: at10), closeTo(1 / 3, 1e-9));
    });
  });

  group('账户 JSON 序列化', () {
    test('往返一致（含 aiAllowed）', () {
      final original = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
        digits: 8,
        period: 60,
        algorithm: 'SHA256',
        aiAllowed: true,
      );
      final decoded =
          TotpAccount.decodeList(TotpAccount.encodeList([original])).single;
      expect(decoded.issuer, 'GitHub');
      expect(decoded.digits, 8);
      expect(decoded.algorithm, 'SHA256');
      expect(decoded.aiAllowed, isTrue);
    });

    test('旧数据无 aiAllowed 字段时按 false 处理', () {
      final decoded = TotpAccount.decodeList(
        '[{"id":"1","issuer":"G","label":"a","secret":"JBSWY3DPEHPK3PXP"}]',
      ).single;
      expect(decoded.aiAllowed, isFalse);
      expect(decoded.digits, 6);
    });
  });

  group('账户名匹配', () {
    test('支持 id / issuer / label / 组合标题，大小写不敏感', () {
      final a = TotpAccount(
        id: 'abc123',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
      );
      expect(a.matches('abc123'), isTrue);
      expect(a.matches('github'), isTrue);
      expect(a.matches('ME@X.COM'), isTrue);
      expect(a.matches('GitHub (me@x.com)'), isTrue);
      expect(a.matches('gitlab'), isFalse);
    });
  });
}
