## [Unreleased]

## [1.3.0] - 2026-10-28

- Dependencies: mcp 1.8.2 (constraint `~> 1.8`), puma 8.0.2, rack 3.2.7, simplecov 1.3.2. Required Ruby is 3.3.0 or later.
- list tool: stopped shuffling. Results are ordered by note name, compared case-insensitively with an ASCII tiebreak. Backlinks, link fallback lists and file enumerations are ordered the same way. When the result is truncated by limit, the truncated priority group shows its head and tail with a line reporting the omitted count.
- list tool: added the `limit` argument (1 to 200, default 20) and the total number of matches in the response.
- list tool: folder names are searched, matches are ranked by the distance from the file, and the response reports the breakdown of matches.
- read tool: a case-insensitive fuzzy match is accepted when no exact match exists, and case variants are suggested when an exact match exists.
- The initialize response advertises only the tools capability.

## [1.2.0] - 2026-07-10

- Vault files are reloaded when they change.
- isError handling was added to the tools.
- Tests were restructured and coverage measurement was added.

## [1.1.2] - 2026-04-28

- The Puma bind address was changed from 127.0.0.1 to 0.0.0.0 to allow external access.
- The `enable_json_response` option added in 1.1.1 was reverted.

## [1.1.1] - 2026-04-28

- Added the `enable_json_response` option for mcp 0.14.0.

## [1.1.0] - 2026-04-28

- Added the Streamable HTTP transport.
- README was made multilingual.
- The mcp gem was upgraded to 0.14.0.

## [1.0.0] - 2025-08-20

- Switched to the official MCP Ruby SDK.
- Fixed the way tools are specified.
- read tool normalizes a path given as `name`.
- Display shows note names instead of paths.
- Refactored and extended the list tool.

## [0.1.0] - 2025-04-27

- Initial release
