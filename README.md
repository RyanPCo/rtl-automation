# RTL Automation

Cursor and VS Code extension scaffold for RTL design automation, with a separate stdio MCP server package and shared types.

## Workspace

- `packages/extension`: extension host, commands, webview shell, and MCP server process management
- `packages/mcp-server`: standalone stdio server shell
- `packages/shared`: command IDs, config keys, and shared message/status types

## Commands

```bash
npm install
npm run build
npm run typecheck
npm run lint
npm test
npm run package:vsix
```

## Test in Cursor (Developer Workflow)

1. Install deps once:
   ```bash
   npm install
   ```
2. Start shared package watch mode in a terminal:
   ```bash
   npm run watch
   ```
3. In Cursor, open **Run and Debug** and launch `Run Extension` (from `.vscode/launch.json`).
4. In the Extension Development Host window, run:
   - `RTL Automation: Open Waveform View`
   - `RTL Automation: Start MCP Server`
   - `RTL Automation: Show Server Status`

## Architecture

The extension package owns editor integration and UI. The MCP server package owns the separate process boundary and stdio lifecycle. The shared package exports the canonical IDs and interfaces used by both so future waveform and debugging features can be added without duplicating protocol strings or state shapes.

