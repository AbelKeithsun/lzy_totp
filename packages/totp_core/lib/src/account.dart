import 'dart:convert';

/// 一个 TOTP 账户（与 otpauth:// URI 一一对应）
class TotpAccount {
  TotpAccount({
    required this.id,
    required this.issuer,
    required this.label,
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
    this.aiAllowed = defaultAiAllowed,
    this.note = '',
  });

  /// 新增账号时是否默认允许 AI 取码。
  ///
  /// **默认放行**：AI 可直接取码；如需关闭个别账号用 `lzy-totp deny <名称>`。
  static const bool defaultAiAllowed = true;

  /// 唯一 ID（用于列表增删）
  final String id;

  /// 发行方，如 GitHub
  String issuer;

  /// 账户名，如 user@example.com
  String label;

  /// Base32 编码的密钥
  String secret;

  /// 验证码位数，常见 6
  int digits;

  /// 周期秒数，常见 30
  int period;

  /// SHA1 / SHA256 / SHA512
  String algorithm;

  /// 备注：给这个账号补充说明（如「生产环境 / 测试环境」「公司邮箱」）。
  ///
  /// 不是密钥，不参与取码，只用于区分同名或相似的账号；
  /// 会随 CLI / MCP 的元数据一起返回给 AI，便于它判断该用哪个账号。
  String note;

  /// 是否允许 AI / 自动化工具查询该账户的验证码。
  ///
  /// **默认 true（默认放行）**：新增账号即可被 AI 取码；
  /// 如要关闭某个账号，用 `lzy-totp deny <名称>`（或 MCP 的 `set_ai_allowed`）设为 false。
  bool aiAllowed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'issuer': issuer,
        'label': label,
        'secret': secret,
        'digits': digits,
        'period': period,
        'algorithm': algorithm,
        'aiAllowed': aiAllowed,
        'note': note,
      };

  factory TotpAccount.fromJson(Map<String, dynamic> json) => TotpAccount(
        id: json['id'] as String,
        issuer: json['issuer'] as String? ?? '',
        label: json['label'] as String? ?? '',
        secret: json['secret'] as String,
        digits: json['digits'] as int? ?? 6,
        period: json['period'] as int? ?? 30,
        algorithm: json['algorithm'] as String? ?? 'SHA1',
        aiAllowed: json['aiAllowed'] as bool? ?? defaultAiAllowed,
        note: json['note'] as String? ?? '',
      );

  static String encodeList(List<TotpAccount> accounts) =>
      jsonEncode(accounts.map((a) => a.toJson()).toList());

  static List<TotpAccount> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => TotpAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 解析 otpauth://totp/Issuer:account?secret=...&issuer=... 形式的二维码内容，
  /// 解析失败返回 null。
  static TotpAccount? fromOtpAuthUri(
    String raw, {
    String? id,
    bool aiAllowed = defaultAiAllowed,
  }) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'otpauth') return null;
    if (uri.host.toLowerCase() != 'totp') return null; // 暂不支持 hotp

    final secret =
        uri.queryParameters['secret']?.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (secret == null || secret.isEmpty) return null;
    if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(secret)) return null;

    // label 形如 "Issuer:account"，URL 解码后拆分
    final pathLabel = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
    String issuer = uri.queryParameters['issuer'] ?? '';
    String accountName = pathLabel;
    if (pathLabel.contains(':')) {
      final idx = pathLabel.indexOf(':');
      if (issuer.isEmpty) issuer = pathLabel.substring(0, idx);
      accountName = pathLabel.substring(idx + 1);
    }

    final algo = (uri.queryParameters['algorithm'] ?? 'SHA1').toUpperCase();
    const allowed = {'SHA1', 'SHA256', 'SHA512'};

    return TotpAccount(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      issuer: issuer,
      label: accountName,
      secret: secret,
      digits: int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6,
      period: int.tryParse(uri.queryParameters['period'] ?? '') ?? 30,
      algorithm: allowed.contains(algo) ? algo : 'SHA1',
      aiAllowed: aiAllowed,
    );
  }

  /// 显示用标题：Issuer (account)
  String get displayTitle {
    if (issuer.isEmpty) return label;
    if (label.isEmpty) return issuer;
    return '$issuer ($label)';
  }

  /// 判断某个用户输入的名字是否指向本账户（大小写不敏感）。
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return id.toLowerCase() == q ||
        issuer.toLowerCase() == q ||
        label.toLowerCase() == q ||
        displayTitle.toLowerCase() == q;
  }

  TotpAccount copyWith({
    String? id,
    String? issuer,
    String? label,
    String? secret,
    int? digits,
    int? period,
    String? algorithm,
    bool? aiAllowed,
    String? note,
  }) =>
      TotpAccount(
        id: id ?? this.id,
        issuer: issuer ?? this.issuer,
        label: label ?? this.label,
        secret: secret ?? this.secret,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        algorithm: algorithm ?? this.algorithm,
        aiAllowed: aiAllowed ?? this.aiAllowed,
        note: note ?? this.note,
      );
}
