import 'package:lzy_totp/models/account.dart';
import 'package:lzy_totp/services/storage_service.dart';

/// 内存版账户存储：跳过 Keychain，仅供 widget 测试使用。
class FakeStorage extends StorageService {
  FakeStorage([List<TotpAccount>? initial]) : _accounts = [...?initial];

  List<TotpAccount> _accounts;

  /// save 被调用的次数，用来断言「删除后确实落库」
  int saveCount = 0;

  List<TotpAccount> get accounts => List.unmodifiable(_accounts);

  @override
  Future<List<TotpAccount>> load() async => List.of(_accounts);

  @override
  Future<void> save(List<TotpAccount> accounts) async {
    _accounts = List.of(accounts);
    saveCount++;
  }
}

TotpAccount testAccount(
  String id,
  String issuer,
  String label, {
  String secret = 'JBSWY3DPEHPK3PXP',
}) =>
    TotpAccount(
      id: id,
      issuer: issuer,
      label: label,
      secret: secret,
    );
