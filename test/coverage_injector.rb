# frozen_string_literal: true

# SimpleCov を silently start してカバレッジ結果をファイルに保存
require 'simplecov'
SimpleCov.start do
  command_name "MCP Server-#{Process.pid}"
  print_error_status = false
  formatter SimpleCov::Formatter::SimpleFormatter
  minimum_coverage 0
end

# テスト終了時にカバレッジ結果をファイルに保存
SimpleCov.at_exit do
  result = SimpleCov.result
  # カバレッジ結果を JSON ファイルに保存
  require 'json'
  File.write(File.join(__dir__, '..', 'coverage', '.simplecov-integration.json'), result.to_json)
end