# frozen_string_literal: true

# SimpleCov を silently start してカバレッジ結果をファイルに保存
require 'simplecov'
SimpleCov.start do
  command_name "MCP Server-#{Process.pid}"
  print_error_status = false
  formatter SimpleCov::Formatter::SimpleFormatter
  minimum_coverage 0
end