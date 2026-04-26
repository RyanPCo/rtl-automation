export const EXTENSION_ID = "rtl-automation";
export const ACTIVITYBAR_VIEW_ID = "rtlAutomation";
export const SIDEBAR_VIEW_ID = "rtlAutomation.waveformView";

export const COMMAND_IDS = {
  openWaveformView: "rtlautomation.openWaveformView",
  startMcpServer: "rtlautomation.startMcpServer",
  showServerStatus: "rtlautomation.showServerStatus",
  openBlockDiagram: "rtlautomation.openBlockDiagram"
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
  | "parse_verilog";

export interface VerilogPort {
  name: string;
  direction: "input" | "output" | "inout";
  width: string;
  line: number;
}

export interface VerilogNet {
  name: string;
  kind: "wire" | "reg";
  width: string;
  line: number;
}

export interface VerilogConnection {
  port: string;
  net: string;
  net_idents: string[];
  direction: "input" | "output" | "inout" | "unknown";
}

export interface VerilogInstance {
  module_type: string;
  instance_name: string;
  line: number;
  connections: VerilogConnection[];
}

export interface VerilogModuleInfo {
  name: string;
  line: number;
  ports: VerilogPort[];
}

export interface VerilogHierarchyNode {
  id: string;
  moduleName: string;
  instanceName?: string;
  definitionFile?: string;
  definitionLine?: number;
  instanceFile: string;
  instanceLine: number;
  ports: VerilogPort[];
  nets?: VerilogNet[];
  connections?: VerilogConnection[];
  instances?: VerilogInstance[];
  assigns?: VerilogAssign[];
  procedurals?: VerilogProcedural[];
  children: VerilogHierarchyNode[];
  unresolved?: boolean;
}

export interface VerilogAssign {
  lhs: string;
  rhs_idents: string[];
  line: number;
}

export interface VerilogProcedural {
  kind: string;
  reads: string[];
  writes: string[];
  line: number;
}

export interface ParseVerilogResult {
  file: string;
  module: VerilogModuleInfo;
  nets: VerilogNet[];
  instances: VerilogInstance[];
  assigns: VerilogAssign[];
  procedurals: VerilogProcedural[];
  hierarchy?: VerilogHierarchyNode;
}

export interface ParseVerilogRequest {
  verilogFile: string;
}

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
    }
  | {
      type: "diagram-data";
      payload: ParseVerilogResult;
    }
  | {
      type: "diagram-error";
      payload: { message: string };
    };

export type BlockDiagramWebviewMessage =
  | { type: "ready" }
  | {
      type: "navigate-to-line";
      payload: { file: string; line: number };
    };
