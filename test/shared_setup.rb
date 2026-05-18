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