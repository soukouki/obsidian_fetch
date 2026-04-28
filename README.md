# ObsidianFetch

> Languages: [日本語](README_ja.md)

MCP servers focused on fetching and presenting information from Obsidian vaults.

The existing MCP server has the following drawbacks:
- It supports many commands, which can cause slow prompt loading when computational resources are limited.
- When reading a note labeled "Sample Note", it is necessary to search for its path first before loading it, but the LLM may not always follow this procedure.
- Some tools include unnecessary options, leading the LLM to sometimes fail to invoke them correctly.

These issues become particularly noticeable when running an LLM on a local GPU.  
To address this, we developed a new MCP server that simply retrieves and loads lists of notes.

The new server also provides the following additional features:
- When the LLM attempts to retrieve link information by searching with brackets like `[[link name]]`, the server automatically removes any characters that cannot be used in links.
- In addition to loading the note contents, it also displays backlinks—notes that link to the currently opened note.
	- This allows the LLM to load and understand the connections between related notes via backlinks.

## Installation

```bash
gem install obsidian_fetch
```

## Usage

### Stdio Transport (default)

```bash
obsidian_fetch /path/to/your/vault
```

### Streamable HTTP Transport

To run the server as an HTTP server:

```bash
obsidian_fetch /path/to/your/vault --transport streamable-http
```

By default, the server listens on `http://localhost:9292`. You can customize the port:

```bash
obsidian_fetch /path/to/your/vault --transport streamable-http --port 3000
```

## Tools

- **read**: Read a note from the Obsidian vault. If multiple notes with the same name are found, all will be shown.
- **list**: Search for files with matching names partially.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soukouki/obsidian_fetch.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
