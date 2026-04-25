import { context } from "esbuild";

const watch = process.argv.includes("--watch");

const extensionCtx = await context({
  entryPoints: ["src/extension.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  sourcemap: true,
  outfile: "dist/extension.js",
  external: ["vscode"]
});

const webviewCtx = await context({
  entryPoints: ["src/webview/blockDiagramEntry.tsx"],
  bundle: true,
  platform: "browser",
  target: "es2020",
  format: "iife",
  sourcemap: true,
  outfile: "dist/blockDiagramWebview.js",
  jsx: "automatic",
  loader: { ".css": "css" },
  define: { "process.env.NODE_ENV": '"production"' }
});

if (watch) {
  await Promise.all([extensionCtx.watch(), webviewCtx.watch()]);
  console.log("watching extension + webview");
} else {
  await Promise.all([extensionCtx.rebuild(), webviewCtx.rebuild()]);
  await Promise.all([extensionCtx.dispose(), webviewCtx.dispose()]);
}
