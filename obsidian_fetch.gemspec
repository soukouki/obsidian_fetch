# frozen_string_literal: true

require_relative "lib/obsidian_fetch/version"

Gem::Specification.new do |spec|
  spec.name = "obsidian_fetch"
  spec.version = ObsidianFetch::VERSION
  spec.authors = ["sou7"]
  spec.email = ["soukouki0@yahoo.co.jp"]

  spec.summary = "MCP servers specialising in retrieving information from Obsidian vaults."
  spec.description = <<~EOS
    The existing MCP server has the following drawbacks:
    - There are many commands, and when computational resources are limited, it can take a long time to load the prompt.
    - When reading a note labeled "LLM," it is necessary to search for the path first before loading it, but the LLM may not always follow this procedure.
    - Some tools have unnecessary options, causing the LLM to sometimes fail to invoke the tool correctly.

    These issues become particularly noticeable when running an LLM on a local GPU.  
    To address this, we developed a new MCP server that simply retrieves and loads a list of notes.

    Additionally, the new server has the following features:
    - When the LLM tries to retrieve link information and searches with brackets like `[[link name]]`, it automatically removes characters that cannot be used in links.
    - When reading a file, if there are links pointing to the opened file, it displays them.
        - Especially in network-style note tools like Obsidian, following such links to load related notes can be very powerful.
  EOS
  spec.homepage = "https://ob.sou7.io/2025-04/week17/obsidian_fetch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/soukouki/obsidian_fetch"
  spec.metadata["changelog_uri"] = "https://github.com/soukouki/obsidian_fetch/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
