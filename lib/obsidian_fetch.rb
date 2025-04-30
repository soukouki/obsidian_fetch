# frozen_string_literal: true

require 'yaml'
require 'date'
require 'mcp'

require_relative "obsidian_fetch/version"

module ObsidianFetch
  class Error < StandardError; end
  
  class Vault
    attr_reader :notes, :links_by_file_path, :links_by_file_name
  
    def initialize vault_pathes
      @vault_pathes = vault_pathes
  
      # key: note_name, value: [file_pathes]
      @notes = {}
  
      # key: file_path, value: [file_pathes]
      @links_by_file_path = {}
  
      # ノートが見つからなかった場合に被リンクを表示するためのハッシュ
      # key: note_name, value: [file_pathes]
      @links_by_file_name = {}
  
      collect_pathes()
      collect_notes()
      collect_links()
    end
  
    private
  
    def collect_pathes
      @all_pathes = @vault_pathes.flat_map do |vault_path|
        Dir.glob("#{vault_path}/**/*.md")
      end
    end
  
    # ノート名を正規化する
    # ファイル名に使えない文字については除去しない。aliasで設定されている場合もあるため。
    def self.normalize_note_name(note_name)
      # ノート名を小文字に変換し、リンクに使えない文字を除去する
      note_name.gsub(/[\[\]#\^\|]/, '')
    end
  
    def collect_notes
      # ノート名を整理するための処理
      @all_pathes.each do |file_path|
        file_name = File.basename(file_path, '.md')
        file_name = Vault.normalize_note_name(file_name)
        @notes[file_name] ||= []
        @notes[file_name] << file_path
        content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
        # もしaliasが設定されていれば、それも追加する
        frontmatter_str = content.match(/\A---(.*?\n)---/m)&.[](1)
        if frontmatter_str
          begin
            frontmatter = YAML.safe_load(frontmatter_str, symbolize_names: true, aliases: true, permitted_classes: [Date])
          rescue Psych::SyntaxError => e
            puts "YAML syntax error in #{file_path}: #{e.message}"
            next
          end
          (frontmatter&.[](:aliases) || []).each do |alias_name|
            alias_name = Vault.normalize_note_name(alias_name)
            @notes[alias_name] ||= []
            @notes[alias_name] << file_path
          end
        end
      end
      @notes.each{|_name, file_pathes| file_pathes.uniq!}
    end
  
    def collect_links
      # リンクを整理するための処理
      # リンクを整理するためにノート名のリストを使用するため、ここで処理する
      @all_pathes.each do |file_path|
        file_name = File.basename(file_path, '.md')
        file_name = Vault.normalize_note_name(file_name)
        content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
        # もしリンクが設定されていれば、linksに追加する
        # [[link]]と[[link|displayname]]の場合
        # linkに.mdが付いている場合、付いていない場合両方を考慮する
        content.scan(/\[\[(.*?)(?:\|.*)?\]\]/) do |match|
          link_name = match[0]
          link_name = link_name.sub(/\.md$/, '') # .mdを削除
          # #、^以降の文字列を削除
          link_name = link_name.sub(/#.*$/, '')
          link_name = Vault.normalize_note_name(link_name)
          next if link_name == file_name # 自分自身をリンクしている場合は無視する
          @links_by_file_name[link_name] ||= []
          @links_by_file_name[link_name] << file_path
          # 同名のノートがある場合に、どこにリンクしているかを処理するのは結構難しい
          # ここでは簡単のため、同名のノートがある場合はすべてのファイルをリンク先として追加する
          # ただし、aliasは除外する
          linked_candidates = (@notes[link_name] || []).filter{|path| path.include?(link_name + '.md') }
          linked_candidates.each do |linked_candidate|
            @links_by_file_path[linked_candidate] ||= []
            @links_by_file_path[linked_candidate] << file_path
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
          link_name = Vault.normalize_note_name(link_name)
          @links_by_file_name[link_name] ||= []
          @links_by_file_name[link_name] << file_path
          # Obsidianはかなり賢くて、リンク先のファイルが無い場合には、その配下のファイルを探してくれる
          # 今回の実装ではそこまで考慮せず、pathを信用する
          path_from_vault = File.join(File.dirname(file_path), path) + '.md'
          @links_by_file_path[path_from_vault] ||= []
          @links_by_file_path[path_from_vault] << file_path
        end
      end
      @links_by_file_name.each do |_file_name, file_pathes|
        file_pathes.uniq!
      end
      @links_by_file_path.each do |_file_path, file_pathes|
        file_pathes.uniq!
      end
    end

    public

    def tool_read name
      name = Vault.normalize_note_name(name)
      file_pathes = @notes[name]
      # 名前のノートが存在しない場合
      if file_pathes.nil?
        return "Note not found: #{name}" if @links_by_file_name[name].nil?
        return <<~EOS
          Note not found: #{name}
          However, I found other notes linked to this note.
          #{@links_by_file_name[name].shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
        EOS
      end
    
      # 複数のファイルがある場合は、---とファイル名で区切って返す
      file_pathes.map do |file_path|
        content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
        link_notes = if @links_by_file_path[file_path].nil?
          ""
        else
          <<~EOS
            This note is linked by the following notes:
            #{(@links_by_file_path[file_path] || []).shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
          EOS
        end
        preface = <<~EOS
          The contents of the note '#{name}' is as follows.
          #{link_notes}
          ---
    
        EOS
        preface + content
      end.join("\n\n---\n\n")
    end
    
    MAX_LIST_SIZE = 20
    def tool_list name
      name = Vault.normalize_note_name(name)
      split_name = name.split(/[\s　]+/)
      # 空白文字で検索された場合は失敗した旨を返す
      # 仮に全ノートからランダムなMAX_LIST_SIZEを返してしまうと、LLMが誤って呼び出した場合に偽の関連性を持ってしまうため
      if split_name.empty?
        return <<~EOS
          It cannot be listed in a blank string.
        EOS
      end
      matched_notes = @notes.select do |note_name, _file_pathes|
        split_name.map {|name_part| note_name.include?(name_part) }.all?
      end
      # 名前で検索したが見つからない場合
      if matched_notes.empty?
        has_found_link = @links_by_file_name[name] && !@links_by_file_name[name].empty?
        return <<~EOS unless has_found_link
          Note not found: #{name}
          Search again with a substring or a string with a different notation.
        EOS
        return <<~EOS
          Note not found: #{name}
          However, I found other notes linked to this note.
          #{@links_by_file_name[name].shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
        EOS
      end
      # マッチした名前の数が多すぎる場合は、ランダムにMAX_LIST_SIZE個選ぶ
      preface = "Notes matching '#{name}' are as follows.\n"
      if matched_notes.size > MAX_LIST_SIZE
        matched_notes = matched_notes.to_a.sample(MAX_LIST_SIZE).to_h
        preface = "Too many notes matched. I will show you only #{MAX_LIST_SIZE} of them.\n" + preface
      end
      # マッチした名前のリストで返す
      list = matched_notes.keys.shuffle.map do |note_name|
        "- #{note_name}"
      end.join("\n")
      preface + list
    end
  end

end
