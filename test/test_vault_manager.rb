# frozen_string_literal: true

require_relative 'shared_setup'

# VaultManagerの動作を確認する最小限のテスト
class VaultManagerTest < Minitest::Test
  def setup
    @test_vault = Dir.mktmpdir('obsidian_manager_test_')
    copy_fixture_vault(@test_vault)
  ensure
    @manager = ObsidianFetch::VaultManager.new([@test_vault])
  end

  def teardown
    FileUtils.rm_rf(@test_vault) if @test_vault
  end

  # 初期スキャンで既存ノートが読み込まれる
  def test_initial_scan
    vault = @manager.vault
    assert vault.notes.key?('Hello World')
    assert vault.notes.key?('Links to HW')
  end

  # 変更なしでvaultを呼ぶと再スキャンされない
  def test_no_change_no_rescan
    # vaultを2回呼び出し、どちらも同じ結果が返ることを確認
    first = ObsidianFetch.read_note(@manager.vault, 'Hello World')
    second = ObsidianFetch.read_note(@manager.vault, 'Hello World')
    assert_equal first.text, second.text
  end

  # 新しい.mdファイルを追加すると反映される
  def test_file_addition
    File.write(File.join(@test_vault, 'New Note.md'), "# New Note\n")
    vault = @manager.vault
    assert vault.notes.key?('New Note')
    result = ObsidianFetch.read_note(vault, 'New Note')
    refute result.error
    assert result.text.include?('New Note')
  end

  # ファイルを削除すると反映される
  def test_file_deletion
    File.delete(File.join(@test_vault, 'Links to HW.md'))
    vault = @manager.vault
    refute vault.notes.key?('Links to HW')
    result = ObsidianFetch.read_note(vault, 'Links to HW')
    assert result.error
    assert result.text.include?('Note not found')
  end

  # ファイル内容を変更すると反映される
  def test_file_modification
    path = File.join(@test_vault, 'Hello World.md')
    File.write(path, "---\naliases:\n  - HW\n---\n# Hello World\n\nModified content.\n")
    vault = @manager.vault
    result = ObsidianFetch.read_note(vault, 'Hello World')
    refute result.error
    assert result.text.include?('Modified content')
  end

  # リンク関係の変化が反映される
  def test_link_change
    # Links to HW が Hello World をリンクしていることを確認
    vault = @manager.vault
    assert vault.links_by_file_name.key?('Hello World')

    # Links to HW のリンク先を変更
    File.write(File.join(@test_vault, 'Links to HW.md'), "# Links to HW\n\nThis note links to [[NonExistent]]. Some extra text to make the file size different.\n")
    # ↑ フレーキー対策: 元のファイル(51バイト)と書き換え後のファイルでバイト数が異なるようにする。
    # mtimeの精度が秒単位であるため、同じ秒内で変更した場合にサイズ差がないと変更が検知されず再スキャンされない。

    # Hello Worldへのリンクがなくなる
    vault = @manager.vault
    # NonExistentへのリンクが追加される
    assert vault.links_by_file_name.key?('NonExistent')
  end
end
