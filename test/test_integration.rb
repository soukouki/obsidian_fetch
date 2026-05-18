# frozen_string_literal: true

require_relative 'shared_setup'

# MCP サーバーの結合テスト
#
# MCP クライアントから見て特に主要な機能が動いていることを確認するテストとして、
# 以下の項目を選定しています：
#
# - read_tool: ノートの読み取り
# - list_tool: ノートのリスト検索
# - isError: エラー状態の判定
# - バックリンクの表示
#
# 詳細な内部ロジックのテストはユニットテスト（test_vault.rb）で担当します。

class McpTest < Minitest::Test
  def setup
    # テスト用 Vault を作成
    @test_vault = Dir.mktmpdir('obsidian_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # MCP サーバーを stdio transport で起動
    @stdio_transport = MCP::Client::Stdio.new(
      command: 'ruby',
      args: [
        '-I', 'lib',
        '-I', 'test',
        '-I', 'vendor/bundle/ruby/3.3.0/gems/simplecov-0.22.0/lib',
        '-r', 'coverage_injector',
        'exe/obsidian_fetch',
        @test_vault
      ],
      read_timeout: 10
    )

    @client = MCP::Client.new(transport: @stdio_transport)
  end

  def teardown
    @stdio_transport.close
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_tool_success
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }
    refute_nil read_tool, 'read ツールが見つかりませんでした'

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'Hello World' }
    )

    content = response['result']['content'].first['text']
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello World'), "Hello World ノートが見つかりませんでした"
    refute response['result']['isError'], "isError が設定されています: #{response['result']}"
  end

  def test_read_tool_not_found
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'NonExistent' }
    )

    content = response['result']['content'].first['text']
    assert content.start_with?('Note not found:'), "エラーメッセージが期待どおりではありません: #{content}"
    assert response['result']['isError'], "isError が true ではありません: #{response['result']}"
  end

  def test_list_tool_success
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }
    refute_nil list_tool, 'list ツールが見つかりませんでした'

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'Hello' }
    )

    content = response['result']['content'].first['text']
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello'), "Hello で始まるノートが見つかりませんでした"
    refute response['result']['isError'], "isError が設定されています: #{response['result']}"
  end

  def test_list_tool_not_found
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'NonExistent' }
    )

    content = response['result']['content'].first['text']
    assert content.start_with?('Note not found:'), "エラーメッセージが期待どおりではありません: #{content}"
    assert response['result']['isError'], "isError が true ではありません: #{response['result']}"
  end

  def test_backlink
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    backlink_response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'Links to HW' }
    )

    content = backlink_response['result']['content'].first['text']
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello World'), "バックリンクが見つかりませんでした"
    refute backlink_response['result']['isError'], "isError が設定されています: #{backlink_response['result']}"
  end
end
