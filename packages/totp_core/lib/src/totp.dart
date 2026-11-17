import 'package:otp/otp.dart';

import 'account.dart';

/// 一次性密码计算：TOTP（RFC 6238）+ HOTP（RFC 4226）
class TotpService {
  /// 生成当前验证码。
  ///
  /// - `totp`：按 [now]（缺省当前时刻）取时间片；
  /// - `hotp`：按账号里的 [TotpAccount.counter] 取码，**不会**自动 +1
  ///   （什么时候 +1 由调用方决定：App 在复制后、CLI 在取码后）。
  static String codeFor(TotpAccount account, {DateTime? now}) {
    if (account.isHotp) {
      return OTP.generateHOTPCodeString(
        account.secret,
        account.counter,
        length: account.digits,
        algorithm: _algorithm(account.algorithm),
        // 兼容 Google Authenticator 系的 base32 补齐习惯
        isGoogle: true,
      );
    }
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return OTP.generateTOTPCodeString(
      account.secret,
      time,
      length: account.digits,
      interval: account.period,
      algorithm: _algorithm(account.algorithm),
      isGoogle: true,
    );
  }

  /// 当前周期剩余秒数（HOTP 没有周期概念，调用方应自行跳过）
  static int remainingSeconds({int period = 30, DateTime? now}) {
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return period - (seconds % period);
  }

  /// 当前周期已过去比例（0.0 ~ 1.0），用于倒计时圆环
  static double progress({int period = 30, DateTime? now}) {
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return (seconds % period) / period;
  }

  /// 当前周期结束时间
  static DateTime expiresAt({int period = 30, DateTime? now}) {
    final now2 = now ?? DateTime.now();
    final remaining = remainingSeconds(period: period, now: now2);
    return now2.add(Duration(seconds: remaining));
  }

  static Algorithm _algorithm(String name) {
    switch (name.toUpperCase()) {
      case 'SHA256':
        return Algorithm.SHA256;
      case 'SHA512':
        return Algorithm.SHA512;
      default:
        return Algorithm.SHA1;
    }
  }
}
