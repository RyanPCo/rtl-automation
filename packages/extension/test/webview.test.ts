import { describe, expect, it, vi } from "vitest";
import { WaveformViewProvider } from "../src/webview.js";

describe("WaveformViewProvider", () => {
  it("initializes HTML and responds to ready messages", () => {
    const postMessage = vi.fn();
    let messageHandler: ((message: { type: string }) => Promise<void>) | undefined;

    const provider = new WaveformViewProvider(
      { fsPath: "/tmp/ext" } as never,
      () => "running",
      () => [{ name: "find_nth_event" }, { name: "list_signals" }],
      async () => null,
      async () => ["top.clk"],
      async () => ({ time: 42 }),
      async () => ({ count: 3 })
    );

    provider.resolveWebviewView({
      webview: {
        cspSource: "csp",
        html: "",
        options: {},
        postMessage,
        onDidReceiveMessage(callback: (message: { type: string }) => Promise<void>) {
          messageHandler = callback;
          return { dispose() {} };
        }
      }
    } as never);

    expect(messageHandler).toBeTypeOf("function");
    void messageHandler?.({ type: "ready" });
    expect(postMessage).toHaveBeenCalledWith({
      type: "server-status",
      payload: "running"
    });
    expect(postMessage).toHaveBeenCalledWith({
      type: "tool-list",
      payload: [{ name: "find_nth_event" }, { name: "list_signals" }]
    });
  });
});

