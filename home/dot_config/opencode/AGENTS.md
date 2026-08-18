# Agent Guidelines

## File Reading Efficiency (Cost Optimization)

**Before using `Read()`, always try cheaper alternatives first:**

1. **Find files first** - Use `Glob` with patterns instead of guessing paths
2. **Search content** - Use `Grep` to locate specific code before reading
3. **LSP navigation** - Use `lsp_symbols` for file outlines, `lsp_goto_definition` for symbol lookup
4. **Targeted reads** - Use `Read` with `offset`/`limit` for files >200 lines
5. **RTK tools** - Prefer `rtk_`-prefixed tools when available (they dedupe and cache)

### Pattern Examples

```txt
❌ Wasteful: Read("/path/to/big-file.ts")  → 3000 tokens
✅ Efficient: Grep("functionName", "/path/to/big-file.ts") → 200 tokens

❌ Wasteful: Read entire module to find a class
✅ Efficient: lsp_symbols → lsp_goto_definition → Read with offset/limit

❌ Wasteful: ls -la recursively to explore
✅ Efficient: Glob("**/*.ts") with specific patterns
```

### Why This Matters

Input tokens cost 3-4x more than output tokens. Reading full files unnecessarily is the #1 source of token waste. Following these guidelines can reduce context costs by 60-80%.

## Tool Preferences

- **Search**: `Grep` > `rtk_grep` > shell `grep`
- **List**: `Glob` > `rtk_ls` > shell `ls`
- **Read**: `cachebro_read_file` > `Read` with offset/limit > full `Read`
- **Navigate code**: `lsp_*` tools > manual file reading

<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tools** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them. `codegraph_node` returns one symbol's source + callers, or reads a whole file with line numbers. If the tools are listed but deferred, load them by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` and `codegraph node <symbol-or-file>` print the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->
