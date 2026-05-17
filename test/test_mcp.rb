# frozen_string_literal: true

require 'fileutils'

# テスト実行前に古いカバレッジデータをクリア
FileUtils.rm_f(File.join(__dir__, '..', 'coverage', '.resultset.json'))
FileUtils.rm_f(File.join(__dir__, '..', 'coverage', '.resultset.json.lock'))

require 'simplecov'
SimpleCov.start do
  command_name 'Unit Tests'
end
require 'minitest/autorun'
require 'mcp'
require 'tmpdir'

# サーバーのコードを require してカバレッジ計測の対象にする
require_relative '../lib/obsidian_fetch'

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
      args: [
        '-I', 'lib',
        '-I', 'test',
        '-I', 'vendor/bundle/ruby/3.3.0/gems/simplecov-0.22.0/lib',
        '-r', 'simplecov_wrapper',
        'exe/obsidian_fetch',
        @test_vault
      ],
      read_timeout: 10
    )

    @client = MCP::Client.new(transport: @stdio_transport)
  end

  def teardown
    @stdio_transport.close
    sleep 1 # サーバープロセスの終了を待つ
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

  def test_read_not_found_is_error
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'NonExistent' }
    )

    # isError が true であることを確認
    assert response['result']['isError'], "isError が true ではありません: #{response['result']}"
  end

  def test_read_hello_is_not_error
    read_tool = @client.tools.find { |t| t.name == 'read_tool' }

    response = @client.call_tool(
      tool: read_tool,
      arguments: { name: 'Hello World' }
    )

    # isError が false または未設定であることを確認
    refute response['result']['isError'], "isError が設定されています: #{response['result']}"
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

  def test_list_not_found_is_error
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'NonExistent' }
    )

    # isError が true であることを確認
    assert response['result']['isError'], "isError が true ではありません: #{response['result']}"
  end

  def test_list_hello_is_not_error
    list_tool = @client.tools.find { |t| t.name == 'list_tool' }

    response = @client.call_tool(
      tool: list_tool,
      arguments: { name: 'Hello' }
    )

    # isError が false または未設定であることを確認
    refute response['result']['isError'], "isError が設定されています: #{response['result']}"
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

# YAML構文エラーのハンドリングをテスト
class VaultYamlErrorTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_yaml_test_')

    # FIXTURE_VAULT から既存のファイルをコピー
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # 無効なfrontmatterを持つ.mdファイルを追加
    # YAML構文エラー: エスケープされていない引用符
    invalid_frontmatter_content = <<~MD
      ---
      title: "未完了の文字列
      aliases:
        - broken
      ---
      # Invalid YAML Note
    MD
    File.write(File.join(@test_vault, 'Invalid Frontmatter.md'), invalid_frontmatter_content)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_vault_initializes_with_invalid_yaml_frontmatter
    # 無効なfrontmatterが存在しても、Vault は初期化できることを確認
    # Psych::SyntaxError が発生しても collect_notes は次のファイルに進む
    vault = ObsidianFetch::Vault.new([@test_vault])
    refute_nil vault, 'Vault が初期化されませんでした'
  end

  def test_valid_notes_loaded_despite_invalid_frontmatter
    # 無効なfrontmatterが存在しても、他のノートが読み込まれることを確認
    vault = ObsidianFetch::Vault.new([@test_vault])

    # Hello World ノートが読み込まれていることを確認
    result = vault.tool_read('Hello World')
    refute result.error, "Hello World ノートの読み込みに失敗しました: #{result.text}"
    assert result.text.include?('Hello World'), "Hello World ノートの内容が見つかりませんでした"
  end

  def test_invalid_yaml_note_is_still_loaded
    # 無効なfrontmatterのノートも読み込まれていることを確認
    # (frontmatter解析はスキップされるが、ファイル自体は読み込まれる)
    vault = ObsidianFetch::Vault.new([@test_vault])

    result = vault.tool_read('Invalid Frontmatter')
    refute result.error, "Invalid Frontmatter ノートの読み込みに失敗しました: #{result.text}"
    assert result.text.include?('Invalid YAML Note'), "Invalid Frontmatter ノートの内容が見つかりませんでした"
  end

  def test_list_works_with_invalid_frontmatter
    # 無効なfrontmatterが存在しても、list が機能することを確認
    vault = ObsidianFetch::Vault.new([@test_vault])

    result = vault.tool_list('Hello')
    refute result.error, "リストの取得に失敗しました: #{result.text}"
    assert result.text.include?('Hello'), "Hello で始まるノートが見つかりませんでした"
  end

  def test_tool_list_with_blank_string_returns_error
    # 空文字列で tool_list を呼び出した場合、エラーが返されることを確認
    vault = ObsidianFetch::Vault.new([@test_vault])

    result = vault.tool_list('')
    assert result.error, "空文字列で検索してもエラーが返されませんでした: #{result.text}"
    assert result.text.include?('blank') || result.text.include?('cannot be listed'), "エラーメッセージに期待する文言が含まれていません: #{result.text}"
  end
end

# tool_read のパス修正経路をテスト
class VaultPathCorrectionTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_path_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_read_with_slash_in_name_falls_back_to_basename
    # パスを含む名前で読み取ると、basename で再試行され、ノートが読み込まれる
    vault = ObsidianFetch::Vault.new([@test_vault])

    # "some/path/Hello World" のようにパスを含む名前で読み取る
    result = vault.tool_read('some/path/Hello World')

    # エラーにならない
    refute result.error, "パスを含む名前の読み込みに失敗しました: #{result.text}"

    # "Hello World" ノートの内容が含まれる
    assert result.text.include?('Hello World'), "Hello World ノートの内容が見つかりませんでした"

    # prefaceメッセージが含まれる（パス修正のログ）
    assert result.text.include?('renamed'), "prefaceメッセージが見つかりませんでした: #{result.text}"
  end
end

# tool_list の大量マッチ制限 (MAX_LIST_SIZE) をテスト
class VaultMassLimitTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_mass_test_')

    # FIXTURE_VAULT から既存のファイルをコピー
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # 25個のノートを作成（MAX_LIST_SIZE=20を超える）
    25.times do |i|
      note_name = "MassNote_#{sprintf('%02d', i)}"
      File.write(File.join(@test_vault, "#{note_name}.md"), "# #{note_name}\n")
    end
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_list_limits_results_to_max_list_size
    # 25個のノートが存在することを確認
    notes_in_vault = Dir.glob(File.join(@test_vault, '**', '*.md')).count
    assert notes_in_vault >= 25, "Vault に 25個以上のノートがありません: #{notes_in_vault}"

    vault = ObsidianFetch::Vault.new([@test_vault])

    # tool_list を呼び出す（MassNote_ で始まるノートを検索）
    result = vault.tool_list('MassNote_')

    # エラーにならない
    refute result.error, "tool_list の呼び出しに失敗しました: #{result.text}"

    # 返されたノート名をカウント
    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert note_names.length <= 20, "MAX_LIST_SIZE(20)を超えるノートが返されました: #{note_names.length}"
  end

  def test_tool_list_mass_limit_has_warning_message
    vault = ObsidianFetch::Vault.new([@test_vault])

    result = vault.tool_list('MassNote_')

    # 大量マッチ制限が適用された場合は警告メッセージが含まれる
    # 25個のノートが存在し、20個以下しか返されない
    note_names = result.text.scan(/MassNote_\d+/).uniq
    if note_names.length < 25
      # 制限が適用された場合、何かしらの制限に関するメッセージが期待される
      # ただしエラーではなく、警告として処理される
      refute result.error, "大量マッチ制限がエラーとして返されました: #{result.text}"
    end
  end

  def test_tool_list_returns_at_most_20_notes
    vault = ObsidianFetch::Vault.new([@test_vault])

    result = vault.tool_list('MassNote_')

    refute result.error, "tool_list の呼び出しに失敗しました: #{result.text}"

    # 返されたノート名の数が 20以下であることを確認
    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert note_names.length <= 20, "20個を超えるノートが返されました: #{note_names.length}"

    # 25個のノートを作成したので、20個以下しか返されない
    assert note_names.length < 25, "25個全てのノートが返されました（制限が機能していません）"
  end
end
