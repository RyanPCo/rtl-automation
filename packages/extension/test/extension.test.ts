import { beforeEach, describe, expect, it, vi } from "vitest";
import type * as vscodeType from "vscode";

const registerCommand = vi.fn((_id: string, callback: (...args: unknown[]) => unknown) => ({
  dispose: vi.fn(),
  callback
}));
const executeCommand = vi.fn();
const showInformationMessage = vi.fn();
const registerWebviewViewProvider = vi.fn(() => ({ dispose: vi.fn() }));
const createOutputChannel = vi.fn(() => ({
  appendLine: vi.fn(),
  dispose: vi.fn()
}));
const getConfiguration = vi.fn(() => ({
  get: vi.fn((key: string, fallback: unknown) => fallback)
}));

vi.mock("vscode", () => {
  const vscode: Partial<typeof vscodeType> = {
    commands: {
      registerCommand,
      executeCommand
    } as unknown as typeof vscodeType.commands,
    window: {
      registerWebviewViewProvider,
      createOutputChannel,
      showInformationMessage
    } as unknown as typeof vscodeType.window,
    workspace: {
      getConfiguration,
      workspaceFolders: []
    } as unknown as typeof vscodeType.workspace
  };

  return vscode;
});

describe("extension activation", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("registers commands and the webview provider", async () => {
    const { activate } = await import("../src/extension.js");

    const context = {
      extensionUri: { fsPath: "/tmp/ext" },
      subscriptions: []
    } as unknown as vscodeType.ExtensionContext;

    await activate(context);

    expect(registerWebviewViewProvider).toHaveBeenCalledWith(
      "rtlAutomation.waveformView",
      expect.anything()
    );
    expect(registerCommand).toHaveBeenCalledTimes(3);
  });
});

