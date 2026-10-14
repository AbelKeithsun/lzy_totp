library;

/// MCP server 实现已上移到共享内核（`packages/totp_core`），
/// 这样 Flutter App 也能用同一份工具实现起一个本机 MCP 服务。
///
/// 这里保留同名导出，CLI 与既有测试的 import 无需改动。
export 'package:totp_core/totp_core.dart'
    show McpHttpServer, McpServer, McpToolError;
