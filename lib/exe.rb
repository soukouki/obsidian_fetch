require 'mcp'
require 'obsidian_fetch'

# Obsidian Vaultの初期化
vault_paths = ARGV
vault = ObsidianFetch::Vault.new(vault_paths)
STDERR.puts "Found #{vault.notes.size} notes"
STDERR.puts "Found #{vault.links_by_file_name.size} links and #{vault.links_by_file_path.size} files linked by notes"

# MCPサーバーの初期化
server = MCP::Server.new(
  name: "obsidian-fetch",
  version: "0.1.0",
  tools: []
)

# "read"ツールの定義
class ReadTool < MCP::Tool
  description "Read a note from Obsidian vault. If multiple notes with the same name are found, all will be shown."
  input_schema(
    properties: {
      name: { type: "string", description: "Note name to read" }
    },
    required: ["name"]
  )

  def self.call(name:, server_context:)
    # 名前が文字列でない場合
    return MCP::Tool::Response.new([{ type: "text", text: "Name must be a string" }]) unless name.is_a?(String)

    # Vaultからノートを読み取る
    result = server_context[:vault].tool_read(name)
    MCP::Tool::Response.new([{ type: "text", text: result }])
  end
end

# "list"ツールの定義
class ListTool < MCP::Tool
  description "Search for files with matching names partially."
  input_schema(
    properties: {
      name: { type: "string", description: "Note name to search" }
    },
    required: ["name"]
  )

  def self.call(name:, server_context:)
    # 名前が文字列でない場合
    return MCP::Tool::Response.new([{ type: "text", text: "Name must be a string" }]) unless name.is_a?(String)

    # Vaultからノートを検索
    result = server_context[:vault].tool_list(name)
    MCP::Tool::Response.new([{ type: "text", text: result }])
  end
end

# サーバーにツールを登録
server.tools = [ReadTool, ListTool]

# サーバーコンテキストにVaultを追加
server.server_context = { vault: vault }

# Stdioトランスポートを使用してサーバーを起動
transport = MCP::Server::Transports::StdioTransport.new(server)
transport.open
