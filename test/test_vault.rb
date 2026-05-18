# frozen_string_literal: true

require_relative 'shared_setup'

# YAML 構文エラーのハンドリングをテスト
class VaultYamlErrorTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_yaml_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # 無効な frontmatter を持つ.md ファイルを追加
    File.write(File.join(@test_vault, 'Invalid Frontmatter.md'), <<~MD)
      ---
      title: "未完了の文字列
      aliases:
        - broken
      ---
      # Invalid YAML Note
    MD
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_vault_handles_invalid_yaml_gracefully
    vault = ObsidianFetch::Vault.new([@test_vault])

    # 無効な frontmatter が存在しても Vault が初期化される
    refute_nil vault

    # 他のノートが正常に読み込まれる
    result = vault.tool_read('Hello World')
    refute result.error
    assert result.text.include?('Hello World')

    # 無効な frontmatter のノートも読み込まれる（frontmatter はスキップされる）
    result = vault.tool_read('Invalid Frontmatter')
    refute result.error
    assert result.text.include?('Invalid YAML Note')

    # list も機能する
    result = vault.tool_list('Hello')
    refute result.error
    assert result.text.include?('Hello')
  end
end

# 入力値のエラーハンドリングをテスト
class VaultBlankInputTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_blank_input_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_list_with_blank_string_returns_error
    vault = ObsidianFetch::Vault.new([@test_vault])
    result = vault.tool_list('')

    assert result.error
    assert result.text.include?('blank') || result.text.include?('cannot be listed')
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

  def test_tool_read_falls_back_to_basename_when_path_provided
    vault = ObsidianFetch::Vault.new([@test_vault])
    result = vault.tool_read('some/path/Hello World')

    refute result.error
    assert result.text.include?('Hello World')
    assert result.text.include?('renamed'), 'パス修正のログが含まれていない'
  end
end

# tool_list の大量マッチ制限 (MAX_LIST_SIZE) をテスト
class VaultMassLimitTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_mass_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # 25 個のノートを作成（MAX_LIST_SIZE=20 を超える）
    25.times do |i|
      note_name = "MassNote_#{sprintf('%02d', i)}"
      File.write(File.join(@test_vault, "#{note_name}.md"), "# #{note_name}\n")
    end
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_list_limits_results_to_max_list_size
    # 25 個のノートが存在することを確認
    notes_in_vault = Dir.glob(File.join(@test_vault, '**', '*.md')).count
    assert notes_in_vault >= 25

    vault = ObsidianFetch::Vault.new([@test_vault])
    result = vault.tool_list('MassNote_')

    refute result.error

    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert note_names.length <= 20, "MAX_LIST_SIZE(20) を超えるノートが返された: #{note_names.length}"
    assert note_names.length < 25, '25 個全てのノートが返された（制限が機能していない）'
    refute result.error, '大量マッチ制限がエラーとして返された'
  end
end

# リンク形式のテストをまとめてテスト
class VaultLinkFormatTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_link_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # 様々なリンク形式を含むノートを追加
    File.write(File.join(@test_vault, 'Has MD Link.md'), "# Has MD Link\n\nThis note has a [[Hello World.md]] link.\n")
    File.write(File.join(@test_vault, 'Has DisplayName Link.md'), "# Has DisplayName Link\n\nThis note has a [[Hello World|HW Note]] link.\n")
    File.write(File.join(@test_vault, 'Has Display Path Link.md'), "# Has Display Path Link\n\nThis note has a [Link to HW](Hello World) link.\n")
    File.write(File.join(@test_vault, 'Has Anchor Link.md'), "# Has Anchor Link\n\nThis note has a [[Hello World#Introduction]] link.\n")
    File.write(File.join(@test_vault, 'Has Block Link.md'), "# Has Block Link\n\nThis note has a [[Hello World^blockid]] link.\n")
    File.write(File.join(@test_vault, 'Has External Link.md'), "# Has External Link\n\nThis note has a [External Link](https://example.com) link.\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_md_extension_link_is_stripped
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), "'.md' が除去されてリンク先が登録されていない"
    refute vault.links_by_file_name.key?('Hello World.md'), "'.md' 付きで登録されてはいけない"

    backlinks = vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has MD Link') }
  end

  def test_displayname_link_uses_link_part_not_display
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), 'リンク部分 Hello World が登録されていない'
    refute vault.links_by_file_name.key?('HW Note'), '表示名 HW Note が登録されてはいけない'

    backlinks = vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has DisplayName Link') }
  end

  def test_displaypath_link_uses_path_not_display
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), 'パス部分 Hello World が登録されていない'
    refute vault.links_by_file_name.key?('Link to HW'), '表示名 Link to HW が登録されてはいけない'

    backlinks = vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has Display Path Link') }
  end

  def test_displaypath_link_with_md_extension
    # `[display](path.md)` 形式のリンクもテスト
    File.write(
      File.join(@test_vault, 'Has Display Path Link with MD.md'),
      "# Has Display Path Link with MD\n\nThis note has a [Link to HW](Hello World.md) link.\n"
    )

    vault = ObsidianFetch::Vault.new([@test_vault])
    assert vault.links_by_file_name.key?('Hello World'), "'.md' が除去されてリンク先が登録されていない"
  end

  def test_external_url_excluded
    vault = ObsidianFetch::Vault.new([@test_vault])

    refute vault.links_by_file_name.key?('example.com'), '外部リンクが登録されてはいけない'
    refute vault.links_by_file_name.key?('https'), '外部リンクのスキームが登録されてはいけない'
  end

  def test_anchor_link_is_stripped
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), '#アンカーが除去されてリンク先が登録されていない'
    refute vault.links_by_file_name.key?('Hello World#Introduction'), 'アンカー付きで登録されてはいけない'

    backlinks = vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has Anchor Link') }
  end

  def test_block_id_link_is_stripped
    # ^block_id 形式のリンクもテスト
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), '^blockid が除去されてリンク先が登録されていない'
  end
end

# tool_list のバックリンクフォールバックをテスト
class VaultBacklinkFallbackTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_backlink_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # リンク先が存在しないノートを追加
    File.write(File.join(@test_vault, 'Links to NonExistent.md'), "# Links to NonExistent\n\nThis note links to [[Phantom Note]].\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_list_backlink_fallback
    vault = ObsidianFetch::Vault.new([@test_vault])

    # "Phantom Note" はノート名として存在しない
    refute vault.notes.key?('Phantom Note'), 'Phantom Note がノート名として登録されてはいけない'
    # だが @links_by_file_name には存在する
    assert vault.links_by_file_name.key?('Phantom Note'), 'links_by_file_name に Phantom Note が登録されていない'

    result = vault.tool_list('Phantom Note')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('However, I found other notes linked to this note'), 'バックリンクのメッセージが表示されていない'
    assert result.text.include?('Links to NonExistent'), 'バックリンク先ノート名が表示されていない'
  end
end

# `tool_read` のバックリンク表示をテスト
class VaultToolReadBacklinkTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_backlink_display_test_')
    FileUtils.cp_r(FIXTURE_VAULT, @test_vault)

    # リンク元となるノートを追加（Hello World を参照する）
    File.write(File.join(@test_vault, 'Refers to Hello.md'), "# Refers to Hello\n\nThis note has a [[Hello World]] link.\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_read_shows_backlink
    vault = ObsidianFetch::Vault.new([@test_vault])

    assert vault.links_by_file_name.key?('Hello World'), 'links_by_file_name に Hello World が登録されていない'

    result = vault.tool_read('Hello World')

    refute result.error
    assert result.text.include?('Hello World')

    # バックリンクが表示される
    assert result.text.include?('Refers to Hello'), 'バックリンクが表示されていない'
    assert result.text.include?('linked by') || result.text.include?('This note is linked'), 'バックリンクのメッセージが表示されていない'

    # 複数のリンク元ノートが表示される
    assert result.text.include?('Links to HW'), '複数のバックリンクが表示されていない'
  end
end