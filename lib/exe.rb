# frozen_string_literal: true

require 'mcp'
require 'obsidian_fetch'

# Parse arguments with validation
VALID_TRANSPORTS = %w[stdio streamable-http].freeze
DEFAULT_TRANSPORT = 'stdio'
DEFAULT_PORT = 9292

transport_type = DEFAULT_TRANSPORT
port = DEFAULT_PORT
vault_paths = []

i = 0
while i < ARGV.length
  arg = ARGV[i]
  case arg
  when '--help', '-h'
    puts "Usage: obsidian_fetch [vault_path] [--transport {stdio|streamable-http}] [--port PORT]"
    puts ""
    puts "Options:"
    puts "  --transport {stdio|streamable-http}  Transport type (default: stdio)"
    puts "    stdio:            Standard I/O transport for local MCP clients"
    puts "    streamable-http:  Streamable HTTP transport (MCP spec latest)"
    puts ""
    puts "  --port PORT              HTTP port for streamable-http transport (default: 9292)"
    puts ""
    puts "Examples:"
    puts "  obsidian_fetch /path/to/vault"
    puts "  obsidian_fetch /path/to/vault --transport streamable-http"
    puts "  obsidian_fetch /path/to/vault --transport streamable-http --port 3000"
    exit 0
  when '--transport'
    if i + 1 >= ARGV.length
      STDERR.puts "Error: --transport requires an argument (stdio or sse)"
      exit 1
    end
    transport_type = ARGV[i + 1]
    unless VALID_TRANSPORTS.include?(transport_type)
      STDERR.puts "Error: Invalid transport '#{transport_type}'. Must be one of: #{VALID_TRANSPORTS.join(', ')}"
      exit 1
    end
    i += 2 # Skip the next argument (transport type)
  when '--port'
    if i + 1 >= ARGV.length
      STDERR.puts "Error: --port requires a numeric argument"
      exit 1
    end
    port_val = ARGV[i + 1]
    unless port_val =~ /^\d+$/
      STDERR.puts "Error: --port must be a positive integer"
      exit 1
    end
    port = port_val.to_i
    unless port > 0 && port <= 65535
      STDERR.puts "Error: --port must be between 1 and 65535"
      exit 1
    end
    i += 2 # Skip the next argument (port value)
  else
    vault_paths << arg
    i += 1
  end
end

# Validate vault paths
if vault_paths.empty?
  STDERR.puts "Error: At least one vault path is required"
  STDERR.puts "Run with --help for usage information"
  exit 1
end

vault_paths.each do |path|
  unless File.directory?(path)
    STDERR.puts "Error: Vault path '#{path}' does not exist or is not a directory"
    exit 1
  end
end

# Obsidian Vaultの初期化
$vault = ObsidianFetch::Vault.new(vault_paths)
STDERR.puts "Found #{$vault.notes.size} notes"
STDERR.puts "Found #{$vault.links_by_file_name.size} links and #{$vault.links_by_file_path.size} files linked by notes"
STDERR.puts "Transport type: #{transport_type}"
STDERR.puts "Port: #{port}" if transport_type == 'streamable-http'

# readツールの定義
class ReadTool < MCP::Tool
  description "Read a note from Obsidian vault. If multiple notes with the same name are found, all will be shown."
  input_schema(
    properties: {
      name: { type: "string", description: "Note name to read" }
    },
    required: ["name"]
  )

  def self.call(name:)
    # 名前が文字列でない場合
    return MCP::Tool::Response.new([{ type: "text", text: "Name must be a string" }]) unless name.is_a?(String)

    # Vaultからノートを読み取る
    result = $vault.tool_read(name)
    MCP::Tool::Response.new([{ type: "text", text: result }])
  end
end

# listツールの定義
class ListTool < MCP::Tool
  description "Search for files with matching names partially."
  input_schema(
    properties: {
      name: { type: "string", description: "Note name to search" }
    },
    required: ["name"]
  )

  def self.call(name:)
    # 名前が文字列でない場合
    return MCP::Tool::Response.new([{ type: "text", text: "Name must be a string" }]) unless name.is_a?(String)

    # Vaultからノートを検索
    result = $vault.tool_list(name)
    MCP::Tool::Response.new([{ type: "text", text: result }])
  end
end

# MCPサーバーの初期化
server = MCP::Server.new(
  name: "obsidian-fetch",
  version: "0.1.0",
  tools: [ReadTool, ListTool],
)

# トランスポートを選択してサーバーを起動
case transport_type
when 'streamable-http'
  require 'puma'
  require 'rack'

  # Streamable HTTP トランスポートを使用してサーバーを起動
  transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)

  # PumaでRack appとして起動
  $stdout.sync = true
  $stderr.sync = true

  server_obj = Puma::Server.new(transport) do
    max_threads 16
    min_threads 1
  end
  server_obj.add_tcp_listener "0.0.0.0", port

  STDERR.puts "Streamable HTTP transport started on http://localhost:#{port}"
  STDERR.puts "Press Ctrl+C to stop"

  # サーバーを起動してメインプロセスをブロックする
  server_thread = server_obj.run
  server_thread.join
when 'stdio'
  # Stdioトランスポートを使用してサーバーを起動
  transport = MCP::Server::Transports::StdioTransport.new(server)
  transport.open
else
  STDERR.puts "Unknown transport type: #{transport_type}. Supported: stdio, sse"
  exit 1
end