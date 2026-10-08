import 'package:otp/otp.dart';

import 'account.dart';

/// 基于 otp 包的 TOTP 计算（RFC 6238）
class TotpService {
  /// 生成当前时刻的验证码；[now] 可注入便于测试
  static String codeFor(TotpAccount account, {DateTime? now}) {
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return OTP.generateTOTPCodeString(
      account.secret,
      time,
      length: account.digits,
      interval: account.period,
      algorithm: _algorithm(account.algorithm),
      // 兼容 Google Authenticator 系的 base32 补齐习惯
      isGoogle: true,
    );
  }

  /// 当前周期剩余秒数
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
