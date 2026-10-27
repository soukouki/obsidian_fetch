# frozen_string_literal: true

require_relative 'shared_setup'

# YAML 構文エラーのハンドリングをテスト
class VaultYamlErrorTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_yaml_test_')
    copy_fixture_vault(@test_vault)

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
    real_stdout = $stdout
    $stdout = StringIO.new
    begin
      vault = ObsidianFetch::VaultManager.new([@test_vault])

      # 無効な frontmatter が存在しても Vault が初期化される
      refute_nil vault.vault

      # 他のノートが正常に読み込まれる
      result = ObsidianFetch.read_note(vault.vault, 'Hello World')
      refute result.error
      assert result.text.include?('Hello World')

      # 無効な frontmatter のノートも読み込まれる（frontmatter はスキップされる）
      result = ObsidianFetch.read_note(vault.vault, 'Invalid Frontmatter')
      refute result.error
      assert result.text.include?('Invalid YAML Note')

      # list も機能する
      result = ObsidianFetch.list_notes(vault.vault, 'Hello')
      refute result.error
      assert result.text.include?('Hello')
    ensure
      $stdout = real_stdout
    end
  end
end

# 入力値のエラーハンドリングをテスト
class VaultBlankInputTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_blank_input_test_')
    copy_fixture_vault(@test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_tool_list_with_blank_string_returns_error
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, '')

    assert result.error
    assert result.text.include?('blank') || result.text.include?('cannot be listed')
  end
end

# read_note のパス修正経路をテスト
class VaultPathCorrectionTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_path_test_')
    copy_fixture_vault(@test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_note_falls_back_to_basename_when_path_provided
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'some/path/Hello World')

    refute result.error
    assert result.text.include?('Hello World')
    assert result.text.include?('renamed'), 'パス修正のログが含まれていない'
  end
end

# list_notes の大量マッチ制限 (MAX_LIST_SIZE) をテスト
class VaultMassLimitTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_mass_test_')
    copy_fixture_vault(@test_vault)

    # 25 個のノートを作成（MAX_LIST_SIZE=20 を超える）
    25.times do |i|
      note_name = "MassNote_#{sprintf('%02d', i)}"
      File.write(File.join(@test_vault, "#{note_name}.md"), "# #{note_name}\n")
    end
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_list_notes_limits_results_to_max_list_size
    # 25 個のノートが存在することを確認
    notes_in_vault = Dir.glob(File.join(@test_vault, '**', '*.md')).count
    assert notes_in_vault >= 25

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'MassNote_')

    refute result.error

    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert note_names.length <= 20, "MAX_LIST_SIZE(20) を超えるノートが返された: #{note_names.length}"
    assert note_names.length < 25, '25 個全てのノートが返された（制限が機能していない）'
    refute result.error, '大量マッチ制限がエラーとして返された'
  end

  def test_list_notes_honors_the_given_limit
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'MassNote_', limit: 10)

    refute result.error
    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert_equal 10, note_names.length, "limit(10) と異なる件数が返された: #{note_names.length}"
  end

  def test_list_notes_returns_all_matches_when_limit_is_greater_than_matches
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'MassNote_', limit: 30)

    refute result.error
    note_names = result.text.scan(/MassNote_\d+/).uniq
    assert_equal 25, note_names.length, "マッチした 25 件全てが返されなかった: #{note_names.length}"
  end

  def test_list_notes_reports_the_total_number_of_matches
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'MassNote_', limit: 10)

    assert result.text.include?('25 notes matched'), "マッチ総件数が応答に含まれていない: #{result.text}"
    assert result.text.include?('I will show you 10 of them.'), "切られていることが応答から読み取れない: #{result.text}"
  end

  def test_list_notes_rejects_a_limit_greater_than_max_list_limit
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'MassNote_', limit: 201)

    assert result.error, '上限を超える limit がエラーとして返されなかった'
    assert result.text.include?('between 1 and 200'), "エラーメッセージが期待どおりではありません: #{result.text}"
  end
end

# list_notes のフォルダ名検索をテスト
class VaultFolderSearchTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_folder_search_test_')
    copy_fixture_vault(@test_vault)

    # 距離0（ノート名一致）、距離1（直近の親フォルダ）、距離2（その上のフォルダ）のノートを作る
    File.write(File.join(@test_vault, 'Factorio.md'), "# Factorio\n")
    FileUtils.mkdir_p(File.join(@test_vault, 'Factorio'))
    File.write(File.join(@test_vault, 'Factorio', 'Overview.md'), "# Overview\n")
    FileUtils.mkdir_p(File.join(@test_vault, 'Factorio', 'Games'))
    File.write(File.join(@test_vault, 'Factorio', 'Games', 'Project Cybersyn.md'), "# Project Cybersyn\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_folder_name_search_matches_notes_in_matching_folder
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio')

    refute result.error
    assert result.text.include?('- Factorio'), "ノート名一致のノートが含まれていない: #{result.text}"
    assert result.text.include?('- Overview (Factorio)'), "フォルダ名一致のノートにパスが添えられていない: #{result.text}"
    assert result.text.include?('- Project Cybersyn (Factorio/Games)'), "フォルダ名一致のノートにパスが添えられていない: #{result.text}"
  end

  def test_matches_are_ordered_by_distance_from_the_file
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio')

    lines = result.text.lines.map(&:strip).select { |line| line.start_with?('- ') }
    assert_equal ['- Factorio', '- Overview (Factorio)', '- Project Cybersyn (Factorio/Games)'], lines,
      "ファイルからの距離順に並んでいない: #{result.text}"
  end

  def test_search_is_case_insensitive
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'factorio')

    refute result.error
    assert result.text.include?('- Factorio'), "小文字の検索語がノート名に一致しなかった: #{result.text}"
    assert result.text.include?('- Project Cybersyn (Factorio/Games)'), "小文字の検索語がフォルダ名に一致しなかった: #{result.text}"
  end

  def test_all_words_must_be_found_in_the_path
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'factorio cybersyn')

    refute result.error
    assert result.text.include?('- Project Cybersyn (Factorio/Games)'), "すべての語が含まれるノートが返されなかった: #{result.text}"

    result = ObsidianFetch.list_notes(vault.vault, 'factorio nonexistent')
    assert result.error, 'すべての語が含まれないノートが返された'
  end

  def test_response_reports_the_breakdown_of_matches
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio')

    assert result.text.include?('3 notes matched'), "マッチ総件数が応答に含まれていない: #{result.text}"
    assert result.text.include?('1 by note name, 2 by folder name'), "マッチの内訳が応答に含まれていない: #{result.text}"
  end

  # 同じ距離内は大文字小文字を揃えて比較し、同値は原名の ASCII 順でタイブレークすることをテストする
  def test_names_are_sorted_case_insensitively_within_a_group
    File.write(File.join(@test_vault, 'Factorio', 'Beta.md'), "# Beta\n")
    File.write(File.join(@test_vault, 'Factorio', 'alpha.md'), "# alpha\n")

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio')

    lines = result.text.lines.map(&:strip).select { |line| line.start_with?('- ') }
    assert_equal ['- Factorio', '- alpha (Factorio)', '- Beta (Factorio)', '- Overview (Factorio)', '- Project Cybersyn (Factorio/Games)'], lines,
      "同じ距離内がノート名順に並んでいない: #{result.text}"
  end
end

# limit を超えるマッチがある場合の truncate の挙動をテストする
class VaultTruncationTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_truncation_test_')

    # 距離0のグループ: Factorio.md
    File.write(File.join(@test_vault, 'Factorio.md'), "# Factorio\n")
    # 距離1のグループ: Factorio 配下に6件
    FileUtils.mkdir_p(File.join(@test_vault, 'Factorio'))
    6.times do |i|
      File.write(File.join(@test_vault, 'Factorio', "note_#{i}.md"), "# note_#{i}\n")
    end
    # 距離2のグループ: Factorio/Games 配下に1件
    FileUtils.mkdir_p(File.join(@test_vault, 'Factorio', 'Games'))
    File.write(File.join(@test_vault, 'Factorio', 'Games', 'deep.md'), "# deep\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_truncation_shows_head_and_tail_of_the_truncated_group
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio', limit: 4)

    refute result.error
    assert result.text.include?('I will show you 4 of them. To see the rest, narrow the search or raise the limit.'), "案内文が表示されていない: #{result.text}"

    lines = result.text.lines.map(&:strip).select { |line| line.start_with?('- ') || line.start_with?('...') }
    assert_equal ['- Factorio', '- note_0 (Factorio)', '- note_1 (Factorio)', '... (3 notes omitted) ...', '- note_5 (Factorio)'], lines,
      "先頭と末尾の表示が期待どおりではありません: #{result.text}"
    # 枠を使い切ったので、優先順位の低いグループ（距離2）は表示されない
    refute result.text.include?('deep'), "優先順位の低いグループが表示されている: #{result.text}"
  end

  def test_truncation_shows_head_only_when_the_remaining_slots_are_less_than_three
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Factorio', limit: 3)

    refute result.error
    lines = result.text.lines.map(&:strip).select { |line| line.start_with?('- ') || line.start_with?('...') }
    assert_equal ['- Factorio', '- note_0 (Factorio)', '- note_1 (Factorio)', '... (4 notes omitted) ...'], lines,
      "先頭だけの表示が期待どおりではありません: #{result.text}"
  end
end

# リンク形式のテストをまとめてテスト
class VaultLinkFormatTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_link_test_')
    copy_fixture_vault(@test_vault)

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
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), "'.md' が除去されてリンク先が登録されていない"
    refute vault.vault.links_by_file_name.key?('Hello World.md'), "'.md' 付きで登録されてはいけない"

    backlinks = vault.vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has MD Link') }
  end

  def test_displayname_link_uses_link_part_not_display
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), 'リンク部分 Hello World が登録されていない'
    refute vault.vault.links_by_file_name.key?('HW Note'), '表示名 HW Note が登録されてはいけない'

    backlinks = vault.vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has DisplayName Link') }
  end

  def test_displaypath_link_uses_path_not_display
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), 'パス部分 Hello World が登録されていない'
    refute vault.vault.links_by_file_name.key?('Link to HW'), '表示名 Link to HW が登録されてはいけない'

    backlinks = vault.vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has Display Path Link') }
  end

  def test_displaypath_link_with_md_extension
    # `[display](path.md)` 形式のリンクもテスト
    File.write(
      File.join(@test_vault, 'Has Display Path Link with MD.md'),
      "# Has Display Path Link with MD\n\nThis note has a [Link to HW](Hello World.md) link.\n"
    )

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    assert vault.vault.links_by_file_name.key?('Hello World'), "'.md' が除去されてリンク先が登録されていない"
  end

  def test_external_url_excluded
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    refute vault.vault.links_by_file_name.key?('example.com'), '外部リンクが登録されてはいけない'
    refute vault.vault.links_by_file_name.key?('https'), '外部リンクのスキームが登録されてはいけない'
  end

  def test_anchor_link_is_stripped
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), '#アンカーが除去されてリンク先が登録されていない'
    refute vault.vault.links_by_file_name.key?('Hello World#Introduction'), 'アンカー付きで登録されてはいけない'

    backlinks = vault.vault.links_by_file_name['Hello World']
    assert backlinks.any? { |p| p.include?('Has Anchor Link') }
  end

  def test_block_id_link_is_stripped
    # ^block_id 形式のリンクもテスト
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), '^blockid が除去されてリンク先が登録されていない'
  end
end

# list_notes のバックリンクフォールバックをテスト
class VaultBacklinkFallbackTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_backlink_test_')
    copy_fixture_vault(@test_vault)

    # リンク先が存在しないノートを追加
    File.write(File.join(@test_vault, 'Links to NonExistent.md'), "# Links to NonExistent\n\nThis note links to [[Phantom Note]].\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_list_notes_backlink_fallback
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    # "Phantom Note" はノート名として存在しない
    refute vault.vault.notes.key?('Phantom Note'), 'Phantom Note がノート名として登録されてはいけない'
    # だが @links_by_file_name には存在する
    assert vault.vault.links_by_file_name.key?('Phantom Note'), 'links_by_file_name に Phantom Note が登録されていない'

    result = ObsidianFetch.list_notes(vault.vault, 'Phantom Note')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('However, I found other notes linked to this note'), 'バックリンクのメッセージが表示されていない'
    assert result.text.include?('Links to NonExistent'), 'バックリンク先ノート名が表示されていない'
  end

  def test_backlink_fallback_list_is_sorted_by_note_name
    File.write(File.join(@test_vault, 'beta.md'), "# beta\n\n[[Phantom Note]]\n")
    File.write(File.join(@test_vault, 'Alpha.md'), "# Alpha\n\n[[Phantom Note]]\n")

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.list_notes(vault.vault, 'Phantom Note')

    lines = result.text.lines.map(&:strip).select { |line| line.start_with?('- ') }
    assert_equal ['- Alpha', '- beta', '- Links to NonExistent'], lines,
      "フォールバックのリストがノート名順に並んでいない: #{result.text}"
  end
end

# read_note のバックリンク表示をテスト
class VaultReadBacklinkTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_backlink_display_test_')
    copy_fixture_vault(@test_vault)

    # リンク元となるノートを追加（Hello World を参照する）
    File.write(File.join(@test_vault, 'Refers to Hello.md'), "# Refers to Hello\n\nThis note has a [[Hello World]] link.\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_note_shows_backlink
    vault = ObsidianFetch::VaultManager.new([@test_vault])

    assert vault.vault.links_by_file_name.key?('Hello World'), 'links_by_file_name に Hello World が登録されていない'

    result = ObsidianFetch.read_note(vault.vault, 'Hello World')

    refute result.error
    assert result.text.include?('Hello World')

    # バックリンクが表示される
    assert result.text.include?('Refers to Hello'), 'バックリンクが表示されていない'
    assert result.text.include?('linked by') || result.text.include?('This note is linked'), 'バックリンクのメッセージが表示されていない'

    # 複数のリンク元ノートが表示される
    assert result.text.include?('Links to HW'), '複数のバックリンクが表示されていない'
  end

  def test_backlinks_are_sorted_by_note_name
    File.write(File.join(@test_vault, 'beta.md'), "# beta\n\n[[Hello World]]\n")
    File.write(File.join(@test_vault, 'Alpha.md'), "# Alpha\n\n[[Hello World]]\n")

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'Hello World')

    order = ['- Alpha', '- beta', '- Links to HW', '- Refers to Hello']
    positions = order.map { |line| result.text.index(line) }
    assert positions.none?(&:nil?), "バックリンクが表示されていない: #{result.text}"
    assert positions == positions.sort, "バックリンクがノート名順に並んでいない: #{result.text}"
  end
end

# read_note のフォールバック処理をテスト
class VaultReadNotExistsTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_notexists_test_')
    copy_fixture_vault(@test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_note_not_exists_no_backlink
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'NonExistent Note')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('Note not found:'), 'ノートが見つからないメッセージが表示されていない'
  end

  def test_read_note_not_exists_with_backlink
    # リンク先が存在しないノートを追加
    File.write(File.join(@test_vault, 'Links to Phantom.md'), "# Links to Phantom\n\nThis note links to [[Phantom Note]].\n")

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'Phantom Note')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('However, I found other notes linked to this note'), 'バックリンクのメッセージが表示されていない'
    assert result.text.include?('Links to Phantom'), 'バックリンク先ノート名が表示されていない'
  end
end

# read_note のパス修正後のフォールバックをテスト
class VaultPathCorrectionFallbackTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_path_correction_test_')
    copy_fixture_vault(@test_vault)
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_read_note_path_correction_not_found_no_backlink
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'some/path/NonExistent')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('Note not found:'), 'ノートが見つからないメッセージが表示されていない'
  end

  def test_read_note_path_correction_found_in_links
    # リンク先が存在しないノートを追加
    File.write(File.join(@test_vault, 'Links to Phantom.md'), "# Links to Phantom\n\nThis note links to [[Phantom Note]].\n")

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'some/path/Phantom Note')

    assert result.error, 'エラーが返されていない'
    assert result.text.include?('However, I found other notes linked to this note'), 'バックリンクのメッセージが表示されていない'
    assert result.text.include?('Links to Phantom'), 'バックリンク先ノート名が表示されていない'
  end
end

# read_note の大文字小文字の揺らぎをテスト
class VaultReadCaseTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_read_case_test_')

    # 完全一致と揺らぎマッチが区別できる内容にする
    File.write(File.join(@test_vault, 'Hello World.md'), "exact content\n")
    File.write(File.join(@test_vault, 'hello world.md'), "variant content\n")
    File.write(File.join(@test_vault, 'HELLO WORLD.md'), "another variant content\n")
    File.write(File.join(@test_vault, 'Solo Note.md'), "solo content\n")
    File.write(File.join(@test_vault, 'solo note.md'), "solo variant content\n")
    File.write(File.join(@test_vault, 'Group Note.md'), "group one content\n")
    File.write(File.join(@test_vault, 'GROUP NOTE.md'), "group two content\n")
    File.write(File.join(@test_vault, 'Path Note.md'), "path content\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_exact_match_is_read_and_case_variants_are_suggested
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'Hello World')

    refute result.error
    assert result.text.include?('exact content'), "完全一致のノートの内容が返されていない: #{result.text}"
    refute result.text.include?('variant content'), "完全一致があるのに揺らぎマッチの内容が混ざっている: #{result.text}"
    refute result.text.include?('another variant content'), "完全一致があるのに揺らぎマッチの内容が混ざっている: #{result.text}"
    assert result.text.include?('There are also notes with the same name in different capitalization'), "サジェストが表示されていない: #{result.text}"
    assert result.text.lines.map(&:strip).select { |line| line.start_with?('- ') } == ['- HELLO WORLD', '- hello world'], "サジェストが期待どおりではありません: #{result.text}"
  end

  def test_exact_match_suggests_a_single_case_variant
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'Solo Note')

    refute result.error
    assert result.text.include?('solo content'), "完全一致のノートの内容が返されていない: #{result.text}"
    assert result.text.include?('There is also a note with the same name in different capitalization'), "サジェストが表示されていない: #{result.text}"
    assert result.text.include?('- solo note'), "サジェストに候補名が含まれていない: #{result.text}"
  end

  def test_multiple_case_variants_are_listed_without_reading_content
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'group note')

    refute result.error, '揺らぎマッチがエラーとして返された'
    assert result.text.include?('The following notes have the same name with different capitalization'), "揺らぎマッチの旨が表示されていない: #{result.text}"
    assert result.text.lines.map(&:strip).select { |line| line.start_with?('- ') } == ['- GROUP NOTE', '- Group Note'], "候補名が期待どおり表示されていない: #{result.text}"
    refute result.text.include?('group one content'), "候補が複数あるのに内容を読んでいる: #{result.text}"
    refute result.text.include?('group two content'), "候補が複数あるのに内容を読んでいる: #{result.text}"
  end

  def test_single_case_variant_is_read_when_no_exact_match_exists
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'path note')

    refute result.error, '揺らぎマッチがエラーとして返された'
    assert result.text.include?('path content'), "揺らぎマッチしたノートの内容が返されていない: #{result.text}"
    assert result.text.include?('The following note has the same name with different capitalization'), "揺らぎマッチの旨が表示されていない: #{result.text}"
  end

  def test_path_input_with_case_variant
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'some/path/path note')

    refute result.error, '揺らぎマッチがエラーとして返された'
    assert result.text.include?('renamed'), "パス補正の旨が表示されていない: #{result.text}"
    assert result.text.include?('The following note has the same name with different capitalization'), "揺らぎマッチの旨が表示されていない: #{result.text}"
    assert result.text.include?('path content'), "揺らぎマッチしたノートの内容が返されていない: #{result.text}"
  end
end

# open_file のファイル列挙の順序をテスト
class VaultFilePathOrderTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_file_path_order_test_')

    FileUtils.mkdir_p(File.join(@test_vault, 'aaa'))
    FileUtils.mkdir_p(File.join(@test_vault, 'BBB'))
    File.write(File.join(@test_vault, 'aaa', 'Same Name.md'), "# first\n")
    File.write(File.join(@test_vault, 'BBB', 'Same Name.md'), "# second\n")
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  def test_files_are_listed_in_path_order
    vault = ObsidianFetch::VaultManager.new([@test_vault])
    result = ObsidianFetch.read_note(vault.vault, 'Same Name')

    assert result.text.index('first') < result.text.index('second'), "ファイル列挙がパス順で並んでいない: #{result.text}"
  end
end
