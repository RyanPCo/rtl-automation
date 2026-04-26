import { Position, type Edge, type Node } from "@xyflow/react";

import type {
  ParseVerilogResult,
  VerilogHierarchyNode,
  VerilogNet,
  VerilogPort
} from "@rtl-automation/shared";
import type { FlowTraceResult } from "./signalFlow.js";

export interface DiagramNodeData {
  moduleName: string;
  instanceName?: string;
  definitionFile?: string;
  definitionLine?: number;
  instanceFile: string;
  instanceLine: number;
  inputPorts: VerilogPort[];
  outputPorts: VerilogPort[];
  inoutPorts: VerilogPort[];
  internalSignals: VerilogNet[];
  unresolved?: boolean;
  selected?: boolean;
  flowActive?: boolean;
  flowSource?: boolean;
  isTop?: boolean;
  [key: string]: unknown;
}

export interface DiagramEdgeData {
  flowActive?: boolean;
  [key: string]: unknown;
}

const DEPTH_X = 260;
const ROW_Y = 110;
const NODE_W = 170;

function fallbackHierarchy(data: ParseVerilogResult): VerilogHierarchyNode {
  return {
    id: "top",
    moduleName: data.module.name,
    definitionFile: data.file,
    definitionLine: data.module.line,
    instanceFile: data.file,
    instanceLine: data.module.line,
    ports: data.module.ports,
    nets: data.nets,
    children: data.instances.map((inst) => ({
      id: `top/${inst.instance_name}`,
      moduleName: inst.module_type,
      instanceName: inst.instance_name,
      instanceFile: data.file,
      instanceLine: inst.line,
      ports: [],
      nets: [],
      children: [],
      unresolved: true
    }))
  };
}

function splitPorts(ports: VerilogPort[]): Pick<
  DiagramNodeData,
  "inputPorts" | "outputPorts" | "inoutPorts"
> {
  return {
    inputPorts: ports.filter((port) => port.direction === "input"),
    outputPorts: ports.filter((port) => port.direction === "output"),
    inoutPorts: ports.filter((port) => port.direction === "inout")
  };
}

function visibleChildren(node: VerilogHierarchyNode): VerilogHierarchyNode[] {
  return node.children.filter((child) => Boolean(child.definitionFile) && !child.unresolved);
}

function visibleLeafCount(node: VerilogHierarchyNode): number {
  const children = visibleChildren(node);
  if (!children.length) return 1;
  return children.reduce((sum, child) => sum + visibleLeafCount(child), 0);
}

function addTreeNodes(
  node: VerilogHierarchyNode,
  depth: number,
  nextLeaf: { value: number },
  nodes: Node<DiagramNodeData>[],
  edges: Edge<DiagramEdgeData>[],
  selectedNodeId?: string,
  flowTrace?: FlowTraceResult | null
): number {
  const children = visibleChildren(node);
  let y: number;
  if (!children.length) {
    y = nextLeaf.value * ROW_Y;
    nextLeaf.value += 1;
  } else {
    const childYs = children.map((child) =>
      addTreeNodes(child, depth + 1, nextLeaf, nodes, edges, selectedNodeId, flowTrace)
    );
    y = (childYs[0] + childYs[childYs.length - 1]) / 2;
  }

  nodes.push({
    id: node.id,
    type: "module",
    data: {
      moduleName: node.moduleName,
      instanceName: node.instanceName,
      definitionFile: node.definitionFile,
      definitionLine: node.definitionLine,
      instanceFile: node.instanceFile,
      instanceLine: node.instanceLine,
      unresolved: node.unresolved,
      selected: node.id === selectedNodeId,
      flowActive: flowTrace?.nodeIds.has(node.id) ?? false,
      flowSource: flowTrace?.selected.nodeId === node.id,
      isTop: depth === 0,
      internalSignals: node.nets ?? [],
      ...splitPorts(node.ports)
    },
    position: { x: depth * DEPTH_X, y },
    sourcePosition: Position.Right,
    targetPosition: Position.Left
  });

  children.forEach((child) => {
    edges.push({
      id: `e-${node.id}->${child.id}`,
      source: node.id,
      target: child.id,
      data: {
        flowActive: flowTrace?.edgeIds.has(`e-${node.id}->${child.id}`) ?? false
      },
      style: {
        stroke: flowTrace?.edgeIds.has(`e-${node.id}->${child.id}`)
          ? "var(--vscode-charts-yellow, #cca700)"
          : "var(--vscode-charts-blue, #4ea1ff)",
        strokeWidth: flowTrace?.edgeIds.has(`e-${node.id}->${child.id}`) ? 3 : 1.8
      }
    });
  });

  return y;
}

export function defaultSelectedNodeId(data: ParseVerilogResult): string {
  return (data.hierarchy ?? fallbackHierarchy(data)).id;
}

export function findHierarchyNode(
  node: VerilogHierarchyNode,
  nodeId: string
): VerilogHierarchyNode | undefined {
  if (node.id === nodeId) return node;
  for (const child of node.children) {
    const found = findHierarchyNode(child, nodeId);
    if (found) return found;
  }
  return undefined;
}

export function buildGraph(
  data: ParseVerilogResult,
  selectedNodeId?: string,
  flowTrace?: FlowTraceResult | null
): {
  nodes: Node<DiagramNodeData>[];
  edges: Edge<DiagramEdgeData>[];
} {
  const hierarchy = data.hierarchy ?? fallbackHierarchy(data);
  const nodes: Node<DiagramNodeData>[] = [];
  const edges: Edge<DiagramEdgeData>[] = [];
  const nextLeaf = { value: 0 };
  const leaves = visibleLeafCount(hierarchy);

  addTreeNodes(
    hierarchy,
    0,
    nextLeaf,
    nodes,
    edges,
    selectedNodeId ?? hierarchy.id,
    flowTrace
  );

  const minY = ((leaves - 1) * ROW_Y) / -2;
  return {
    nodes: nodes.map((node) => ({
      ...node,
      position: {
        x: node.position.x + NODE_W,
        y: node.position.y + minY
      }
    })),
    edges
  };
}
