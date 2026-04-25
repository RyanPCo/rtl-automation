import { useEffect, useMemo, useState } from "react";
import {
  Background,
  Controls,
  ReactFlow,
  type Node
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import type { ParseVerilogResult, VerilogPort } from "@rtl-automation/shared";
import { ModuleNode } from "./InstanceNode.js";
import {
  buildGraph,
  defaultSelectedNodeId,
  type DiagramNodeData
} from "./blockDiagramGraph.js";

interface VsCodeApi {
  postMessage(message: unknown): void;
}

declare global {
  interface Window {
    acquireVsCodeApi: () => VsCodeApi;
  }
}

const vscode: VsCodeApi = window.acquireVsCodeApi();

const nodeTypes = { module: ModuleNode };

function navigateTo(file: string, line: number): void {
  vscode.postMessage({ type: "navigate-to-line", payload: { file, line } });
}

function ErrorView({ message }: { message: string }) {
  return (
    <div
      style={{
        padding: 24,
        color: "var(--vscode-errorForeground, #f48771)",
        fontFamily: "var(--vscode-font-family, sans-serif)"
      }}
    >
      <h3 style={{ marginTop: 0 }}>Could not render block diagram</h3>
      <pre style={{ whiteSpace: "pre-wrap" }}>{message}</pre>
    </div>
  );
}

function LoadingView() {
  return (
    <div
      style={{
        padding: 24,
        color: "var(--vscode-foreground, #ddd)",
        fontFamily: "var(--vscode-font-family, sans-serif)"
      }}
    >
      Parsing Verilog…
    </div>
  );
}

function widthLabel(width: string): string {
  return width && width !== "1" ? width : "1";
}

function PortList({ title, ports }: { title: string; ports: VerilogPort[] }) {
  return (
    <section style={{ minWidth: 220, flex: "1 1 260px" }}>
      <div style={{ fontSize: 11, fontWeight: 700, opacity: 0.72, textTransform: "uppercase" }}>
        {title} ({ports.length})
      </div>
      {ports.length ? (
        <div style={{ marginTop: 8, display: "flex", gap: 8, flexWrap: "wrap" }}>
          {ports.map((port) => (
            <div
              key={`${port.direction}-${port.name}`}
              style={{
                display: "flex",
                gap: 6,
                alignItems: "baseline",
                padding: "5px 8px",
                border: "1px solid var(--vscode-panel-border, #3c3c3c)",
                borderRadius: 4,
                background: "var(--vscode-editor-background, #1e1e1e)"
              }}
            >
              <span style={{ fontWeight: 600 }}>{port.name}</span>
              <span style={{ opacity: 0.64 }}>{widthLabel(port.width)}</span>
            </div>
          ))}
        </div>
      ) : (
        <div style={{ marginTop: 8, opacity: 0.58 }}>None</div>
      )}
    </section>
  );
}

function Inspector({ selected }: { selected: DiagramNodeData | null }) {
  if (!selected) {
    return (
      <footer style={inspectorStyle}>
        <div style={{ opacity: 0.65 }}>Select a module to inspect its ports.</div>
      </footer>
    );
  }

  return (
    <footer style={inspectorStyle}>
      <div style={{ flex: "0 0 190px" }}>
        <div style={{ fontSize: 15, fontWeight: 750 }}>
          {selected.instanceName ?? selected.moduleName}
        </div>
        <div style={{ marginTop: 4, opacity: 0.68 }}>
          {selected.isTop ? "top module" : selected.moduleName}
        </div>
        {selected.unresolved ? (
          <div
            style={{
              marginTop: 8,
              color: "var(--vscode-descriptionForeground, #9d9d9d)"
            }}
          >
            Definition not found.
          </div>
        ) : null}
      </div>
      <PortList title="Inputs" ports={selected.inputPorts} />
      <PortList title="Outputs" ports={selected.outputPorts} />
      {selected.inoutPorts.length ? <PortList title="Inout" ports={selected.inoutPorts} /> : null}
    </footer>
  );
}

const inspectorStyle = {
  minHeight: 150,
  flex: "0 0 150px",
  padding: "14px 18px",
  borderTop: "1px solid var(--vscode-panel-border, #3c3c3c)",
  background: "var(--vscode-sideBar-background, #252526)",
  color: "var(--vscode-foreground, #ddd)",
  fontFamily: "var(--vscode-font-family, sans-serif)",
  fontSize: 12,
  display: "flex",
  gap: 24,
  alignItems: "flex-start",
  overflow: "auto"
} as const;

export function BlockDiagramApp() {
  const [data, setData] = useState<ParseVerilogResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);

  useEffect(() => {
    const handler = (event: MessageEvent): void => {
      const msg = event.data;
      if (!msg || typeof msg !== "object") return;
      if (msg.type === "diagram-data") {
        const payload = msg.payload as ParseVerilogResult;
        setData(payload);
        setSelectedNodeId(defaultSelectedNodeId(payload));
        setError(null);
      } else if (msg.type === "diagram-error") {
        setError(msg.payload?.message ?? "Unknown error");
        setData(null);
        setSelectedNodeId(null);
      }
    };
    window.addEventListener("message", handler);
    vscode.postMessage({ type: "ready" });
    return () => window.removeEventListener("message", handler);
  }, []);

  const graph = useMemo(
    () => (data ? buildGraph(data, selectedNodeId ?? undefined) : null),
    [data, selectedNodeId]
  );
  const selectedNode = useMemo(() => {
    if (!graph || !selectedNodeId) return null;
    return (graph.nodes.find((node) => node.id === selectedNodeId)?.data ?? null) as
      | DiagramNodeData
      | null;
  }, [graph, selectedNodeId]);

  if (error) return <ErrorView message={error} />;
  if (!data || !graph) return <LoadingView />;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", minHeight: 0 }}>
      <div style={{ flex: "1 1 auto", minHeight: 0 }}>
        <ReactFlow
          nodes={graph.nodes}
          edges={graph.edges}
          nodeTypes={nodeTypes}
          onNodeClick={(event: React.MouseEvent, node: Node) => {
            const nd = node.data as DiagramNodeData;
            setSelectedNodeId(node.id);
            if (
              (event.ctrlKey || event.metaKey) &&
              !nd.unresolved &&
              nd.definitionFile &&
              nd.definitionLine
            ) {
              navigateTo(nd.definitionFile, nd.definitionLine);
              return;
            }
          }}
          fitView
          proOptions={{ hideAttribution: true }}
        >
          <Background />
          <Controls />
        </ReactFlow>
      </div>
      <Inspector selected={selectedNode} />
    </div>
  );
}
