# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rake/testtask'

task default: [:test]

task :test do
  # テスト実行前にカバレッジデータをリセット
  Dir.glob('coverage/.resultset.json*').each { |f| File.delete(f) if File.exist?(f) }
end

Rake::TestTask.new('test') do |t|
  t.test_files = FileList['test/test_*.rb']
end
