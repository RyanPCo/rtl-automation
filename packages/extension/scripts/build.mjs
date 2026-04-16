import { context } from "esbuild";

const watch = process.argv.includes("--watch");

const ctx = await context({
  entryPoints: ["src/extension.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  sourcemap: true,
  outfile: "dist/extension.js",
  external: ["vscode"]
});

if (watch) {
  await ctx.watch();
  console.log("watching extension");
} else {
  await ctx.rebuild();
  await ctx.dispose();
}

