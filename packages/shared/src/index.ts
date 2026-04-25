export const EXTENSION_ID = "rtl-automation";
export const ACTIVITYBAR_VIEW_ID = "rtlAutomation";
export const SIDEBAR_VIEW_ID = "rtlAutomation.waveformView";

export const COMMAND_IDS = {
  openWaveformView: "rtlautomation.openWaveformView",
  startMcpServer: "rtlautomation.startMcpServer",
  showServerStatus: "rtlautomation.showServerStatus"
} as const;

export const CONFIG_KEYS = {
  autoStart: "rtlAutomation.server.autoStart",
  logLevel: "rtlAutomation.server.logLevel",
  pythonCommand: "rtlAutomation.server.pythonCommand",
  defaultBackend: "rtlAutomation.waveform.defaultBackend"
} as const;

export type ServerStatus = "stopped" | "starting" | "running" | "error";

export interface ServerLaunchOptions {
  cwd?: string;
  logLevel?: string;
  pythonCommand?: string;
  extensionPath?: string;
}

export type WaveformToolName =
  | "list_signals"
  | "find_nth_event"
  | "count_event_occurrences"
  | "annotate_wavedrom_bug";

export interface WaveformEventSpec {
  type: string;
  value?: string;
}

export interface WaveformToolBaseRequest {
  waveformFile: string;
  signals: string[];
  events: WaveformEventSpec[];
  afterTime?: number;
}

export interface ListSignalsRequest {
  waveformFile: string;
}

export interface FindNthEventRequest extends WaveformToolBaseRequest {
  n: number;
}

export type CountEventOccurrencesRequest = WaveformToolBaseRequest;

export interface AnnotateWavedromBugRequest {
  waveformFile: string;
  clockSignal: string;
  cycleStart: number;
  cycleEnd: number;
  signals: string[];
  diagnosis: string;
  contextCycles?: number;
  backgroundColor?: string;
}

export interface WaveformToolInfo {
  name: WaveformToolName | string;
  description?: string;
}

export interface WaveformToolResult {
  tool: WaveformToolName;
  result: Record<string, unknown>;
}

export interface WaveformDebugState {
  selectedWaveformFile: string | null;
  signalCount: number;
  lastSignalLoadStatus: "idle" | "loading" | "loaded" | "error";
  lastSignalLoadMessage?: string;
}

export interface WaveformSessionSummary {
  id: string;
  label: string;
  backend: string;
  status: "idle" | "active" | "error";
}

export type ExtensionWebviewMessage =
  | {
      type: "ready" | "show-status" | "pick-waveform-file";
    }
  | {
      type: "load-signal-options";
      payload: ListSignalsRequest;
    }
  | {
      type: "run-find-nth-event";
      payload: FindNthEventRequest;
    }
  | {
      type: "run-count-event-occurrences";
      payload: CountEventOccurrencesRequest;
    };

export type WebviewExtensionMessage =
  | {
      type: "server-status";
      payload: ServerStatus;
    }
  | {
      type: "tool-list";
      payload: WaveformToolInfo[];
    }
  | {
      type: "tool-result";
      payload: WaveformToolResult;
    }
  | {
      type: "tool-error";
      payload: {
        tool: WaveformToolName;
        message: string;
      };
    }
  | {
      type: "waveform-file-selected";
      payload: string | null;
    }
  | {
      type: "signal-options";
      payload: string[];
    }
  | {
      type: "debug-state";
      payload: WaveformDebugState;
    }
  | {
      type: "session-summary";
      payload: WaveformSessionSummary;
    };
