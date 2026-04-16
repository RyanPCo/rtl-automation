import { describe, expect, it, vi } from "vitest";
import { WaveformViewProvider } from "../src/webview.js";

describe("WaveformViewProvider", () => {
  it("initializes HTML and responds to ready messages", () => {
    const postMessage = vi.fn();
    let messageHandler: ((message: { type: string }) => void) | undefined;

    const provider = new WaveformViewProvider(
      { fsPath: "/tmp/ext" } as never,
      () => "running"
    );

    provider.resolveWebviewView({
      webview: {
        cspSource: "csp",
        html: "",
        options: {},
        postMessage,
        onDidReceiveMessage(callback: (message: { type: string }) => void) {
          messageHandler = callback;
          return { dispose() {} };
        }
      }
    } as never);

    expect(messageHandler).toBeTypeOf("function");
    messageHandler?.({ type: "ready" });
    expect(postMessage).toHaveBeenCalledWith({
      type: "server-status",
      payload: "running"
    });
  });
});

