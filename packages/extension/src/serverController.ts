import { ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import path from "node:path";
import type { ServerLaunchOptions, ServerStatus } from "@rtl-automation/shared";
import type { Logger } from "./logging.js";

export class ServerController {
  private child?: ChildProcessWithoutNullStreams;
  private status: ServerStatus = "stopped";

  constructor(
    private readonly logger: Logger,
    private readonly options: ServerLaunchOptions = {}
  ) {}

  getStatus(): ServerStatus {
    return this.status;
  }

  async start(): Promise<ServerStatus> {
    if (this.child) {
      return this.status;
    }

    this.status = "starting";
    const serverEntrypoint = path.resolve(
      __dirname,
      "../../mcp-server/dist/cli.js"
    );

    this.child = spawn(process.execPath, [serverEntrypoint], {
      cwd: this.options.cwd ?? process.cwd(),
      env: {
        ...process.env,
        LOG_LEVEL: this.options.logLevel ?? "info"
      },
      stdio: "pipe"
    });

    this.child.stderr.on("data", (chunk) => {
      this.logger.info(String(chunk).trim());
    });

    this.child.on("exit", (code) => {
      this.logger.info(`MCP server exited with code ${code ?? 0}`);
      this.child = undefined;
      this.status = "stopped";
    });

    this.status = "running";
    return this.status;
  }

  async stop(): Promise<void> {
    if (!this.child) {
      this.status = "stopped";
      return;
    }

    this.child.kill();
    this.child = undefined;
    this.status = "stopped";
  }
}

