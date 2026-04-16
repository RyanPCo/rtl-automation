import type { ServerLaunchOptions, ServerStatus } from "@rtl-automation/shared";
import { createLogger, type Logger } from "./logger.js";

export interface ServerApp {
  getStatus(): ServerStatus;
  start(): Promise<void>;
  close(): Promise<void>;
}

class StubServerApp implements ServerApp {
  private status: ServerStatus = "stopped";

  constructor(
    private readonly options: ServerLaunchOptions,
    private readonly logger: Logger
  ) {}

  getStatus(): ServerStatus {
    return this.status;
  }

  async start(): Promise<void> {
    this.status = "starting";
    this.logger.info(
      `bootstrapping stdio server shell (cwd=${this.options.cwd ?? process.cwd()})`
    );
    this.status = "running";
  }

  async close(): Promise<void> {
    this.logger.info("shutting down stdio server shell");
    this.status = "stopped";
  }
}

export const createServerApp = (
  options: ServerLaunchOptions = {},
  logger: Logger = createLogger()
): ServerApp => new StubServerApp(options, logger);

