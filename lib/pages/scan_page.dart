import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/account.dart';

/// 扫码页：识别 otpauth:// 二维码，成功后 pop 返回账户
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final account = TotpAccount.fromOtpAuthUri(raw);
      if (account != null) {
        _handled = true;
        Navigator.of(context).pop(account);
        return;
      }
      // 是二维码但不是 TOTP 链接
      if (mounted) setState(() => _error = '不是有效的 TOTP 二维码');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码添加'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: '闪光灯',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // 中间取景框
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            child: Text(
              _error ?? '对准账户二维码即可自动添加',
              style: TextStyle(
                color: _error != null
                    ? Theme.of(context).colorScheme.error
                    : Colors.white,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
