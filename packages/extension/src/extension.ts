import * as vscode from "vscode";
import { COMMAND_IDS, CONFIG_KEYS, SIDEBAR_VIEW_ID } from "@rtl-automation/shared";
import { registerCommands } from "./commands.js";
import { getExtensionConfig } from "./config.js";
import { createLogger } from "./logging.js";
import { ServerController } from "./serverController.js";
import { WaveformViewProvider } from "./webview.js";

export const activate = async (context: vscode.ExtensionContext): Promise<void> => {
  const logger = createLogger();
  const config = getExtensionConfig();
  const serverController = new ServerController(logger, {
    cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
    logLevel: config.logLevel
  });

  const waveformView = new WaveformViewProvider(
    context.extensionUri,
    () => serverController.getStatus()
  );

  context.subscriptions.push(
    logger,
    vscode.window.registerWebviewViewProvider(SIDEBAR_VIEW_ID, waveformView)
  );

  registerCommands(context, serverController, waveformView);
  logger.info(`Registered commands: ${Object.values(COMMAND_IDS).join(", ")}`);
  logger.info(`Config keys: ${Object.values(CONFIG_KEYS).join(", ")}`);

  if (config.autoStart) {
    await serverController.start();
  }
};

export const deactivate = async (): Promise<void> => Promise.resolve();

