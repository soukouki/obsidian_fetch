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

  # limit を超えるマッチがある場合、距離順が保たれ、同じ距離内での選択は乱数で決まることをテストする
  # Array#shuffle はシステムの乱数を使うので、srand で seed を固定すれば結果を再現できる
  def test_truncation_keeps_closer_matches_and_is_reproducible_with_a_seed
    # 同じ距離内のノートを増やして、選択がランダムになる条件を作る
    3.times do |i|
      File.write(File.join(@test_vault, 'Factorio', "Extra_#{i}.md"), "# Extra_#{i}\n")
    end

    vault = ObsidianFetch::VaultManager.new([@test_vault])
    same_distance = ['- Overview (Factorio)', '- Extra_0 (Factorio)', '- Extra_1 (Factorio)', '- Extra_2 (Factorio)']

    srand(42)
    first = ObsidianFetch.list_notes(vault.vault, 'Factorio', limit: 3)
    first_lines = first.text.lines.map(&:strip).select { |line| line.start_with?('- ') }

    srand(42)
    second = ObsidianFetch.list_notes(vault.vault, 'Factorio', limit: 3)
    second_lines = second.text.lines.map(&:strip).select { |line| line.start_with?('- ') }

    refute first.error
    assert_equal 3, first_lines.length, "limit(3) と異なる件数が返された: #{first.text}"
    assert_equal '- Factorio', first_lines.first, "距離0のノートが上位に置かれなかった: #{first.text}"
    # 距離1のノートが4件あり、残り枠は2件なので、距離2のノートは削られる
    refute first_lines.any? { |line| line.include?('Project Cybersyn') }, "距離2のノートが距離1より優先された: #{first.text}"
    # 同じ距離内（4件）から2件を選ぶので、同じ距離内からは2件が削られる
    assert_equal 2, (same_distance - first_lines).length, "同じ距離内からの選択が subset になっていない: #{first.text}"
    # seed を固定したときの結果（Ruby の PRNG と Dir.glob の走査順に依存する）
    assert_equal ['- Factorio', '- Extra_1 (Factorio)', '- Overview (Factorio)'], first_lines, "seed を固定した結果が期待どおりではありません: #{first.text}"
    assert_equal first_lines, second_lines, "同じ seed で同じ結果にならなかった"
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
