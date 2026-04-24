import * as vscode from "vscode";
import type {
  CountEventOccurrencesRequest,
  ExtensionWebviewMessage,
  FindNthEventRequest,
  ListSignalsRequest,
  ServerStatus,
  WaveformDebugState,
  WaveformToolInfo,
  WebviewExtensionMessage
} from "@rtl-automation/shared";

export class WaveformViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "rtlAutomation.waveformView";

  private view?: vscode.WebviewView;
  private debugState: WaveformDebugState = {
    selectedWaveformFile: null,
    signalCount: 0,
    lastSignalLoadStatus: "idle"
  };

  constructor(
    private readonly extensionUri: vscode.Uri,
    private readonly getServerStatus: () => ServerStatus,
    private readonly getAvailableTools: () => WaveformToolInfo[],
    private readonly pickWaveformFile: () => Promise<string | null>,
    private readonly loadSignalOptions: (payload: ListSignalsRequest) => Promise<string[]>,
    private readonly runFindNthEvent: (payload: FindNthEventRequest) => Promise<Record<string, unknown>>,
    private readonly runCountEventOccurrences: (
      payload: CountEventOccurrencesRequest
    ) => Promise<Record<string, unknown>>
  ) {}

  resolveWebviewView(view: vscode.WebviewView): void {
    this.view = view;
    view.webview.options = {
      enableScripts: true,
      localResourceRoots: [this.extensionUri]
    };
    view.webview.html = this.getHtml(view.webview);

    view.webview.onDidReceiveMessage(async (message: ExtensionWebviewMessage) => {
      switch (message.type) {
        case "ready":
        case "show-status":
          this.syncState();
          break;
        case "pick-waveform-file": {
          const filePath = await this.pickWaveformFile();
          this.postMessage({
            type: "waveform-file-selected",
            payload: filePath
          });
          if (filePath) {
            await this.handleSignalLoad(filePath);
          }
          break;
        }
        case "load-signal-options":
          await this.handleSignalLoad(message.payload.waveformFile);
          break;
        case "run-find-nth-event":
          await this.handleToolCall("find_nth_event", () => this.runFindNthEvent(message.payload));
          break;
        case "run-count-event-occurrences":
          await this.handleToolCall("count_event_occurrences", () =>
            this.runCountEventOccurrences(message.payload)
          );
          break;
      }
    });
  }

  postMessage(message: WebviewExtensionMessage): void {
    void this.view?.webview.postMessage(message);
  }

  private syncState(): void {
    this.postMessage({
      type: "server-status",
      payload: this.getServerStatus()
    });
    this.postMessage({
      type: "tool-list",
      payload: this.getAvailableTools()
    });
    this.postMessage({
      type: "debug-state",
      payload: this.debugState
    });
  }

  private async handleToolCall(
    tool: "find_nth_event" | "count_event_occurrences",
    action: () => Promise<Record<string, unknown>>
  ): Promise<void> {
    try {
      const result = await action();
      this.syncState();
      this.postMessage({
        type: "tool-result",
        payload: {
          tool,
          result
        }
      });
    } catch (error) {
      this.syncState();
      this.postMessage({
        type: "tool-error",
        payload: {
          tool,
          message: error instanceof Error ? error.message : String(error)
        }
      });
    }
  }

  private async handleSignalLoad(waveformFile: string): Promise<void> {
    this.debugState = {
      selectedWaveformFile: waveformFile,
      signalCount: 0,
      lastSignalLoadStatus: "loading",
      lastSignalLoadMessage: "Loading signals..."
    };
    this.postMessage({
      type: "debug-state",
      payload: this.debugState
    });

    try {
      const signals = await this.loadSignalOptions({ waveformFile });
      this.debugState = {
        selectedWaveformFile: waveformFile,
        signalCount: signals.length,
        lastSignalLoadStatus: "loaded",
        lastSignalLoadMessage: `Loaded ${signals.length} signals`
      };
      this.postMessage({
        type: "signal-options",
        payload: signals
      });
      this.postMessage({
        type: "debug-state",
        payload: this.debugState
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.debugState = {
        selectedWaveformFile: waveformFile,
        signalCount: 0,
        lastSignalLoadStatus: "error",
        lastSignalLoadMessage: message
      };
      this.postMessage({
        type: "tool-error",
        payload: {
          tool: "list_signals",
          message
        }
      });
      this.postMessage({
        type: "debug-state",
        payload: this.debugState
      });
    }
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
      .status,
      .tools {
        margin-top: 12px;
        font-weight: 700;
      }
      .form {
        display: grid;
        gap: 12px;
        margin-top: 16px;
      }
      label {
        display: grid;
        gap: 6px;
        font-size: 12px;
      }
      input,
      select,
      button {
        font: inherit;
      }
      input,
      select {
        width: 100%;
        box-sizing: border-box;
        border: 1px solid rgba(127, 127, 127, 0.35);
        border-radius: 8px;
        padding: 8px 10px;
        background: transparent;
        color: inherit;
      }
      .row {
        display: flex;
        gap: 8px;
      }
      .row > * {
        flex: 1;
      }
      .actions {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
      }
      button {
        border: 1px solid rgba(127, 127, 127, 0.35);
        border-radius: 999px;
        padding: 8px 12px;
        background: transparent;
        cursor: pointer;
      }
      pre {
        margin: 12px 0 0;
        font-size: 12px;
        line-height: 1.5;
        white-space: pre-wrap;
        word-break: break-word;
      }
      .signal-row {
        display: grid;
        gap: 8px;
        padding: 10px;
        border: 1px solid rgba(127, 127, 127, 0.2);
        border-radius: 10px;
      }
      .hint {
        font-size: 11px;
        opacity: 0.8;
      }
    </style>
  </head>
  <body>
    <div class="shell">
      <h1>Waveform Workspace</h1>
      <p>Run the real waveform_mcp tools against a selected waveform file.</p>
      <div class="status" id="status">Server status: loading</div>
      <div class="tools" id="tools">Available tools: loading</div>
      <pre id="debugState">Debug: waiting for waveform selection</pre>
      <div class="form">
        <label>
          Waveform file
          <div class="row">
            <input id="waveformFile" type="text" placeholder="/absolute/path/to/waveform.vcd" />
            <button id="pickWaveformFile" type="button">Browse</button>
          </div>
        </label>
        <div>
          <div class="row" style="justify-content: space-between; align-items: center;">
            <label style="gap: 0;">Signal/event rows</label>
            <button id="addSignalRow" type="button">Add signal</button>
          </div>
          <div class="hint">Pick a waveform to load all available signals into the dropdowns.</div>
          <div class="form" id="signalRows"></div>
        </div>
        <div class="row">
          <label>
            After time
            <input id="afterTime" type="number" min="0" value="0" />
          </label>
          <label>
            Nth occurrence
            <input id="nthOccurrence" type="number" min="1" value="1" />
          </label>
        </div>
        <div class="actions">
          <button id="countEvents" type="button">Count event occurrences</button>
          <button id="findNthEvent" type="button">Find nth event</button>
          <button id="refreshStatus" type="button">Refresh status</button>
        </div>
      </div>
      <pre id="result">No MCP tool call run yet.</pre>
    </div>
    <script nonce="${nonce}">
      const vscode = acquireVsCodeApi();
      const waveformFileInput = document.getElementById("waveformFile");
      const afterTimeInput = document.getElementById("afterTime");
      const nthOccurrenceInput = document.getElementById("nthOccurrence");
      const resultEl = document.getElementById("result");
      const toolsEl = document.getElementById("tools");
      const debugStateEl = document.getElementById("debugState");
      const signalRowsEl = document.getElementById("signalRows");
      const eventTypes = [
        "rise",
        "fall",
        "become_x",
        "become_z",
        "unbecome_x",
        "unbecome_z",
        "transition_to"
      ];
      let signalOptions = [];

      const setResult = (value) => {
        resultEl.textContent = typeof value === "string" ? value : JSON.stringify(value, null, 2);
      };

      const setDebugState = (payload) => {
        debugStateEl.textContent = [
          "Selected file: " + (payload.selectedWaveformFile || "(none)"),
          "Signal count: " + payload.signalCount,
          "Signal load status: " + payload.lastSignalLoadStatus,
          "Signal load message: " + (payload.lastSignalLoadMessage || "")
        ].join("\\n");
      };

      const createOptionMarkup = (value, label, selectedValue = "") =>
        '<option value="' + value + '"' + (value === selectedValue ? " selected" : "") + ">" + label + "</option>";

      const renderSignalRows = () => {
        const rows = Array.from(signalRowsEl.querySelectorAll(".signal-row"));
        if (rows.length === 0) {
          addSignalRow();
          return;
        }

        rows.forEach((row) => {
          const signalSelect = row.querySelector(".signal-select");
          const selectedSignal = signalSelect ? signalSelect.value : "";
          signalSelect.innerHTML = [
            createOptionMarkup("", signalOptions.length ? "Select a signal" : "No signals loaded", ""),
            ...signalOptions.map((signal) => createOptionMarkup(signal, signal, selectedSignal))
          ].join("");

          const eventSelect = row.querySelector(".event-type-select");
          const valueInput = row.querySelector(".event-value-input");
          valueInput.style.display = eventSelect.value === "transition_to" ? "block" : "none";
        });
      };

      const addSignalRow = () => {
        const row = document.createElement("div");
        row.className = "signal-row";
        row.innerHTML = [
          '<label>Signal<select class="signal-select"></select></label>',
          '<label>Event type<select class="event-type-select">' +
            eventTypes.map((type) => createOptionMarkup(type, type, "rise")).join("") +
            "</select></label>",
          '<label>Transition value<input class="event-value-input" type="text" placeholder="b1010" style="display:none;" /></label>',
          '<button class="remove-signal-row" type="button">Remove</button>'
        ].join("");

        row.querySelector(".event-type-select").addEventListener("change", (event) => {
          const nextType = event.target.value;
          row.querySelector(".event-value-input").style.display =
            nextType === "transition_to" ? "block" : "none";
        });

        row.querySelector(".remove-signal-row").addEventListener("click", () => {
          row.remove();
          if (signalRowsEl.children.length === 0) {
            addSignalRow();
          }
        });

        signalRowsEl.appendChild(row);
        renderSignalRows();
      };

      const parsePayload = (includeNth) => {
        const waveformFile = waveformFileInput.value.trim();

        if (!waveformFile) {
          setResult("Pick a waveform file first.");
          return null;
        }

        const rows = Array.from(signalRowsEl.querySelectorAll(".signal-row"));
        const signals = [];
        const events = [];

        for (const row of rows) {
          const signal = row.querySelector(".signal-select").value;
          const eventType = row.querySelector(".event-type-select").value;
          const transitionValue = row.querySelector(".event-value-input").value.trim();

          if (!signal) {
            continue;
          }

          if (eventType === "transition_to" && !transitionValue) {
            setResult("Each transition_to row needs a value.");
            return null;
          }

          signals.push(signal);
          events.push(
            eventType === "transition_to"
              ? { type: eventType, value: transitionValue }
              : { type: eventType }
          );
        }

        if (signals.length === 0) {
          setResult("Select at least one signal.");
          return null;
        }

        const payload = {
          waveformFile,
          signals,
          events,
          afterTime: Number(afterTimeInput.value || "0")
        };

        if (includeNth) {
          return {
            ...payload,
            n: Number(nthOccurrenceInput.value || "1")
          };
        }

        return payload;
      };

      window.addEventListener("message", (event) => {
        const message = event.data;
        if (message.type === "server-status") {
          document.getElementById("status").textContent = "Server status: " + message.payload;
        }
        if (message.type === "tool-list") {
          const toolNames = (message.payload || []).map((tool) => tool.name).join(", ");
          toolsEl.textContent = "Available tools: " + (toolNames || "not connected");
        }
        if (message.type === "waveform-file-selected" && message.payload) {
          waveformFileInput.value = message.payload;
        }
        if (message.type === "signal-options") {
          signalOptions = message.payload || [];
          renderSignalRows();
          if (signalOptions.length === 0) {
            setResult("No signals found in waveform.");
          }
        }
        if (message.type === "debug-state") {
          setDebugState(message.payload);
        }
        if (message.type === "tool-result") {
          setResult(message.payload);
        }
        if (message.type === "tool-error") {
          setResult("Error running " + message.payload.tool + ": " + message.payload.message);
        }
      });

      document.getElementById("pickWaveformFile").addEventListener("click", () => {
        vscode.postMessage({ type: "pick-waveform-file" });
      });

      waveformFileInput.addEventListener("change", () => {
        const waveformFile = waveformFileInput.value.trim();
        if (!waveformFile) {
          return;
        }
        vscode.postMessage({ type: "load-signal-options", payload: { waveformFile } });
      });

      document.getElementById("addSignalRow").addEventListener("click", () => {
        addSignalRow();
      });

      document.getElementById("countEvents").addEventListener("click", () => {
        const payload = parsePayload(false);
        if (!payload) {
          return;
        }
        setResult("Running count_event_occurrences...");
        vscode.postMessage({ type: "run-count-event-occurrences", payload });
      });

      document.getElementById("findNthEvent").addEventListener("click", () => {
        const payload = parsePayload(true);
        if (!payload) {
          return;
        }
        setResult("Running find_nth_event...");
        vscode.postMessage({ type: "run-find-nth-event", payload });
      });

      document.getElementById("refreshStatus").addEventListener("click", () => {
        vscode.postMessage({ type: "show-status" });
      });

      addSignalRow();
      vscode.postMessage({ type: "ready" });
    </script>
  </body>
</html>`;
  }
}

