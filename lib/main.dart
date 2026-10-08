import 'package:flutter/material.dart';

import 'pages/account_list_page.dart';
import 'services/storage_service.dart';

void main() {
  runApp(const TotpApp());
}

class TotpApp extends StatelessWidget {
  const TotpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOTP 验证器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: AccountListPage(storage: StorageService()),
    );
  }
}
