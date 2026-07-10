# frozen_string_literal: true

require 'fileutils'

require 'simplecov'
SimpleCov.start do
  # テストファイル自体をカバレッジ対象から除外
  add_filter do |source_file|
    source_file.filename.include?('test/') && source_file.filename.end_with?('.rb')
  end
end

require 'minitest/autorun'
require 'mcp'
require 'tmpdir'

# サーバーのコードを require してカバレッジ計測の対象にする
require_relative '../lib/obsidian_fetch'

# テスト設定
PROJECT_ROOT = File.dirname(__dir__)
FIXTURE_VAULT = File.join(PROJECT_ROOT, 'test', 'fixtures', 'test_vault')

# FIXTURE_VAULT の中身をテスト用ディレクトリにコピー（サブディレクトリを作らない）
def copy_fixture_vault(dest)
  FileUtils.rm_rf(dest)
  FileUtils.mkdir_p(dest)
  Dir.entries(FIXTURE_VAULT).each do |entry|
    next if entry == '.' || entry == '..'
    src = File.join(FIXTURE_VAULT, entry)
    if File.directory?(src)
      FileUtils.cp_r(src, File.join(dest, File.basename(entry)))
    else
      FileUtils.cp(src, dest)
    end
  end
end