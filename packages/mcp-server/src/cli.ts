import { createServerApp } from "./app.js";

const run = async (): Promise<void> => {
  const app = createServerApp({
    cwd: process.cwd(),
    logLevel: process.env.LOG_LEVEL ?? "info"
  });

  await app.start();

  if (process.argv.includes("--smoke-test")) {
    await app.close();
    return;
  }

  const shutdown = async (): Promise<void> => {
    await app.close();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
};

void run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});

