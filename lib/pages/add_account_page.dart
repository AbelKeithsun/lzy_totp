import 'package:flutter/material.dart';

import '../models/account.dart';
import '../services/totp_service.dart';
import '../utils/platform_utils.dart';

/// 手动添加账户页
class AddAccountPage extends StatefulWidget {
  const AddAccountPage({super.key});

  @override
  State<AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<AddAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _issuerController = TextEditingController();
  final _labelController = TextEditingController();
  final _secretController = TextEditingController();
  int _digits = 6;
  int _period = 30;
  String _algorithm = 'SHA1';

  @override
  void dispose() {
    _issuerController.dispose();
    _labelController.dispose();
    _secretController.dispose();
    super.dispose();
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
    final account = TotpAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      issuer: _issuerController.text.trim(),
      label: _labelController.text.trim(),
      secret:
          _secretController.text.toUpperCase().replaceAll(RegExp(r'\s'), ''),
      digits: _digits,
      period: _period,
      algorithm: _algorithm,
    );
    Navigator.of(context).pop(account);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手动添加')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _issuerController,
              decoration: const InputDecoration(
                labelText: '发行方（可选）',
                hintText: '如 GitHub',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: '账户名（可选）',
                hintText: '如 user@example.com',
                border: OutlineInputBorder(),
              ),
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
              // 桌面端打开即聚焦，Cmd+V 直接粘贴密钥
              autofocus: AppPlatform.isDesktop,
              validator: _validateSecret,
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
              label: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
