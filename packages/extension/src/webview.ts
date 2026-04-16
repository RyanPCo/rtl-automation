import * as vscode from "vscode";
import type { ExtensionWebviewMessage, ServerStatus, WebviewExtensionMessage } from "@rtl-automation/shared";

export class WaveformViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "rtlAutomation.waveformView";

  private view?: vscode.WebviewView;

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly getServerStatus: () => ServerStatus
  ) {}

  resolveWebviewView(view: vscode.WebviewView): void {
    this.view = view;
    view.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };
    view.webview.html = this.getHtml(view.webview);

    view.webview.onDidReceiveMessage((message: ExtensionWebviewMessage) => {
      if (message.type === "ready" || message.type === "show-status") {
        this.postMessage({
          type: "server-status",
          payload: this.getServerStatus()
        });
      }
    });
  }

  postMessage(message: WebviewExtensionMessage): void {
    void this.view?.webview.postMessage(message);
  }

  private getHtml(webview: vscode.Webview): string {
    const nonce = String(Date.now());
    const cspSource = webview.cspSource;

    return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${cspSource} 'unsafe-inline'; script-src 'nonce-${nonce}';" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>RTL Automation</title>
    <style>
      :root {
        color-scheme: dark light;
        font-family: ui-monospace, "SF Mono", Menlo, monospace;
      }
      body {
        margin: 0;
        padding: 16px;
      }
      .shell {
        border: 1px solid rgba(127, 127, 127, 0.35);
        border-radius: 12px;
        padding: 16px;
      }
      h1 {
        font-size: 14px;
        margin: 0 0 8px;
        text-transform: uppercase;
        letter-spacing: 0.12em;
      }
      p {
        font-size: 12px;
        line-height: 1.5;
      }
      .status {
        margin-top: 12px;
        font-weight: 700;
      }
    </style>
  </head>
  <body>
    <div class="shell">
      <h1>Waveform Workspace</h1>
      <p>Sidebar shell for waveform sessions, debug controls, and future MCP-backed tooling.</p>
      <div class="status" id="status">Server status: loading</div>
    </div>
    <script nonce="${nonce}">
      const vscode = acquireVsCodeApi();
      window.addEventListener("message", (event) => {
        const message = event.data;
        if (message.type === "server-status") {
          document.getElementById("status").textContent = "Server status: " + message.payload;
        }
      });
      vscode.postMessage({ type: "ready" });
    </script>
  </body>
</html>`;
  }
}

