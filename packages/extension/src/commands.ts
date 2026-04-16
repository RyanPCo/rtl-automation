import * as vscode from "vscode";
import { COMMAND_IDS, SIDEBAR_VIEW_ID } from "@rtl-automation/shared";
import type { ServerController } from "./serverController.js";
import type { WaveformViewProvider } from "./webview.js";

export const registerCommands = (
  context: vscode.ExtensionContext,
  serverController: ServerController,
  waveformView: WaveformViewProvider
): void => {
  context.subscriptions.push(
    vscode.commands.registerCommand(COMMAND_IDS.openWaveformView, async () => {
      await vscode.commands.executeCommand(`${SIDEBAR_VIEW_ID}.focus`);
    }),
    vscode.commands.registerCommand(COMMAND_IDS.startMcpServer, async () => {
      const status = await serverController.start();
      waveformView.postMessage({ type: "server-status", payload: status });
    }),
    vscode.commands.registerCommand(COMMAND_IDS.showServerStatus, async () => {
      const status = serverController.getStatus();
      await vscode.window.showInformationMessage(`RTL Automation MCP server: ${status}`);
      waveformView.postMessage({ type: "server-status", payload: status });
    })
  );
};

