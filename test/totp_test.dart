import 'package:flutter_test/flutter_test.dart';
import 'package:lzy_totp/models/account.dart';
import 'package:lzy_totp/services/totp_service.dart';

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
    // RFC 6238 为不同算法规定了不同长度的 seed，以下为各自 base32 编码
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
      // seed = ASCII "12345678901234567890"（20 字节）
      final code = TotpService.codeFor(
        acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', 'SHA1'),
        now: at59,
      );
      expect(code, '94287082');
    });

    test('SHA256, T=59s → 46119246', () {
      // seed = ASCII "12345678901234567890123456789012"（32 字节）
      final code = TotpService.codeFor(
        acc('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA', 'SHA256'),
        now: at59,
      );
      expect(code, '46119246');
    });

    test('SHA512, T=59s → 90693936', () {
      // seed = ASCII "1234...（共 64 字节）
      final code = TotpService.codeFor(
        acc(
            'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA',
            'SHA512'),
        now: at59,
      );
      expect(code, '90693936');
    });

    test('剩余秒数与进度', () {
      final at10 = DateTime.fromMillisecondsSinceEpoch(10 * 1000, isUtc: true);
      expect(TotpService.remainingSeconds(period: 30, now: at10), 20);
      expect(TotpService.progress(period: 30, now: at10), closeTo(1 / 3, 1e-9));
    });
  });

  group('账户 JSON 序列化', () {
    test('往返一致', () {
      final original = TotpAccount(
        id: '1',
        issuer: 'GitHub',
        label: 'me@x.com',
        secret: 'JBSWY3DPEHPK3PXP',
        digits: 8,
        period: 60,
        algorithm: 'SHA256',
      );
      final decoded = TotpAccount.decodeList(TotpAccount.encodeList([original]));
      expect(decoded, hasLength(1));
      expect(decoded.single.issuer, 'GitHub');
      expect(decoded.single.digits, 8);
      expect(decoded.single.algorithm, 'SHA256');
    });
  });
}
