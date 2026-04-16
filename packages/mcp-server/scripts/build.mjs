import { build, context } from "esbuild";

const watch = process.argv.includes("--watch");

const common = {
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  sourcemap: true,
  outdir: "dist",
  entryNames: "[name]"
};

if (watch) {
  const ctx = await context({
    ...common,
    entryPoints: ["src/index.ts", "src/cli.ts"]
  });
  await ctx.watch();
  console.log("watching mcp-server");
} else {
  await build({
    ...common,
    entryPoints: ["src/index.ts", "src/cli.ts"]
  });
}
