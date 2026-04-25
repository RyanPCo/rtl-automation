import { Handle, Position } from "@xyflow/react";
import type { DiagramNodeData } from "./blockDiagramGraph.js";

const baseNodeStyle = {
  border: "1px solid var(--vscode-panel-border, #565656)",
  borderRadius: 6,
  background: "var(--vscode-editor-background, #1e1e1e)",
  color: "var(--vscode-foreground, #ddd)",
  fontFamily: "var(--vscode-font-family, sans-serif)",
  fontSize: 12,
  boxShadow: "0 1px 10px rgba(0, 0, 0, 0.18)"
} as const;

export function ModuleNode({ data }: { data: DiagramNodeData }) {
  const portCount = data.inputPorts.length + data.outputPorts.length + data.inoutPorts.length;
  const subtitle = data.isTop
    ? "top module"
    : data.unresolved
      ? "unresolved"
      : data.moduleName;

  return (
    <div
      style={{
        ...baseNodeStyle,
        padding: "12px 14px",
        minWidth: 160,
        textAlign: "center",
        opacity: data.unresolved ? 0.62 : 1,
        borderColor: data.selected
          ? "var(--vscode-focusBorder, #007fd4)"
          : "var(--vscode-panel-border, #565656)",
        outline: data.selected ? "1px solid var(--vscode-focusBorder, #007fd4)" : "none"
      }}
    >
      <Handle type="target" position={Position.Left} />
      <div style={{ fontWeight: 700 }}>{data.instanceName ?? data.moduleName}</div>
      <div style={{ opacity: 0.72, marginTop: 3 }}>{subtitle}</div>
      <div style={{ opacity: 0.58, marginTop: 7, fontSize: 11 }}>
        {portCount} ports
      </div>
      <Handle type="source" position={Position.Right} />
    </div>
  );
}
