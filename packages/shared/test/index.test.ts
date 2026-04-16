import { describe, expect, it } from "vitest";
import {
  COMMAND_IDS,
  CONFIG_KEYS,
  SIDEBAR_VIEW_ID,
  type ExtensionWebviewMessage,
  type ServerLaunchOptions,
  type ServerStatus
} from "../src/index.js";

describe("shared exports", () => {
  it("exposes canonical IDs", () => {
    expect(COMMAND_IDS.openWaveformView).toBe("rtlautomation.openWaveformView");
    expect(CONFIG_KEYS.autoStart).toBe("rtlAutomation.server.autoStart");
    expect(SIDEBAR_VIEW_ID).toBe("rtlAutomation.waveformView");
  });

  it("supports shared type imports", () => {
    const status: ServerStatus = "running";
    const options: ServerLaunchOptions = { cwd: "/tmp", logLevel: "info" };
    const message: ExtensionWebviewMessage = { type: "ready" };

    expect(status).toBe("running");
    expect(options.cwd).toBe("/tmp");
    expect(message.type).toBe("ready");
  });
});

