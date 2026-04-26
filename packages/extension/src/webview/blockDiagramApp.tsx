import { useEffect, useMemo, useState } from "react";
import {
  Background,
  Controls,
  ReactFlow,
  type Node
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";

import type { ParseVerilogResult, VerilogNet, VerilogPort } from "@rtl-automation/shared";
import { ModuleNode } from "./InstanceNode.js";
import {
  buildGraph,
  defaultSelectedNodeId,
  type DiagramNodeData
} from "./blockDiagramGraph.js";
import {
  tracePortFlow,
  type SelectedPortFlow
} from "./signalFlow.js";

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

function PortList({
  title,
  ports,
  selectedNodeId,
  activeFlow,
  onPortClick,
  listMaxHeight
}: {
  title: string;
  ports: VerilogPort[];
  selectedNodeId: string | null;
  activeFlow: SelectedPortFlow | null;
  onPortClick(port: VerilogPort): void;
  listMaxHeight: number;
}) {
  const [query, setQuery] = useState("");
  const normalizedQuery = query.trim().toLowerCase();
  const filteredPorts = normalizedQuery
    ? ports.filter((port) => port.name.toLowerCase().includes(normalizedQuery))
    : ports;

  return (
    <section style={{ minWidth: 180, flex: "1 1 210px" }}>
      <div style={{ fontSize: 11, fontWeight: 700, opacity: 0.72, textTransform: "uppercase" }}>
        {title} ({ports.length})
      </div>
      <input
        type="text"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={`Search ${title.toLowerCase()}`}
        style={{
          width: "100%",
          boxSizing: "border-box",
          marginTop: 8,
          padding: "5px 7px",
          border: "1px solid var(--vscode-input-border, #3c3c3c)",
          borderRadius: 3,
          background: "var(--vscode-input-background, #1e1e1e)",
          color: "var(--vscode-input-foreground, #ddd)",
          font: "inherit"
        }}
      />
      {ports.length ? (
        <div style={{ marginTop: 8, display: "grid", gap: 4, overflowY: "auto", overflowX: "hidden", maxHeight: listMaxHeight }}>
          {filteredPorts.map((port) => (
            <button
              key={`${port.direction}-${port.name}`}
              type="button"
              onClick={() => onPortClick(port)}
              style={{
                display: "flex",
                justifyContent: "space-between",
                gap: 12,
                alignItems: "baseline",
                width: "100%",
                padding: "5px 7px",
                border: activeFlow?.nodeId === selectedNodeId && activeFlow.portName === port.name
                  ? "1px solid var(--vscode-charts-yellow, #cca700)"
                  : "1px solid transparent",
                borderRadius: 3,
                background: "var(--vscode-editor-background, #1e1e1e)",
                color: "var(--vscode-foreground, #ddd)",
                font: "inherit",
                cursor: "pointer",
                textAlign: "left"
              }}
            >
              <span style={{ fontWeight: 600 }}>{port.name}</span>
              <span style={{ opacity: 0.64 }}>{widthLabel(port.width)}</span>
            </button>
          ))}
          {!filteredPorts.length ? (
            <div style={{ opacity: 0.58, padding: "5px 0" }}>No matches</div>
          ) : null}
        </div>
      ) : (
        <div style={{ marginTop: 8, opacity: 0.58 }}>None</div>
      )}
    </section>
  );
}

function SignalList({ signals, listMaxHeight }: { signals: VerilogNet[]; listMaxHeight: number }) {
  const [query, setQuery] = useState("");
  const normalizedQuery = query.trim().toLowerCase();
  const filteredSignals = normalizedQuery
    ? signals.filter((signal) => signal.name.toLowerCase().includes(normalizedQuery))
    : signals;

  return (
    <section style={{ minWidth: 190, flex: "1 1 220px" }}>
      <div style={{ fontSize: 11, fontWeight: 700, opacity: 0.72, textTransform: "uppercase" }}>
        Signals ({signals.length})
      </div>
      <input
        type="text"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder="Search signals"
        style={{
          width: "100%",
          boxSizing: "border-box",
          marginTop: 8,
          padding: "5px 7px",
          border: "1px solid var(--vscode-input-border, #3c3c3c)",
          borderRadius: 3,
          background: "var(--vscode-input-background, #1e1e1e)",
          color: "var(--vscode-input-foreground, #ddd)",
          font: "inherit"
        }}
      />
      {signals.length ? (
        <div style={{ marginTop: 8, display: "grid", gap: 4, overflowY: "auto", overflowX: "hidden", maxHeight: listMaxHeight }}>
          {filteredSignals.map((signal) => (
            <div
              key={`${signal.kind}-${signal.name}`}
              style={{
                display: "flex",
                justifyContent: "space-between",
                gap: 12,
                alignItems: "baseline",
                padding: "5px 7px",
                borderRadius: 3,
                background: "var(--vscode-editor-background, #1e1e1e)"
              }}
            >
              <span style={{ fontWeight: 600 }}>{signal.name}</span>
              <span style={{ opacity: 0.64 }}>{signal.kind} {widthLabel(signal.width)}</span>
            </div>
          ))}
          {!filteredSignals.length ? (
            <div style={{ opacity: 0.58, padding: "5px 0" }}>No matches</div>
          ) : null}
        </div>
      ) : (
        <div style={{ marginTop: 8, opacity: 0.58 }}>None</div>
      )}
    </section>
  );
}

function Inspector({
  selected,
  selectedNodeId,
  activeFlow,
  onPortClick,
  height
}: {
  selected: DiagramNodeData | null;
  selectedNodeId: string | null;
  activeFlow: SelectedPortFlow | null;
  onPortClick(port: VerilogPort): void;
  height: number;
}) {
  const style = {
    ...inspectorStyle,
    minHeight: height,
    flex: `0 0 ${height}px`
  };
  const listMaxHeight = Math.max(48, height - 22);

  if (!selected) {
    return (
      <footer style={style}>
        <div style={{ opacity: 0.65 }}>Select a module to inspect its ports.</div>
      </footer>
    );
  }

  return (
    <footer style={style}>
      <PortList
        title="Inputs"
        ports={selected.inputPorts}
        selectedNodeId={selectedNodeId}
        activeFlow={activeFlow}
        onPortClick={onPortClick}
        listMaxHeight={listMaxHeight}
      />
      <PortList
        title="Outputs"
        ports={selected.outputPorts}
        selectedNodeId={selectedNodeId}
        activeFlow={activeFlow}
        onPortClick={onPortClick}
        listMaxHeight={listMaxHeight}
      />
      {selected.inoutPorts.length ? (
        <PortList
          title="Inout"
          ports={selected.inoutPorts}
          selectedNodeId={selectedNodeId}
          activeFlow={activeFlow}
          onPortClick={onPortClick}
          listMaxHeight={listMaxHeight}
        />
      ) : null}
      <SignalList signals={selected.internalSignals} listMaxHeight={listMaxHeight} />
    </footer>
  );
}

const inspectorStyle = {
  padding: "14px 18px",
  borderTop: "1px solid var(--vscode-panel-border, #3c3c3c)",
  background: "var(--vscode-sideBar-background, #252526)",
  color: "var(--vscode-foreground, #ddd)",
  fontFamily: "var(--vscode-font-family, sans-serif)",
  fontSize: 12,
  display: "flex",
  gap: 24,
  alignItems: "flex-start",
  overflowX: "auto",
  overflowY: "hidden",
  minHeight: 0
} as const;

const MIN_PANEL_HEIGHT = 96;
const DEFAULT_PANEL_HEIGHT = 220;
const MAX_PANEL_HEIGHT = 420;

export function BlockDiagramApp() {
  const [data, setData] = useState<ParseVerilogResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [activeFlow, setActiveFlow] = useState<SelectedPortFlow | null>(null);
  const [panelHeight, setPanelHeight] = useState(DEFAULT_PANEL_HEIGHT);

  useEffect(() => {
    const handler = (event: MessageEvent): void => {
      const msg = event.data;
      if (!msg || typeof msg !== "object") return;
      if (msg.type === "diagram-data") {
        const payload = msg.payload as ParseVerilogResult;
        setData(payload);
        setSelectedNodeId(defaultSelectedNodeId(payload));
        setActiveFlow(null);
        setError(null);
      } else if (msg.type === "diagram-error") {
        setError(msg.payload?.message ?? "Unknown error");
        setData(null);
        setSelectedNodeId(null);
        setActiveFlow(null);
      }
    };
    window.addEventListener("message", handler);
    vscode.postMessage({ type: "ready" });
    return () => window.removeEventListener("message", handler);
  }, []);

  const flowTrace = useMemo(
    () => tracePortFlow(data?.hierarchy, activeFlow),
    [data, activeFlow]
  );
  const graph = useMemo(
    () => (data ? buildGraph(data, selectedNodeId ?? undefined, flowTrace) : null),
    [data, selectedNodeId, flowTrace]
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
            setActiveFlow(null);
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
      <div
        onPointerDown={(event) => {
          event.preventDefault();
          const startY = event.clientY;
          const startHeight = panelHeight;
          const onMove = (moveEvent: PointerEvent) => {
            const nextHeight = startHeight - (moveEvent.clientY - startY);
            setPanelHeight(Math.max(MIN_PANEL_HEIGHT, Math.min(MAX_PANEL_HEIGHT, nextHeight)));
          };
          const onUp = () => {
            window.removeEventListener("pointermove", onMove);
            window.removeEventListener("pointerup", onUp);
          };
          window.addEventListener("pointermove", onMove);
          window.addEventListener("pointerup", onUp);
        }}
        style={{
          flex: "0 0 6px",
          cursor: "ns-resize",
          borderTop: "1px solid var(--vscode-panel-border, #3c3c3c)",
          background: "var(--vscode-sideBar-background, #252526)"
        }}
      />
      <Inspector
        selected={selectedNode}
        selectedNodeId={selectedNodeId}
        activeFlow={activeFlow}
        height={panelHeight}
        onPortClick={(port) => {
          if (!selectedNodeId) return;
          setActiveFlow((current) =>
            current?.nodeId === selectedNodeId && current.portName === port.name
              ? null
              : {
                  nodeId: selectedNodeId,
                  portName: port.name,
                  direction: port.direction
                }
          );
        }}
      />
    </div>
  );
}
