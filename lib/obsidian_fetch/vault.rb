# frozen_string_literal: true

module ObsidianFetch
  # Vaultスナップショットを表現するイミュータブルなデータ構造
  class Vault
    attr_reader :vault_pathes
    attr_reader :notes
    attr_reader :links_by_file_path
    attr_reader :links_by_file_name

    # @param vault_pathes [Array<String>] 保管庫パスのリスト
    # @param notes [Hash{String => Array<String>}] {ノート名 → [ファイルパス]}
    # @param links_by_file_path [Hash{String => Array<String>}] {ファイルパス → [逆引きパス]}
    # @param links_by_file_name [Hash{String => Array<String>}] {ノート名 → [逆引きパス]}
    def initialize(vault_pathes, notes:, links_by_file_path:, links_by_file_name:)
      @vault_pathes = vault_pathes
      @notes = notes
      @links_by_file_path = links_by_file_path
      @links_by_file_name = links_by_file_name
    end
  end
end
