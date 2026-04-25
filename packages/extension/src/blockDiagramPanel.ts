import { randomBytes } from "node:crypto";
import * as path from "node:path";
import * as vscode from "vscode";
import type { ParseVerilogResult } from "@rtl-automation/shared";

type ParseFn = (file: string) => Promise<ParseVerilogResult>;

interface IncomingMessage {
  type: string;
  payload?: { file?: string; line?: number };
}

export class BlockDiagramPanel {
  public static readonly viewType = "rtlAutomation.blockDiagram";
  private static readonly panels = new Map<string, BlockDiagramPanel>();

  private readonly disposables: vscode.Disposable[] = [];

  static createOrShow(
    extensionUri: vscode.Uri,
    filePath: string,
    parseFn: ParseFn
  ): void {
    const existing = BlockDiagramPanel.panels.get(filePath);
    if (existing) {
      existing.panel.reveal(vscode.ViewColumn.Beside);
      return;
    }

    const panel = vscode.window.createWebviewPanel(
      BlockDiagramPanel.viewType,
      `Block Diagram: ${path.basename(filePath)}`,
      vscode.ViewColumn.Beside,
      {
        enableScripts: true,
        retainContextWhenHidden: true,
        localResourceRoots: [vscode.Uri.joinPath(extensionUri, "dist")]
      }
    );

    BlockDiagramPanel.panels.set(
      filePath,
      new BlockDiagramPanel(panel, extensionUri, filePath, parseFn)
    );
  }

  private constructor(
    private readonly panel: vscode.WebviewPanel,
    private readonly extensionUri: vscode.Uri,
    private readonly filePath: string,
    private readonly parseFn: ParseFn
  ) {
    panel.webview.html = this.getHtml(panel.webview);

    panel.webview.onDidReceiveMessage(
      (msg: IncomingMessage) => {
        void this.onMessage(msg);
      },
      null,
      this.disposables
    );
    panel.onDidDispose(() => this.dispose(), null, this.disposables);

    vscode.workspace.onDidSaveTextDocument(
      (doc) => {
        if (doc.uri.fsPath === this.filePath) {
          void this.refresh();
        }
      },
      null,
      this.disposables
    );
  }

  private async refresh(): Promise<void> {
    try {
      const data = await this.parseFn(this.filePath);
      void this.panel.webview.postMessage({ type: "diagram-data", payload: data });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      void this.panel.webview.postMessage({
        type: "diagram-error",
        payload: { message }
      });
    }
  }

  private async onMessage(message: IncomingMessage): Promise<void> {
    if (message.type === "ready") {
      await this.refresh();
      return;
    }
    if (message.type === "navigate-to-line") {
      const file = message.payload?.file;
      const line = message.payload?.line;
      if (typeof file !== "string" || typeof line !== "number") return;
      const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(file));
      const targetLine = Math.max(0, line - 1);
      await vscode.window.showTextDocument(doc, {
        viewColumn: vscode.ViewColumn.One,
        selection: new vscode.Range(targetLine, 0, targetLine, 0),
        preserveFocus: false
      });
    }
  }

  private getHtml(webview: vscode.Webview): string {
    const scriptUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, "dist", "blockDiagramWebview.js")
    );
    const cssUri = webview.asWebviewUri(
      vscode.Uri.joinPath(this.extensionUri, "dist", "blockDiagramWebview.css")
    );
    const nonce = randomBytes(16).toString("base64");
    const csp = [
      "default-src 'none'",
      `img-src ${webview.cspSource} data:`,
      `style-src ${webview.cspSource} 'unsafe-inline'`,
      `font-src ${webview.cspSource}`,
      `script-src 'nonce-${nonce}'`
    ].join("; ");

    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="Content-Security-Policy" content="${csp}" />
  <link rel="stylesheet" href="${cssUri}" />
  <style>
    html, body, #root { height: 100%; margin: 0; padding: 0; }
    body { background: var(--vscode-editor-background, #1e1e1e); }
  </style>
</head>
<body>
  <div id="root"></div>
  <script nonce="${nonce}" src="${scriptUri}"></script>
</body>
</html>`;
  }

  private dispose(): void {
    BlockDiagramPanel.panels.delete(this.filePath);
    this.panel.dispose();
    while (this.disposables.length) {
      const d = this.disposables.pop();
      d?.dispose();
    }
  }
}
