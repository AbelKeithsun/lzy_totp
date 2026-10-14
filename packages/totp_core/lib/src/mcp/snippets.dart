/// 给不同 MCP 客户端的「粘进去就能用」配置片段。
///
/// App 设置页与 CLI `serve` 命令共用同一份文案，保证两边给出的地址与写法一致。
class McpClientSnippets {
  const McpClientSnippets(this.url);

  /// 形如 `http://127.0.0.1:45763/mcp/<token>`
  final String url;

  /// Claude Code：一行命令添加
  String get claudeCode => 'claude mcp add --transport http lzy_totp $url';

  /// Claude Code：移除
  String get claudeCodeRemove => 'claude mcp remove lzy_totp';

  /// 通用 JSON（Cursor / 支持 HTTP 传输的客户端）
  String get jsonConfig => '''{
  "mcpServers": {
    "lzy_totp": {
      "url": "$url"
    }
  }
}''';

  /// DSH（Cordis patch，streamable-http）
  String get dshYaml => '''- insert:
    - id: lzy-totp-mcp-http
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: lzy_totp
        transport: streamable-http
        url: $url''';

  /// 纯文本汇总（CLI 打印用）
  String get summary => '''
【Claude Code】添加：
$claudeCode
【Claude Code】移除：
$claudeCodeRemove

【通用 JSON】（Cursor 等支持 HTTP 传输的客户端）
$jsonConfig

【DSH】（追加到 \$DSH_HOME/cordis.patch.yml）
$dshYaml''';
}
