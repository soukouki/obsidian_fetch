# frozen_string_literal: true

require 'minitest/autorun'
require 'mcp'
require 'tmpdir'
require 'fileutils'

# テスト設定
PROJECT_ROOT = File.dirname(__dir__)
FIXTURE_VAULT = File.join(PROJECT_ROOT, 'test', 'fixtures', 'test_vault')

# MCP サーバーの結合テスト
class McpTest < Minitest::Test
  def setup
    # テスト用 Vault を作成
    @test_vault = Dir.mktmpdir('obsidian_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # MCP サーバーを stdio transport で起動
    @stdio_transport = MCP::Client::Stdio.new(
      command: 'ruby',
      args: ['-I', 'lib', 'exe/obsidian_fetch', @test_vault],
      read_timeout: 10
    )

    @client = MCP::Client.new(transport: @stdio_transport)
  end

  def teardown
    @stdio_transport.close
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_hello_world
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }
    refute_nil read_tool, 'read ツールが見つかりませんでした'

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'Hello World' }
    )

    content = response['result']['content'].first['text']
    # エラーメッセージではなく、ノートの中身が含まれていることを確認
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello World'), "Hello World ノートが見つかりませんでした"
  end

  def test_read_not_found
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'NonExistent' }
    )

    content = response['result']['content'].first['text']
    assert content.start_with?('Note not found:'), "エラーメッセージが期待どおりではありません: #{content}"
  end

  def test_list_hello
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }
    refute_nil list_tool, 'list ツールが見つかりませんでした'

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'Hello' }
    )

    content = response['result']['content'].first['text']
    # エラーメッセージではなく、ノート名が含まれていることを確認
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello'), "Hello で始まるノートが見つかりませんでした"
  end

  def test_list_not_found
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'NonExistent' }
    )

    content = response['result']['content'].first['text']
    assert content.start_with?('Note not found:'), "エラーメッセージが期待どおりではありません: #{content}"
  end

  def test_backlink
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    backlink_response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'Links to HW' }
    )

    content = backlink_response['result']['content'].first['text']
    # エラーメッセージではなく、ノートの中身が含まれていることを確認
    refute content.start_with?('Note not found:'), "ノートが見つかりませんでした: #{content}"
    assert content.include?('Hello World'), "バックリンクが見つかりませんでした"
  end
end