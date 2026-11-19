import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/totp_service.dart';
import '../utils/platform_utils.dart';

/// 手动添加 / 编辑账户页。
///
/// - 新增：账户名与密钥必填（带 `*` 标识）；
/// - 编辑：传入 [initial] 与 `editing: true`，保存时保留原 id 与 AI 权限；
/// - 扫码后若二维码里没有账户名，也会带着 [initial] 进到这里补全。
class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key, this.initial, this.editing = false});

  /// 预填账号：编辑已有账号，或扫码后补全信息
  final TotpAccount? initial;

  /// 是否为「编辑已有账号」（只影响文案）
  final bool editing;

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _issuerController;
  late final TextEditingController _labelController;
  late final TextEditingController _secretController;
  late final TextEditingController _noteController;
  late final TextEditingController _recoveryController;
  late final TextEditingController _counterController;
  late int _digits;
  late int _period;
  late String _algorithm;

  /// `totp`（按时间）或 `hotp`（按计数器）
  late String _type;

  /// 可选有效期（本地时区当天 23:59:59 结束）
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _issuerController = TextEditingController(text: initial?.issuer ?? '');
    _labelController = TextEditingController(text: initial?.label ?? '');
    _secretController = TextEditingController(text: initial?.secret ?? '');
    _noteController = TextEditingController(text: initial?.note ?? '');
    _recoveryController = TextEditingController(
      text: (initial?.recoveryCodes ?? const <String>[]).join('\n'),
    );
    _counterController =
        TextEditingController(text: '${initial?.counter ?? 0}');
    _digits = initial?.digits ?? 6;
    _period = initial?.period ?? 30;
    _algorithm = initial?.algorithm ?? 'SHA1';
    _type = initial?.type ?? TotpAccount.typeTotp;
    _expiresAt = initial?.expiresAtTime;
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _labelController.dispose();
    _secretController.dispose();
    _noteController.dispose();
    _recoveryController.dispose();
    _counterController.dispose();
    super.dispose();
  }

  bool get _isHotp => _type == TotpAccount.typeHotp;

  String? _validateLabel(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return '请填写账户名，用于区分不同系统 / 环境';
    }
    return null;
  }

  String? _validateSecret(String? value) {
    final secret = (value ?? '').toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (secret.isEmpty) return '请输入密钥';
    if (!RegExp(r'^[A-Z2-7]+=*$').hasMatch(secret)) {
      return '密钥应为 Base32 格式（字母 A-Z 和数字 2-7）';
    }
    // 试算一次，确认密钥可被正常解码
    try {
      TotpService.codeFor(TotpAccount(
        id: 'tmp',
        issuer: '',
        label: '',
        secret: secret,
      ));
    } catch (_) {
      return '密钥无法解码，请检查是否完整';
    }
    return null;
  }

  /// 解析恢复码输入：每行一个，去掉空行与重复项。
  List<String> _parseRecoveryCodes() => TotpAccount.normalizeRecoveryCodes(
        _recoveryController.text.split('\n'),
      );

  String? _validateRecoveryCodes(String? value) {
    final codes = TotpAccount.normalizeRecoveryCodes(
      (value ?? '').split('\n'),
    );
    if (codes.isEmpty) return null; // 可选
    if (codes.length > 20) {
      return '恢复码最多 20 个（多了通常是粘贴错了）';
    }
    final bad = codes.where((c) => !TotpAccount.isValidRecoveryCode(c));
    if (bad.isNotEmpty) {
      return '恢复码「${bad.first}」格式不对：应为字母 / 数字（可含 - 或 _），至少 4 位';
    }
    return null;
  }

  String? _validateCounter(String? value) {
    if (!_isHotp) return null;
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 0) return '计数器应为非负整数';
    return null;
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final base = widget.initial;
    final account = TotpAccount(
      // 编辑时保留原 id（列表按 id 定位，AI vault 也已关联）
      id: base?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      issuer: _issuerController.text.trim(),
      label: _labelController.text.trim(),
      secret:
          _secretController.text.toUpperCase().replaceAll(RegExp(r'\s'), ''),
      digits: _digits,
      period: _period,
      algorithm: _algorithm,
      type: _type,
      counter: _isHotp ? (int.tryParse(_counterController.text.trim()) ?? 0) : 0,
      // 创建时间只在首次录入时确定，编辑不覆盖
      createdAt: base?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      lastUsedAt: base?.lastUsedAt,
      // 过期日存当天 23:59:59，避免「当天零点就过期」的意外
      expiresAt: _expiresAt == null
          ? null
          : DateTime(_expiresAt!.year, _expiresAt!.month, _expiresAt!.day, 23,
                  59, 59)
              .millisecondsSinceEpoch,
      aiAllowed: base?.aiAllowed ?? TotpAccount.defaultAiAllowed,
      note: _noteController.text.trim(),
      recoveryCodes: _parseRecoveryCodes(),
      // 已用掉的恢复码留档：编辑页只维护「还没用过」的那些
      usedRecoveryCodes: base?.usedRecoveryCodes ?? const <String>[],
    );
    Navigator.of(context).pop(account);
  }

  /// 选失效日期（可选）；选中的是「到期日当天」，当天仍然有效
  Future<void> _pickExpiresAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 90)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
      helpText: '选择失效日期（到期后仅提醒，不阻止取码）',
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateTime(DateTime d) =>
      '${_formatDate(d)} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '编辑账户' : '手动添加')),
      // 主操作固定在屏幕底部：Scaffold 会给它留出位置，SnackBar 之类的底部浮层
      // 一律排在它上面，不会再出现「撤销」提示条压住「保存」按钮的情况。
      bottomNavigationBar: _SaveBar(
        label: editing ? '保存修改' : '保存',
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '带 * 的为必填项。账户名会显示在首页，用来区分不同系统 / 环境。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '账户名 *',
                hintText: '如 GitHub、公司 VPN、生产环境 Jenkins',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              // 编辑时的重点是改名字，直接聚焦这里
              autofocus: editing,
              validator: _validateLabel,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _issuerController,
              decoration: const InputDecoration(
                labelText: '发行方（可选）',
                hintText: '如 GitHub',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secretController,
              decoration: const InputDecoration(
                labelText: '密钥 *',
                hintText: 'Base32 格式，如 JBSW Y3DP EHPK 3PXP',
                border: OutlineInputBorder(),
              ),
              autocorrect: false,
              // 新增时先粘贴密钥，聚焦这里；编辑时聚焦账户名
              autofocus: !editing && AppPlatform.isDesktop,
              validator: _validateSecret,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '如：生产环境 / 测试环境、给哪台机器用',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _recoveryController,
              decoration: const InputDecoration(
                labelText: '恢复码（可选）',
                hintText: '每行一个，如\nabcd-efgh\n1234-5678',
                helperText: '网站给的备用码（一次性）：换手机 / 验证码器坏了时用它登录。'
                    '与密钥同样加密保存，不会展示给 AI。',
                helperMaxLines: 3,
                border: OutlineInputBorder(),
              ),
              // 一行一个，最多数十行
              minLines: 2,
              maxLines: 6,
              autocorrect: false,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              validator: _validateRecoveryCodes,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                helperText: 'TOTP 按时间（30 秒一变，绝大多数网站）；'
                    'HOTP 按计数器（用一次 +1，少数硬件令牌 / 银行类服务）',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: TotpAccount.typeTotp, child: Text('TOTP（按时间）')),
                DropdownMenuItem(
                    value: TotpAccount.typeHotp, child: Text('HOTP（按计数器）')),
              ],
              onChanged: (v) => setState(
                  () => _type = v ?? TotpAccount.typeTotp),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _digits,
                    decoration: const InputDecoration(
                        labelText: '位数', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 6, child: Text('6 位')),
                      DropdownMenuItem(value: 8, child: Text('8 位')),
                    ],
                    onChanged: (v) => setState(() => _digits = v ?? 6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _isHotp
                      ? TextFormField(
                          controller: _counterController,
                          decoration: const InputDecoration(
                            labelText: '计数器',
                            hintText: '0',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: _validateCounter,
                        )
                      : DropdownButtonFormField<int>(
                          initialValue: _period,
                          decoration: const InputDecoration(
                              labelText: '周期', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 30, child: Text('30 秒')),
                            DropdownMenuItem(value: 60, child: Text('60 秒')),
                          ],
                          onChanged: (v) => setState(() => _period = v ?? 30),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _algorithm,
              decoration: const InputDecoration(
                  labelText: '算法', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'SHA1', child: Text('SHA1（最常见）')),
                DropdownMenuItem(value: 'SHA256', child: Text('SHA256')),
                DropdownMenuItem(value: 'SHA512', child: Text('SHA512')),
              ],
              onChanged: (v) => setState(() => _algorithm = v ?? 'SHA1'),
            ),
            const SizedBox(height: 16),
            // 失效日期（可选）：到期只提醒，不阻止取码
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '失效日期（可选）',
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiresAt == null ? '未设置' : _formatDate(_expiresAt!),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  if (_expiresAt != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '清除失效日期',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _expiresAt = null),
                    ),
                  TextButton.icon(
                    onPressed: _pickExpiresAt,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_expiresAt == null ? '选择' : '修改'),
                  ),
                ],
              ),
            ),
            // 编辑时把「创建 / 最近取码」亮出来，新增时不显示（还没发生）
            if (editing && widget.initial != null) ...[
              const SizedBox(height: 12),
              Text(
                '创建于 ${widget.initial!.createdAtTime == null ? '—' : _formatDateTime(widget.initial!.createdAtTime!)}'
                ' · 最近取码 ${widget.initial!.lastUsedAtTime == null ? '从未' : _formatDateTime(widget.initial!.lastUsedAtTime!)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// 底部固定的主操作栏（保存 / 保存修改）。
///
/// - 固定在屏幕底部：Scaffold 给它留出空间后，SnackBar 等底部浮层会自动排在它**上面**，
///   「撤销」提示条再也不会压住「保存」按钮；
/// - 键盘弹起时（Android）整条栏顶到键盘上方，按钮始终露在外面、点得到。
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      // 键盘高度补在下面：按钮本身被顶到键盘上沿
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + keyboard),
      child: SafeArea(
        top: false,
        // 键盘已经占了下沿，此时不再重复留安全区
        bottom: keyboard == 0,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.check),
            label: Text(label),
          ),
        ),
      ),
    );
  }
}
