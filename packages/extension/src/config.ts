import * as vscode from "vscode";
import { CONFIG_KEYS } from "@rtl-automation/shared";

export interface ExtensionConfig {
  autoStart: boolean;
  logLevel: string;
  defaultBackend: string;
}

export const getExtensionConfig = (): ExtensionConfig => {
  const config = vscode.workspace.getConfiguration();

  return {
    autoStart: config.get<boolean>(CONFIG_KEYS.autoStart, false),
    logLevel: config.get<string>(CONFIG_KEYS.logLevel, "info"),
    defaultBackend: config.get<string>(CONFIG_KEYS.defaultBackend, "stub")
  };
};

