# frozen_string_literal: true

module ObsidianFetch
  # ツール呼び出しの結果を保持する
  Result = Struct.new(:text, :error, keyword_init: true) do
    def initialize(text:, error: false)
      super(text: text, error: error)
    end
  end

  # list ツールの既定の返却件数
  MAX_LIST_SIZE = 20
  # list ツールで指定できる返却件数の上限
  MAX_LIST_LIMIT = 200

  # ノート名を正規化する
  # ファイル名に使えない文字については除去しない。aliasで設定されている場合もあるため。
  def self.normalize_note_name(note_name)
    note_name.gsub(/[\[\]\#\^|]/, '')
  end

  PATH_CORRECTION_PREFACE = <<~EOS
    Presumably a path was specified. The process was automatically renamed and processed.
  EOS

  # --- ツールロジック ---
  def self.read_note(vault, name)
    name = ObsidianFetch.normalize_note_name(name)
    file_pathes = vault.notes[name]

    preface = ""
    # 名前のノートが見つからないが、nameがパスっぽい場合は、パスを修正したうえでもう一度試す
    if file_pathes.nil? && name.include?('/')
      fixed_name = File.basename(name, '.md')
      file_pathes = vault.notes[fixed_name]
      if file_pathes.nil?
        # 完全一致がない場合のみ、大文字小文字の差異を許容した検索をする
        candidates = case_variant_candidates(vault, fixed_name)
        return fuzzy_match_response(vault, fixed_name, candidates, PATH_CORRECTION_PREFACE) unless candidates.empty?

        # もしも名前で見つからなければ、リンクにも存在しないか確認する
        link_pathes = vault.links_by_file_name[fixed_name]
        if link_pathes.nil?
          return Result.new(text: note_not_found(name), error: true)
        else
          # リンク先のノートが見つかった場合は、prefaceを追加する
          return Result.new(text: list_links(fixed_name, PATH_CORRECTION_PREFACE, vault), error: true)
        end
      else
        # ノート名が見つかった場合は、prefaceを追加する
        return Result.new(text: PATH_CORRECTION_PREFACE + case_variant_suggestion(vault, fixed_name) + open_file(fixed_name, file_pathes, "", vault))
      end
    end

    # 名前のノートが存在しない場合
    if file_pathes.nil?
      # 完全一致がない場合のみ、大文字小文字の差異を許容した検索をする
      candidates = case_variant_candidates(vault, name)
      return fuzzy_match_response(vault, name, candidates, preface) unless candidates.empty?

      return Result.new(text: note_not_found(name), error: true) if vault.links_by_file_name[name].nil?
      return Result.new(text: list_links(name, preface, vault), error: true)
    end

    Result.new(text: case_variant_suggestion(vault, name) + open_file(name, file_pathes, preface, vault))
  end

  def self.list_notes(vault, name, limit: MAX_LIST_SIZE)
    unless limit.is_a?(Integer) && limit >= 1 && limit <= MAX_LIST_LIMIT
      return Result.new(text: <<~EOS, error: true)
        The limit must be an integer between 1 and #{MAX_LIST_LIMIT}.
      EOS
    end

    name = ObsidianFetch.normalize_note_name(name)
    split_name = name.split(/[\t \u3000]+/)
    # 空白文字で検索された場合は失敗した旨を返す
    # 仮に全ノートからランダムに limit 件返してしまうと、LLMが誤って呼び出した場合に偽の関連性を持ってしまうため
    if split_name.empty?
      return Result.new(text: <<~EOS, error: true)
        It cannot be listed in a blank string.
      EOS
    end
    matched_notes = vault.notes.filter_map do |note_name, file_pathes|
      match_note(vault, note_name, file_pathes, split_name)
    end
    # 名前で検索したが見つからない場合
    if matched_notes.empty?
      has_found_link = vault.links_by_file_name[name] && !vault.links_by_file_name[name].empty?
      return Result.new(text: <<~EOS, error: true) unless has_found_link
        Note not found: #{name}
        Search again with a substring or a string with a different notation.
      EOS
      return Result.new(text: <<~EOS, error: true)
        Note not found: #{name}
        However, I found other notes linked to this note.
        #{sort_case_insensitive(vault.links_by_file_name[name].map { |file_path| File.basename(file_path, '.md') }).map { |note_name| "- #{note_name}" }.join("\n")}
      EOS
    end
    # マッチしたノートの数が limit より多い場合は、優先順位の順に枠を埋める
    # truncate されるグループは先頭と末尾を出す
    total = matched_notes.size
    by_name = matched_notes.count { |entry| entry[:matched_by_name] }
    tiers = matched_notes.group_by { |entry| entry[:distance] }.keys.sort.map do |distance|
      matched_notes.select { |entry| entry[:distance] == distance }.sort_by { |entry| [entry[:note_name].downcase, entry[:note_name]] }
    end

    segments = []
    remaining = limit
    tiers.each do |tier|
      break if remaining.zero?

      if tier.size <= remaining
        segments << {entries: tier, omitted_after: 0}
        remaining -= tier.size
      elsif remaining < 3
        segments << {entries: tier.first(remaining), omitted_after: tier.size - remaining}
        remaining = 0
      else
        head_size = (remaining * 2) / 3
        tail_size = remaining - head_size
        segments << {entries: tier.first(head_size), omitted_after: tier.size - remaining}
        segments << {entries: tier.last(tail_size), omitted_after: 0}
        remaining = 0
      end
    end

    shown = segments.sum { |segment| segment[:entries].size }
    preface = "#{total} notes matched '#{name}'"
    preface += " (#{by_name} by note name, #{total - by_name} by folder name)" if total > by_name
    preface += ".\n"
    preface += "The list is in name order within each priority group.\n"
    if shown < total
      preface += "I will show you #{shown} of them. To see the rest, narrow the search or raise the limit.\n"
    end
    preface += "Notes matching '#{name}' are as follows.\n"
    lines = []
    segments.each do |segment|
      lines += segment[:entries].map do |entry|
        if entry[:matched_by_name]
          "- #{entry[:note_name]}"
        else
          "- #{entry[:note_name]} (#{entry[:display_folder]})"
        end
      end
      lines << "... (#{segment[:omitted_after]} notes omitted) ..." if segment[:omitted_after].positive?
    end
    Result.new(text: preface + lines.join("\n") + "\n")
  end

  # ノート1件について検索語のマッチを判定し、マッチしていれば情報を返す
  # 距離はファイルからの距離で、ノート名は距離0、直近の親フォルダは距離1、その上が距離2とする
  # 各語の最も近いマッチ位置のうち、最も遠いものがそのノートの距離になる
  def self.match_note(vault, note_name, file_pathes, words)
    lowered_words = words.map(&:downcase)
    best = nil

    file_pathes.each do |file_path|
      vault_name, rel_path = relative_path(vault, file_path)
      folders = rel_path.split('/')[0...-1]

      distances = lowered_words.map do |word|
        distance = note_name.downcase.include?(word) ? 0 : nil
        folders.each_with_index do |folder, index|
          next unless folder.downcase.include?(word)
          candidate = folders.size - index
          distance = candidate if distance.nil? || candidate < distance
        end
        distance
      end
      next if distances.any?(&:nil?)

      display_folder = folders.join('/')
      display_folder = File.join(vault_name, display_folder) if vault.vault_pathes.size > 1 && vault_name

      entry = {
        note_name: note_name,
        distance: distances.max,
        matched_by_name: distances.max.zero?,
        display_folder: display_folder,
      }
      best = entry if best.nil? || entry[:distance] < best[:distance]
    end

    best
  end

  # 保管庫ルートからの相対パスと、その保管庫名を返す
  def self.relative_path(vault, file_path)
    vault.vault_pathes.each do |vault_path|
      pattern = /\A#{Regexp.escape(vault_path)}\/+/
      return [File.basename(vault_path), file_path.sub(pattern, '')] if file_path.match?(pattern)
    end
    [nil, File.basename(file_path)]
  end

  # --- ヘルパーメソッド ---
  def self.note_not_found(name)
    <<~EOS
      Note not found: #{name}
    EOS
  end

  # 大文字小文字は揃えて比較し、同値は原名の ASCII 順でタイブレークする
  def self.sort_case_insensitive(values)
    values.sort_by { |value| [value.downcase, value] }
  end

  # 完全一致を除いた、大文字小文字の差異だけのキーをノート名順で返す
  def self.case_variant_candidates(vault, target)
    sort_case_insensitive(vault.notes.keys.reject { |note_name| note_name == target }.select { |note_name| note_name.downcase == target.downcase })
  end

  # 完全一致を読むときに、揺らぎマッチしたノート名のサジェストを組み立てる
  def self.case_variant_suggestion(vault, target)
    candidates = case_variant_candidates(vault, target)
    return "" if candidates.empty?

    if candidates.size == 1
      "There is also a note with the same name in different capitalization:\n- #{candidates.first}\n\n"
    else
      "There are also notes with the same name in different capitalization:\n" +
        candidates.map { |note_name| "- #{note_name}" }.join("\n") + "\n\n"
    end
  end

  # 揺らぎマッチの応答を組み立てる
  # 候補が1件のときはその内容を読み、複数のときは候補名の一覧を返す
  def self.fuzzy_match_response(vault, target, candidates, preface)
    if candidates.size == 1
      note_name = candidates.first
      message = "There is no note named '#{target}'. The following note has the same name with different capitalization:\n- #{note_name}\n\n"
      Result.new(text: preface + message + open_file(note_name, vault.notes[note_name], "", vault), error: false)
    else
      message = "There is no note named '#{target}'. The following notes have the same name with different capitalization:\n" +
        candidates.map { |note_name| "- #{note_name}" }.join("\n") + "\n"
      Result.new(text: preface + message, error: false)
    end
  end

  def self.list_links(name, preface, vault)
    <<~EOS
      #{preface}
      Note not found: #{name}
      However, I found other notes linked to this note.
      #{sort_case_insensitive(vault.links_by_file_name[name].map { |file_path| File.basename(file_path, '.md') }).map { |note_name| "- #{note_name}" }.join("\n")}
    EOS
  end

  def self.open_file(name, file_pathes, preface, vault)
    # 複数のファイルがある場合は、---とファイル名で区切って返す
    result = sort_case_insensitive(file_pathes).map do |file_path|
      content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
      link_notes = if vault.links_by_file_path[file_path].nil?
        ""
      else
        <<~EOS
          This note is linked by the following notes:
          #{sort_case_insensitive(vault.links_by_file_path[file_path].map { |linked_path| File.basename(linked_path, '.md') }).map { |note_name| "- #{note_name}" }.join("\n")}
        EOS
      end
      metadata = <<~EOS
        The contents of the note '#{name}' is as follows.
        #{link_notes}
        ---
      EOS
      metadata + content
    end.join("\n\n---\n\n")
    preface + result
  end
end
