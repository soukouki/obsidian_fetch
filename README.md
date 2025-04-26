# ObsidianFetch

MCP servers specialising in retrieving information from Obsidian vaults.

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
- Support for aliases.

## Installation

```bash
gem install obsidian_fetch
```

## Usage

```bash
obsidian_fetch /path/to/your/vault
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/soukouki/obsidian_fetch.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
