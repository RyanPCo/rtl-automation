export interface Logger {
  info(message: string): void;
  error(message: string): void;
}

export const createLogger = (): Logger => ({
  info(message: string) {
    console.error(`[mcp-server] ${message}`);
  },
  error(message: string) {
    console.error(`[mcp-server:error] ${message}`);
  }
});

