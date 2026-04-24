import * as vscode from "vscode";
import { COMMAND_IDS, CONFIG_KEYS, SIDEBAR_VIEW_ID } from "@rtl-automation/shared";
import { registerCommands } from "./commands.js";
import { getExtensionConfig } from "./config.js";
import { createLogger } from "./logging.js";
import { ServerController } from "./serverController.js";
import { WaveformViewProvider } from "./webview.js";

let activeServerController: ServerController | undefined;

export const activate = async (context: vscode.ExtensionContext): Promise<void> => {
  const logger = createLogger();
  const config = getExtensionConfig();
  const serverController = new ServerController(logger, {
    cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
    logLevel: config.logLevel,
    pythonCommand: config.pythonCommand,
    extensionPath: context.extensionUri.fsPath
  });
  activeServerController = serverController;

  const waveformView = new WaveformViewProvider(
    context.extensionUri,
    () => serverController.getStatus(),
    () => serverController.getTools(),
    async () => {
      const selection = await vscode.window.showOpenDialog({
        canSelectFiles: true,
        canSelectFolders: false,
        canSelectMany: false,
        filters: {
          Waveforms: ["vcd", "fst"]
        }
      });

      return selection?.[0]?.fsPath ?? null;
    },
    (payload) => serverController.listSignals(payload),
    (payload) => serverController.findNthEvent(payload),
    (payload) => serverController.countEventOccurrences(payload)
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

export const deactivate = async (): Promise<void> => {
  await activeServerController?.stop();
  activeServerController = undefined;
};

