import fs from "node:fs";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import type {
  CountEventOccurrencesRequest,
  FindNthEventRequest,
  ListSignalsRequest,
  ParseVerilogRequest,
  ParseVerilogResult,
  ServerLaunchOptions,
  ServerStatus,
  WaveformToolInfo
} from "@rtl-automation/shared";
import type { Logger } from "./logging.js";

export class ServerController {
  private client?: Client;
  private transport?: StdioClientTransport;
  private status: ServerStatus = "stopped";
  private tools: WaveformToolInfo[] = [];

  constructor(
    private readonly logger: Logger,
    private readonly options: ServerLaunchOptions = {}
  ) {}

  getStatus(): ServerStatus {
    return this.status;
  }

  getTools(): WaveformToolInfo[] {
    return this.tools;
  }

  async start(): Promise<ServerStatus> {
    if (this.client && this.transport) {
      return this.status;
    }

    this.status = "starting";
    const serverRoot = this.resolveServerRoot();

    if (!fs.existsSync(serverRoot)) {
      this.status = "error";
      this.logger.error(`waveform_mcp server root not found at ${serverRoot}`);
      return this.status;
    }

    const pythonCommand = this.options.pythonCommand ?? "python3";
    this.logger.info(`Starting waveform_mcp with ${pythonCommand} from ${serverRoot}`);

    const transport = new StdioClientTransport({
      command: pythonCommand,
      args: ["-m", "waveform_mcp.server"],
      cwd: serverRoot,
      env: this.getServerEnvironment(),
      stderr: "pipe"
    });
    const client = new Client(
      {
        name: "rtl-automation-extension",
        version: "0.1.0"
      },
      {
        capabilities: {}
      }
    );

    transport.stderr?.on("data", (chunk) => {
      const message = String(chunk).trim();
      if (message) {
        this.logger.info(message);
      }
    });

    transport.onerror = (error) => {
      this.logger.error(`MCP transport error: ${error.message}`);
      this.status = "error";
    };

    transport.onclose = () => {
      this.logger.info("MCP server connection closed");
      this.client = undefined;
      this.transport = undefined;
      this.tools = [];
      if (this.status !== "error") {
        this.status = "stopped";
      }
    };

    try {
      await client.connect(transport);
      const toolList = await client.listTools();

      this.client = client;
      this.transport = transport;
      this.tools = toolList.tools.map((tool) => ({
        name: tool.name,
        description: tool.description
      }));
      this.status = "running";
      this.logger.info(
        `Connected to waveform_mcp tools: ${this.tools.map((tool) => tool.name).join(", ")}`
      );
      return this.status;
    } catch (error) {
      this.status = "error";
      this.client = undefined;
      this.transport = undefined;
      this.tools = [];
      await transport.close().catch(() => undefined);
      this.logger.error(this.formatError("Failed to start MCP server", error));
      return this.status;
    }
  }

  async findNthEvent(payload: FindNthEventRequest): Promise<Record<string, unknown>> {
    return this.callTool("find_nth_event", {
      waveform_file: payload.waveformFile,
      signals: payload.signals,
      events: payload.events,
      n: payload.n,
      after_time: payload.afterTime ?? 0
    });
  }

  async countEventOccurrences(
    payload: CountEventOccurrencesRequest
  ): Promise<Record<string, unknown>> {
    return this.callTool("count_event_occurrences", {
      waveform_file: payload.waveformFile,
      signals: payload.signals,
      events: payload.events,
      after_time: payload.afterTime ?? 0
    });
  }

  async listSignals(payload: ListSignalsRequest): Promise<string[]> {
    const result = await this.callTool("list_signals", {
      waveform_file: payload.waveformFile
    });
    const signalList = result.signals;

    if (!Array.isArray(signalList) || signalList.some((signal) => typeof signal !== "string")) {
      throw new Error("list_signals: invalid signal list returned by server");
    }

    return signalList;
  }

  async parseVerilog(payload: ParseVerilogRequest): Promise<ParseVerilogResult> {
    const result = await this.callTool("parse_verilog", {
      verilog_file: payload.verilogFile
    });
    return result as unknown as ParseVerilogResult;
  }

  async stop(): Promise<void> {
    if (!this.transport) {
      this.status = "stopped";
      return;
    }

    await this.transport.close();
    this.transport = undefined;
    this.client = undefined;
    this.tools = [];
    this.status = "stopped";
  }

  private async ensureStarted(): Promise<void> {
    const status = await this.start();
    if (status !== "running" || !this.client) {
      throw new Error("MCP server is not running");
    }
  }

  private async callTool(
    toolName: string,
    args: Record<string, unknown>
  ): Promise<Record<string, unknown>> {
    await this.ensureStarted();

    const result = await this.client!.callTool({
      name: toolName,
      arguments: args
    });

    if ("toolResult" in result) {
      return this.parseToolPayload(toolName, result.toolResult);
    }

    const textParts = result.content
      .filter((item): item is { type: "text"; text: string } => item.type === "text")
      .map((item) => item.text)
      .filter(Boolean);

    if (result.isError) {
      throw new Error(textParts.join("\n") || `${toolName} failed`);
    }

    if (result.structuredContent) {
      return this.parseToolPayload(toolName, result.structuredContent);
    }

    if (textParts.length === 0) {
      return {};
    }

    return this.parseToolPayload(toolName, textParts.join("\n"));
  }

  private parseToolPayload(
    toolName: string,
    payload: unknown
  ): Record<string, unknown> {
    const parsed = this.coerceRecord(payload);

    if ("error" in parsed && typeof parsed.error === "string") {
      throw new Error(`${toolName}: ${parsed.error}`);
    }

    return parsed;
  }

  private coerceRecord(payload: unknown): Record<string, unknown> {
    if (typeof payload === "string") {
      const parsed = JSON.parse(payload) as unknown;
      return this.coerceRecord(parsed);
    }

    if (payload && typeof payload === "object" && !Array.isArray(payload)) {
      const record = payload as Record<string, unknown>;
      if ("result" in record) {
        return this.coerceRecord(record.result);
      }

      return record;
    }

    return { value: payload };
  }

  private getServerEnvironment(): Record<string, string> {
    return Object.fromEntries(
      Object.entries({
        ...process.env,
        LOG_LEVEL: this.options.logLevel ?? "info"
      }).filter((entry): entry is [string, string] => typeof entry[1] === "string")
    );
  }

  private formatError(prefix: string, error: unknown): string {
    const message = error instanceof Error ? error.message : String(error);
    return `${prefix}: ${message}`;
  }

  private resolveServerRoot(): string {
    if (this.options.extensionPath) {
      return path.resolve(this.options.extensionPath, "../../waveform_mcp");
    }

    const workspaceRoot = this.options.cwd ?? process.cwd();
    return path.resolve(workspaceRoot, "waveform_mcp");
  }
}

