import type {
  VerilogConnection,
  VerilogHierarchyNode,
  VerilogInstance,
  VerilogPort
} from "@rtl-automation/shared";

export interface SelectedPortFlow {
  nodeId: string;
  portName: string;
  direction: VerilogPort["direction"];
}

export interface FlowTraceStep {
  nodeId: string;
  moduleLabel: string;
  portName: string;
  direction: VerilogConnection["direction"] | VerilogPort["direction"] | "net";
  via: string;
}

export interface FlowTraceResult {
  selected: SelectedPortFlow;
  nodeIds: Set<string>;
  edgeIds: Set<string>;
  steps: FlowTraceStep[];
}

function visibleChildren(node: VerilogHierarchyNode): VerilogHierarchyNode[] {
  return node.children.filter((child) => Boolean(child.definitionFile) && !child.unresolved);
}

function findNode(node: VerilogHierarchyNode, nodeId: string): VerilogHierarchyNode | undefined {
  if (node.id === nodeId) return node;
  for (const child of node.children) {
    const found = findNode(child, nodeId);
    if (found) return found;
  }
  return undefined;
}

function moduleLabel(node: VerilogHierarchyNode): string {
  return node.instanceName ? `${node.instanceName} (${node.moduleName})` : node.moduleName;
}

function addNetEdge(graph: Map<string, Set<string>>, a: string, b: string): void {
  if (!a || !b || a === b) return;
  const aSet = graph.get(a) ?? new Set<string>();
  aSet.add(b);
  graph.set(a, aSet);
  const bSet = graph.get(b) ?? new Set<string>();
  bSet.add(a);
  graph.set(b, bSet);
}

function reachableNets(node: VerilogHierarchyNode, startNet: string): Set<string> {
  const graph = new Map<string, Set<string>>();
  (node.assigns ?? []).forEach((assign) => {
    assign.rhs_idents.forEach((rhs) => addNetEdge(graph, assign.lhs, rhs));
  });
  (node.procedurals ?? []).forEach((proc) => {
    proc.writes.forEach((write) => {
      proc.reads.forEach((read) => addNetEdge(graph, write, read));
    });
  });

  const seen = new Set<string>();
  const queue = [startNet];
  while (queue.length) {
    const net = queue.shift()!;
    if (seen.has(net)) continue;
    seen.add(net);
    (graph.get(net) ?? new Set<string>()).forEach((next) => {
      if (!seen.has(next)) queue.push(next);
    });
  }
  return seen;
}

function instanceForChild(parent: VerilogHierarchyNode, child: VerilogHierarchyNode): VerilogInstance | undefined {
  return (parent.instances ?? []).find((inst) => inst.instance_name === child.instanceName);
}

function traceNodePort(
  root: VerilogHierarchyNode,
  node: VerilogHierarchyNode,
  portName: string,
  result: FlowTraceResult,
  visited: Set<string>
): void {
  const visitKey = `${node.id}:${portName}`;
  if (visited.has(visitKey)) return;
  visited.add(visitKey);
  result.nodeIds.add(node.id);

  const nets = reachableNets(node, portName);
  visibleChildren(node).forEach((child) => {
    const inst = instanceForChild(node, child);
    const connections = inst?.connections ?? child.connections ?? [];
    const matched = connections.filter((conn) =>
      conn.net_idents.some((ident) => nets.has(ident))
    );
    if (!matched.length) return;

    result.nodeIds.add(child.id);
    result.edgeIds.add(`e-${node.id}->${child.id}`);
    matched.forEach((conn) => {
      result.steps.push({
        nodeId: child.id,
        moduleLabel: moduleLabel(child),
        portName: conn.port,
        direction: conn.direction,
        via: conn.net_idents.filter((ident) => nets.has(ident)).join(", ") || conn.net
      });
      traceNodePort(root, child, conn.port, result, visited);
    });
  });

  if (node.id !== root.id) {
    const parentId = node.id.split("/").slice(0, -1).join("/");
    const parent = parentId ? findNode(root, parentId) : undefined;
    if (parent) {
      const matchedParentPins = (node.connections ?? []).filter((conn) => conn.port === portName);
      matchedParentPins.forEach((conn) => {
        conn.net_idents.forEach((parentNet) => {
          result.nodeIds.add(parent.id);
          result.edgeIds.add(`e-${parent.id}->${node.id}`);
          result.steps.push({
            nodeId: parent.id,
            moduleLabel: moduleLabel(parent),
            portName: parentNet,
            direction: "net",
            via: `${node.instanceName ?? node.moduleName}.${conn.port}`
          });
        });
      });
    }
  }
}

export function tracePortFlow(
  root: VerilogHierarchyNode | undefined,
  selected: SelectedPortFlow | null
): FlowTraceResult | null {
  if (!root || !selected) return null;
  const node = findNode(root, selected.nodeId);
  if (!node) return null;

  const result: FlowTraceResult = {
    selected,
    nodeIds: new Set<string>([selected.nodeId]),
    edgeIds: new Set<string>(),
    steps: [
      {
        nodeId: selected.nodeId,
        moduleLabel: moduleLabel(node),
        portName: selected.portName,
        direction: selected.direction,
        via: "selected"
      }
    ]
  };
  traceNodePort(root, node, selected.portName, result, new Set<string>());
  return result;
}
