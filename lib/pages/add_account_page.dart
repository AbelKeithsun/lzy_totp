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
  late int _digits;
  late int _period;
  late String _algorithm;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _issuerController = TextEditingController(text: initial?.issuer ?? '');
    _labelController = TextEditingController(text: initial?.label ?? '');
    _secretController = TextEditingController(text: initial?.secret ?? '');
    _noteController = TextEditingController(text: initial?.note ?? '');
    _digits = initial?.digits ?? 6;
    _period = initial?.period ?? 30;
    _algorithm = initial?.algorithm ?? 'SHA1';
  }

  @override
  void dispose() {
    _issuerController.dispose();
    _labelController.dispose();
    _secretController.dispose();
    _noteController.dispose();
    super.dispose();
  }

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
      aiAllowed: base?.aiAllowed ?? TotpAccount.defaultAiAllowed,
      note: _noteController.text.trim(),
    );
    Navigator.of(context).pop(account);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? '编辑账户' : '手动添加')),
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
            const SizedBox(height: 24),
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
                  child: DropdownButtonFormField<int>(
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
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(editing ? '保存修改' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}
