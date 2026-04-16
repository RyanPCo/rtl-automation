import { describe, expect, it } from "vitest";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

describe("cli", () => {
  it("starts and exits in smoke test mode", async () => {
    const cliPath = path.resolve(
      path.dirname(fileURLToPath(import.meta.url)),
      "../dist/cli.js"
    );

    const exitCode = await new Promise<number>((resolve, reject) => {
      const child = spawn(process.execPath, [cliPath, "--smoke-test"], {
        stdio: "ignore"
      });

      child.on("error", reject);
      child.on("exit", (code) => resolve(code ?? 1));
    });

    expect(exitCode).toBe(0);
  });
});

