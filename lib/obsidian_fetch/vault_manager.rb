# frozen_string_literal: true

require 'set'

module ObsidianFetch
  # Vaultスナップショットのライフサイクルを管理
  # ファイル変更を検知し、Vaultを再構築する
  class VaultManager

    def initialize(vault_pathes)
      @vault_pathes = vault_pathes
      scan!
    end

    # 最新のVaultを返す。変更があれば自動的に再スキャンする。
    def vault
      refresh_if_changed
      @vault
    end

    private

    # 変更があれば再スキャン
    def refresh_if_changed
      return unless changed?
      scan!
    end

    # 再スキャン: Vaultを再構築し、内部状態を更新
    def scan!
      @last_scan_time = Time.now
      @notes_cache = collect_notes
      @vault = build_vault
      @known_paths = collect_pathes.to_set
      @known_mtimes = {}
      @known_sizes = {}
      @known_paths.each do |path|
        stat = File.stat(path) rescue nil
        @known_mtimes[path] = stat&.mtime&.to_f
        @known_sizes[path] = stat&.size
      end
    end

    # 変更検知
    # チェックサムは計算しない（mtimeとサイズだけで変更を検知）
    # パスごとに stat を1回だけ実行し、mtime と size を両方取得
    # mtime は浮動小数点で比較（マイクロ秒の差も検知）
    # 1. 既知のパスがファイルシステムに存在しない → 削除
    # 2. mtime または size が前回と異なる → 変更
    # 3. 新しい.mdファイルが追加されている → 追加
    def changed?
      current_paths = collect_pathes

      # 追加検知
      if (current_paths.to_set - @known_paths).any?
        return true
      end

      # 削除検知と変更検知を1パスで実行
      @known_paths.each do |path|
        stat = File.stat(path) rescue nil
        unless stat
          return true  # 既知のパスが存在しなくなった = 削除
        end
        previous_mtime = @known_mtimes[path]
        previous_size  = @known_sizes[path]
        if stat.mtime.to_f != previous_mtime || stat.size != previous_size
          return true
        end
      end

      false
    end

    # .mdファイルのパスを収集
    def collect_pathes
      @vault_pathes.flat_map do |vault_path|
        Dir.glob("#{vault_path}/**/*.md")
      end
    end

    # ノート名・aliasの抽出
    # 戻り値: {ノート名 → [ファイルパス]} のハッシュ
    def collect_notes
      # ノートを整理するための処理
      notes = {}
      collect_pathes.each do |file_path|
        file_name = File.basename(file_path, '.md')
        # ノート名を正規化する
        # ファイル名に使えない文字については除去しない。aliasで設定されている場合もあるため。
        file_name = ObsidianFetch.normalize_note_name(file_name)
        notes[file_name] ||= []
        notes[file_name] << file_path

        content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
        frontmatter_str = content.match(/\A---(.*?\n)---/m)&.[](1)
        if frontmatter_str
          begin
            frontmatter = YAML.safe_load(frontmatter_str,
              symbolize_names: true, aliases: true, permitted_classes: [Date])
          rescue Psych::SyntaxError => e
            puts "YAML syntax error in #{file_path}: #{e.message}"
            next
          end
          Array(frontmatter&.[](:aliases) || []).each do |alias_name|
            # もしaliasが設定されていれば、それも追加する
            alias_name = ObsidianFetch.normalize_note_name(alias_name)
            notes[alias_name] ||= []
            notes[alias_name] << file_path
          end
        end
      end
      notes.each { |_name, file_pathes| file_pathes.uniq! }
      notes
    end

    # [[link]]と[link](path)の解析
    # 戻り値: [links_by_file_path, links_by_file_name] の2要素配列
    def collect_links
      links_by_file_path = {}
      links_by_file_name = {}

      # リンクを整理するための処理
      # リンクを整理するためにノート名のリストを使用するため、ここで処理する
      collect_pathes.each do |file_path|
        file_name = File.basename(file_path, '.md')
        file_name = ObsidianFetch.normalize_note_name(file_name)
        content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
        # もしリンクが設定されていれば、linksに追加する
        # [[link]]と[[link|displayname]]の場合
        # linkに.mdが付いている場合、付いていない場合両方を考慮する
        # TODO : linkにディレクトリ名が着くことがあるので、それを除去する
        content.scan(/\[\[(.*?)(?:\|.*)?\]\]/) do |match|
          link_name = match[0]
          link_name = link_name.sub(/\.md$/, '') # .mdを削除
          # #、^以降の文字列を削除
          link_name = link_name.sub(/#.*$/, '')
          link_name = ObsidianFetch.normalize_note_name(link_name)
          next if link_name == file_name # 自分自身をリンクしている場合は無視する
          # 同名のノートがある場合に、どこにリンクしているかを処理するのは結構難しい
          # ここでは簡単のため、同名のノートがある場合はすべてのファイルをリンク先として追加する
          # ただし、aliasは除外する
          links_by_file_name[link_name] ||= []
          links_by_file_name[link_name] << file_path
          linked_candidates = (@notes_cache[link_name] || []).filter { |path| path.include?(link_name + '.md') }
          linked_candidates.each do |linked_candidate|
            links_by_file_path[linked_candidate] ||= []
            links_by_file_path[linked_candidate] << file_path
          end
        end

        # [displayname](path)の場合
        # pathの末尾に.mdが付いている場合、付いていない場合両方を考慮する
        content.scan(/\[(.*?)\]\((?!\[\[)(.*?)(?<!\]\])\)/) do |match|
          path = match[1]
          # `(.+)://`から始まる場合は除外する
          next if path =~ /^[a-z]+:\/\// # 外部リンク
          # #、^以降の文字列を削除
          path = path.sub(/#.*$/, '')
          path = path.sub(/\.md$/, '') # .mdを削除
          link_name = File.basename(path)
          link_name = ObsidianFetch.normalize_note_name(link_name)
          links_by_file_name[link_name] ||= []
          links_by_file_name[link_name] << file_path
          path_from_vault = File.join(File.dirname(file_path), path) + '.md'
          # Obsidianはかなり賢くて、リンク先のファイルが無い場合には、その配下のファイルを探してくれる
          # 今回の実装ではそこまで考慮せず、pathを信用する
          links_by_file_path[path_from_vault] ||= []
          links_by_file_path[path_from_vault] << file_path
        end
      end

      links_by_file_name.each { |_file_name, file_pathes| file_pathes.uniq! }
      links_by_file_path.each { |_file_path, file_pathes| file_pathes.uniq! }
      [links_by_file_path, links_by_file_name]
    end

    # Vaultスナップショットを生成
    def build_vault
      links_by_file_path, links_by_file_name = collect_links
      Vault.new(@vault_pathes,
                notes: @notes_cache,
                links_by_file_path: links_by_file_path,
                links_by_file_name: links_by_file_name)
    end
  end
end
