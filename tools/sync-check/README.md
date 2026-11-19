# sync-check

Answers: do the scripts inside Studio match the files on disk? It compares content, so it works even when
the Rojo plugin shows as connected but edits to existing scripts are being dropped (new files still arrive,
and the manifest is a new file).

Needs `node` on PATH. Nothing is installed or modified besides a temporary `src/server/dev/SyncManifest_*.luau`
(git-ignored).

## Person (two steps)

1. `.\tools\sync-check\run.ps1` - writes the manifest, waits ~4 s for Rojo, prints the snippet.
2. Studio command bar, Edit mode: `require(game.ServerScriptService.Server.dev.SyncCheck).run()` and read the Output.

Then `.\tools\sync-check\run.ps1 clean` to delete the manifest (Rojo removes it from Studio too).

## Assistant via Studio MCP

1. `powershell -NoProfile -File tools/sync-check/run.ps1`
2. `execute_luau`, datamodel `Edit`: `return require(game.ServerScriptService.Server.dev.SyncCheck).run().message`
3. `powershell -NoProfile -File tools/sync-check/run.ps1 clean`

Only mismatches are returned (capped at 60 lines per category). A file another session is mid-saving may show as
differing; re-run before trusting it. "No SyncManifest module found" means Rojo is not delivering to Studio.

## Rules

- Hash: FNV-1a 32 over UTF-8 bytes after CRLF -> LF, formatted `<8 hex>:<byte length>`.
- Roots come from `default.project.json`: `src/shared`, `src/server`, `src/client`. `Packages/` and
  `ServerPackages/` are not checked.
- `init.luau`, `init.server.luau`, `init.client.luau` are the folder's own instance; `x.server.luau` Script,
  `x.client.luau` LocalScript, `x.luau`/`x.lua` ModuleScript. Other file kinds are skipped (currently only one `.md`).
- Studio side compares every LuaSourceContainer under the three roots by `GetFullName()`; SyncManifest modules are ignored.
