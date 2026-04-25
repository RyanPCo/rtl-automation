import { describe, expect, it } from "vitest";
import type { ParseVerilogResult } from "@rtl-automation/shared";
import { buildGraph } from "../src/webview/blockDiagramGraph.js";

const treeData: ParseVerilogResult = {
  file: "/repo/src/top.v",
  module: {
    name: "top",
    line: 1,
    ports: [
      { name: "clk", direction: "input", width: "1", line: 2 },
      { name: "result", direction: "output", width: "[7:0]", line: 3 }
    ]
  },
  nets: [],
  instances: [],
  assigns: [],
  procedurals: [],
  hierarchy: {
    id: "top",
    moduleName: "top",
    definitionFile: "/repo/src/top.v",
    definitionLine: 1,
    instanceFile: "/repo/src/top.v",
    instanceLine: 1,
    ports: [
      { name: "clk", direction: "input", width: "1", line: 2 },
      { name: "result", direction: "output", width: "[7:0]", line: 3 }
    ],
    children: [
      {
        id: "top/u_mid",
        moduleName: "mid",
        instanceName: "u_mid",
        definitionFile: "/repo/src/mid.v",
        definitionLine: 1,
        instanceFile: "/repo/src/top.v",
        instanceLine: 7,
        ports: [
          { name: "clk", direction: "input", width: "1", line: 2 },
          { name: "done", direction: "output", width: "1", line: 3 }
        ],
        children: [
          {
            id: "top/u_mid/u_leaf",
            moduleName: "leaf",
            instanceName: "u_leaf",
            definitionFile: "/repo/src/leaf.v",
            definitionLine: 1,
            instanceFile: "/repo/src/mid.v",
            instanceLine: 9,
            ports: [{ name: "din", direction: "input", width: "[7:0]", line: 2 }],
            children: []
          }
        ]
      },
      {
        id: "top/u_missing",
        moduleName: "missing",
        instanceName: "u_missing",
        instanceFile: "/repo/src/top.v",
        instanceLine: 11,
        ports: [],
        children: [],
        unresolved: true
      }
    ]
  }
};

describe("buildGraph", () => {
  it("builds module hierarchy nodes without port block nodes", () => {
    const graph = buildGraph(treeData);

    expect(graph.nodes.map((node) => node.id)).toEqual(
      expect.arrayContaining([
        "top",
        "top/u_mid",
        "top/u_mid/u_leaf"
      ])
    );
    expect(graph.nodes.map((node) => node.id)).not.toContain("top/u_missing");
    expect(graph.nodes).toHaveLength(3);
    expect(graph.nodes.every((node) => node.type === "module")).toBe(true);
  });

  it("adds parent-to-child arrows recursively", () => {
    const graph = buildGraph(treeData);

    expect(graph.edges.map((edge) => `${edge.source}->${edge.target}`)).toEqual(
      expect.arrayContaining([
        "top->top/u_mid",
        "top/u_mid->top/u_mid/u_leaf"
      ])
    );
    expect(graph.edges.map((edge) => `${edge.source}->${edge.target}`)).not.toContain(
      "top->top/u_missing"
    );
  });

  it("places grandchildren deeper than children", () => {
    const graph = buildGraph(treeData);
    const top = graph.nodes.find((node) => node.id === "top");
    const child = graph.nodes.find((node) => node.id === "top/u_mid");
    const grandchild = graph.nodes.find((node) => node.id === "top/u_mid/u_leaf");

    expect(child?.position.x).toBeGreaterThan(top?.position.x ?? 0);
    expect(grandchild?.position.x).toBeGreaterThan(child?.position.x ?? 0);
  });

  it("lays siblings out vertically", () => {
    const graphWithMoreSiblings = buildGraph({
      ...treeData,
      hierarchy: {
        ...treeData.hierarchy!,
        children: [
          ...treeData.hierarchy!.children,
          {
            id: "top/u_other",
            moduleName: "other",
            instanceName: "u_other",
            definitionFile: "/repo/src/other.v",
            definitionLine: 1,
            instanceFile: "/repo/src/top.v",
            instanceLine: 13,
            ports: [],
            children: []
          }
        ]
      }
    });
    const firstChild = graphWithMoreSiblings.nodes.find((node) => node.id === "top/u_mid");
    const secondChild = graphWithMoreSiblings.nodes.find((node) => node.id === "top/u_other");

    expect(secondChild?.position.x).toBe(firstChild?.position.x);
    expect(Math.abs((secondChild?.position.y ?? 0) - (firstChild?.position.y ?? 0))).toBeGreaterThan(80);
  });

  it("filters unresolved children without definition links", () => {
    const graph = buildGraph(treeData);

    expect(graph.nodes.find((node) => node.id === "top/u_missing")).toBeUndefined();
    expect(graph.edges.find((edge) => edge.target === "top/u_missing")).toBeUndefined();
  });

  it("carries port data for the selected inspector", () => {
    const graph = buildGraph(treeData, "top/u_mid");
    const node = graph.nodes.find((item) => item.id === "top/u_mid");

    expect(node?.data.selected).toBe(true);
    expect(node?.data.inputPorts.map((port) => port.name)).toEqual(["clk"]);
    expect(node?.data.outputPorts.map((port) => port.name)).toEqual(["done"]);
  });
});
