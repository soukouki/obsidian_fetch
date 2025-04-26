# frozen_string_literal: true

require_relative "lib/obsidian_fetch/version"

Gem::Specification.new do |spec|
  spec.name = "obsidian_fetch"
  spec.version = ObsidianFetch::VERSION
  spec.authors = ["sou7"]
  spec.email = ["soukouki0@yahoo.co.jp"]

  spec.summary = "MCP servers specialising in retrieving information from Obsidian vaults."
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
  spec.add_dependency 'mcp-rb', '~> 0.3.2'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
