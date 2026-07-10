# frozen_string_literal: true

require 'yaml'
require 'date'

require_relative "obsidian_fetch/version"
require_relative "obsidian_fetch/vault"
require_relative "obsidian_fetch/vault_manager"
require_relative "obsidian_fetch/logic"

module ObsidianFetch
  class Error < StandardError; end
end
