/// 账户模型已迁到共享内核 `packages/totp_core`，App / CLI / MCP server 共用一份实现。
///
/// 保留本文件是为了不破坏既有 import 路径（`package:lzy_totp/models/account.dart`）。
library;

export 'package:totp_core/totp_core.dart' show TotpAccount;
