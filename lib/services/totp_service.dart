/// TOTP 计算已迁到共享内核 `packages/totp_core`，App / CLI / MCP server 共用一份实现。
///
/// 保留本文件是为了不破坏既有 import 路径（`package:lzy_totp/services/totp_service.dart`）。
library;

export 'package:totp_core/totp_core.dart' show TotpService;
