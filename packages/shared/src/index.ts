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
  defaultBackend: "rtlAutomation.waveform.defaultBackend"
} as const;

export type ServerStatus = "stopped" | "starting" | "running" | "error";

export interface ServerLaunchOptions {
  cwd?: string;
  logLevel?: string;
}

export interface WaveformSessionSummary {
  id: string;
  label: string;
  backend: string;
  status: "idle" | "active" | "error";
}

export interface ExtensionWebviewMessage {
  type: "ready" | "start-server" | "show-status";
  payload?: Record<string, unknown>;
}

export interface WebviewExtensionMessage {
  type: "server-status" | "session-summary";
  payload?: ServerStatus | WaveformSessionSummary;
}

