import * as vscode from "vscode";

export interface Logger {
  info(message: string): void;
  error(message: string): void;
  dispose(): void;
}

export const createLogger = (): Logger => {
  const output = vscode.window.createOutputChannel("RTL Automation");

  return {
    info(message: string) {
      output.appendLine(`[info] ${message}`);
    },
    error(message: string) {
      output.appendLine(`[error] ${message}`);
    },
    dispose() {
      output.dispose();
    }
  };
};

