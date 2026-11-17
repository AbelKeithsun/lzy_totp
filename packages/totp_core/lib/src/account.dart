import 'dart:convert';

/// 一个 TOTP / HOTP 账户（与 otpauth:// URI 一一对应）
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
    this.type = typeTotp,
    this.counter = 0,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
    List<String>? recoveryCodes,
    List<String>? usedRecoveryCodes,
  })  : recoveryCodes = List<String>.of(recoveryCodes ?? const <String>[]),
        usedRecoveryCodes = List<String>.of(usedRecoveryCodes ?? const <String>[]);

  /// 新增账号时是否默认允许 AI 取码。
  ///
  /// **默认放行**：AI 可直接取码；如需关闭个别账号用 `lzy-totp deny <名称>`。
  static const bool defaultAiAllowed = true;

  /// 按时间变化的一次性密码（RFC 6238），绝大多数网站都是这种
  static const String typeTotp = 'totp';

  /// 按计数器变化的一次性密码（RFC 4226），少数硬件令牌 / 银行 U 盾类服务用它
  static const String typeHotp = 'hotp';

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

  /// 一次性密码的类型：`totp`（按时间，默认）或 `hotp`（按计数器）。
  ///
  /// 绝大多数网站用 TOTP；少数硬件令牌 / 银行类服务用 HOTP——
  /// 它没有「30 秒过期」，而是**每用一次计数器 +1**，服务端也同步 +1。
  String type;

  /// HOTP 的计数器（TOTP 账号下无意义，保持 0）。
  int counter;

  /// 账户录入时间（epoch 毫秒）。旧数据没有该字段，此时为 null（显示「—」）。
  int? createdAt;

  /// 最近一次取码（复制 / 生成）时间（epoch 毫秒）。
  ///
  /// App 侧在「复制验证码」时更新；CLI 侧在 `lzy-totp code` 时更新。
  int? lastUsedAt;

  /// 可选的有效期（epoch 毫秒）。到期后只做提醒（密钥可能已被网站轮换），
  /// 不阻止继续取码——毕竟轮换与否只有网站知道。
  int? expiresAt;

  /// 是否为 HOTP（按计数器）
  bool get isHotp => type == typeHotp;

  /// 是否已过有效期（未设置有效期时永远为 false）
  bool get isExpired {
    final at = expiresAt;
    if (at == null) return false;
    return at <= DateTime.now().millisecondsSinceEpoch;
  }

  /// 创建时间 / 最近取码时间 / 有效期的可读形式（未设置时为 null）
  DateTime? get createdAtTime =>
      createdAt == null ? null : DateTime.fromMillisecondsSinceEpoch(createdAt!);
  DateTime? get lastUsedAtTime => lastUsedAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(lastUsedAt!);
  DateTime? get expiresAtTime =>
      expiresAt == null ? null : DateTime.fromMillisecondsSinceEpoch(expiresAt!);

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

  /// 未使用的恢复码（备用码）。
  ///
  /// 恢复码是「第二道门」的钥匙：一旦泄露，攻击者可以绕过 TOTP 直接登录，
  /// 因此它和密钥同等敏感——落盘时必须加密，且**不通过任何 MCP 工具暴露给 AI**。
  ///
  /// 大多数网站给 8~10 个一次性恢复码，用掉一个就作废一个。
  List<String> recoveryCodes;

  /// 已用掉的恢复码（留档，便于一眼看出还剩几个能用）。
  List<String> usedRecoveryCodes;

  /// 还没用过的恢复码数量
  int get recoveryCodeCount => recoveryCodes.length;

  /// 是否录过恢复码（含已用完的情况）
  bool get hasRecoveryCodes =>
      recoveryCodes.isNotEmpty || usedRecoveryCodes.isNotEmpty;

  /// 归一化用户输入的恢复码：去掉首尾空白与空行，按原文去重（保留首次出现的写法）。
  ///
  /// 不改变大小写——不同站点的恢复码可能大小写敏感。
  static List<String> normalizeRecoveryCodes(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final code = item.trim();
      if (code.isEmpty) continue;
      if (seen.add(code)) out.add(code);
    }
    return out;
  }

  /// 校验单个恢复码是否像样（字母 / 数字，可含 `-` `_`，长度 ≥ 4）。
  ///
  /// 只做形状检查，不判断真假——真实与否只能由网站验证。
  static bool isValidRecoveryCode(String code) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_]{3,}$').hasMatch(code.trim());

  /// 把某个恢复码标记为「已用」，返回新账号（不动原对象）。
  TotpAccount markRecoveryCodeUsed(String code) {
    final target = code.trim();
    if (!recoveryCodes.contains(target)) return this;
    final next = copyWith(
      recoveryCodes: recoveryCodes.where((c) => c != target).toList(),
      usedRecoveryCodes: [...usedRecoveryCodes, target],
    );
    return next;
  }

  /// 删除某个恢复码（无论用没用过），返回新账号。
  TotpAccount removeRecoveryCode(String code) {
    final target = code.trim();
    if (!recoveryCodes.contains(target) && !usedRecoveryCodes.contains(target)) {
      return this;
    }
    return copyWith(
      recoveryCodes: recoveryCodes.where((c) => c != target).toList(),
      usedRecoveryCodes: usedRecoveryCodes.where((c) => c != target).toList(),
    );
  }

  /// 记一次「取码」：更新最近取码时间，返回新账号（不动原对象）。
  TotpAccount touch({DateTime? now}) => copyWith(
        lastUsedAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
      );

  /// HOTP 用掉一个码：计数器 +1，返回新账号；TOTP 原样返回。
  TotpAccount advanceCounter() => isHotp ? copyWith(counter: counter + 1) : this;

  Map<String, dynamic> toJson() => {
        'id': id,
        'issuer': issuer,
        'label': label,
        'secret': secret,
        'digits': digits,
        'period': period,
        'algorithm': algorithm,
        'type': type,
        'counter': counter,
        'createdAt': createdAt,
        'lastUsedAt': lastUsedAt,
        'expiresAt': expiresAt,
        'aiAllowed': aiAllowed,
        'note': note,
        'recoveryCodes': recoveryCodes,
        'usedRecoveryCodes': usedRecoveryCodes,
      };

  factory TotpAccount.fromJson(Map<String, dynamic> json) => TotpAccount(
        id: json['id'] as String,
        issuer: json['issuer'] as String? ?? '',
        label: json['label'] as String? ?? '',
        secret: json['secret'] as String,
        digits: json['digits'] as int? ?? 6,
        period: json['period'] as int? ?? 30,
        algorithm: json['algorithm'] as String? ?? 'SHA1',
        type: _type(json['type']),
        counter: (json['counter'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt(),
        lastUsedAt: (json['lastUsedAt'] as num?)?.toInt(),
        expiresAt: (json['expiresAt'] as num?)?.toInt(),
        aiAllowed: json['aiAllowed'] as bool? ?? defaultAiAllowed,
        note: json['note'] as String? ?? '',
        recoveryCodes: _stringList(json['recoveryCodes']),
        usedRecoveryCodes: _stringList(json['usedRecoveryCodes']),
      );

  /// 兼容旧数据（没有 type 字段 → totp）与手改的非法值。
  static String _type(Object? raw) {
    final value = raw?.toString().toLowerCase();
    return value == typeHotp ? typeHotp : typeTotp;
  }

  /// 兼容旧数据（没有恢复码字段）与手改过的 JSON（字段类型不标准）。
  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString()).toList();
  }

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
    final kind = uri.host.toLowerCase();
    if (kind != 'totp' && kind != 'hotp') return null;

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
      type: kind == 'hotp' ? typeHotp : typeTotp,
      // HOTP 的起始计数器由 URI 的 counter 参数给出（缺省 0）
      counter: kind == 'hotp'
          ? (int.tryParse(uri.queryParameters['counter'] ?? '') ?? 0)
          : 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
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
    String? type,
    int? counter,
    int? createdAt,
    int? lastUsedAt,
    int? expiresAt,
    bool? aiAllowed,
    String? note,
    List<String>? recoveryCodes,
    List<String>? usedRecoveryCodes,
  }) =>
      TotpAccount(
        id: id ?? this.id,
        issuer: issuer ?? this.issuer,
        label: label ?? this.label,
        secret: secret ?? this.secret,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        algorithm: algorithm ?? this.algorithm,
        type: type ?? this.type,
        counter: counter ?? this.counter,
        createdAt: createdAt ?? this.createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        aiAllowed: aiAllowed ?? this.aiAllowed,
        note: note ?? this.note,
        recoveryCodes: recoveryCodes ?? this.recoveryCodes,
        usedRecoveryCodes: usedRecoveryCodes ?? this.usedRecoveryCodes,
      );
}
