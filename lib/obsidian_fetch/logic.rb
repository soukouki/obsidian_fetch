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
        # もしも名前で見つからなければ、リンクにも存在しないか確認する
        link_pathes = vault.links_by_file_name[fixed_name]
        if link_pathes.nil?
          return Result.new(text: note_not_found(name), error: true)
        else
          # リンク先のノートが見つかった場合は、prefaceを追加する
          preface = <<~EOS
            Presumably a path was specified. The process was automatically renamed and processed.
          EOS
          return Result.new(text: list_links(fixed_name, preface, vault), error: true)
        end
      else
        # ノート名が見つかった場合は、prefaceを追加する
        preface = <<~EOS
          Presumably a path was specified. The process was automatically renamed and processed.
        EOS
        return Result.new(text: open_file(fixed_name, file_pathes, preface, vault))
      end
    end

    # 名前のノートが存在しない場合
    if file_pathes.nil?
      return Result.new(text: note_not_found(name), error: true) if vault.links_by_file_name[name].nil?
      return Result.new(text: list_links(name, preface, vault), error: true)
    end

    Result.new(text: open_file(name, file_pathes, preface, vault))
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
    # 仮に全ノートからランダムなMAX_LIST_SIZEを返してしまうと、LLMが誤って呼び出した場合に偽の関連性を持ってしまうため
    if split_name.empty?
      return Result.new(text: <<~EOS, error: true)
        It cannot be listed in a blank string.
      EOS
    end
    matched_notes = vault.notes.select do |note_name, _file_pathes|
      split_name.map { |name_part| note_name.include?(name_part) }.all?
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
        #{vault.links_by_file_name[name].shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
      EOS
    end
    # マッチした名前の数が limit より多い場合は、ランダムに limit 個選ぶ
    total = matched_notes.size
    matched_notes = matched_notes.to_a.sample(limit).to_h if total > limit
    preface = "#{total} notes matched '#{name}'.\n"
    preface += "I will show you #{matched_notes.size} of them.\n" if matched_notes.size < total
    preface += "Notes matching '#{name}' are as follows.\n"
    # マッチした名前のリストで返す
    list = matched_notes.keys.shuffle.map { |note_name| "- #{note_name}" }.join("\n")
    Result.new(text: preface + list)
  end

  # --- ヘルパーメソッド ---
  def self.note_not_found(name)
    <<~EOS
      Note not found: #{name}
    EOS
  end

  def self.list_links(name, preface, vault)
    <<~EOS
      #{preface}
      Note not found: #{name}
      However, I found other notes linked to this note.
      #{vault.links_by_file_name[name].shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
    EOS
  end

  def self.open_file(name, file_pathes, preface, vault)
    # 複数のファイルがある場合は、---とファイル名で区切って返す
    result = file_pathes.map do |file_path|
      content = open(file_path) { |f| f.read.force_encoding('UTF-8') }
      link_notes = if vault.links_by_file_path[file_path].nil?
        ""
      else
        <<~EOS
          This note is linked by the following notes:
          #{(vault.links_by_file_path[file_path] || []).shuffle.map { |file_path| "- #{File.basename(file_path, '.md')}" }.join("\n")}
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
