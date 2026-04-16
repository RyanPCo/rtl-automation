import { describe, expect, it } from "vitest";
import { createServerApp } from "../src/app.js";

describe("createServerApp", () => {
  it("constructs and starts cleanly", async () => {
    const app = createServerApp({ cwd: "/tmp" }, { info() {}, error() {} });

    expect(app.getStatus()).toBe("stopped");
    await app.start();
    expect(app.getStatus()).toBe("running");
    await app.close();
    expect(app.getStatus()).toBe("stopped");
  });
});

