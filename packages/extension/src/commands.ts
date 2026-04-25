import * as vscode from "vscode";
import { COMMAND_IDS, SIDEBAR_VIEW_ID } from "@rtl-automation/shared";
import { BlockDiagramPanel } from "./blockDiagramPanel.js";
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
      waveformView.postMessage({ type: "tool-list", payload: serverController.getTools() });
    }),
    vscode.commands.registerCommand(COMMAND_IDS.showServerStatus, async () => {
      const status = serverController.getStatus();
      await vscode.window.showInformationMessage(`RTL Automation MCP server: ${status}`);
      waveformView.postMessage({ type: "server-status", payload: status });
      waveformView.postMessage({ type: "tool-list", payload: serverController.getTools() });
    }),
    vscode.commands.registerCommand(
      COMMAND_IDS.openBlockDiagram,
      async (uri?: vscode.Uri) => {
        const filePath =
          uri?.fsPath ?? vscode.window.activeTextEditor?.document.uri.fsPath;
        if (!filePath || !/\.(v|sv)$/i.test(filePath)) {
          await vscode.window.showErrorMessage(
            "Open Block Diagram: select a .v or .sv file."
          );
          return;
        }
        BlockDiagramPanel.createOrShow(
          context.extensionUri,
          filePath,
          (file) => serverController.parseVerilog({ verilogFile: file })
        );
      }
    )
  );
};

