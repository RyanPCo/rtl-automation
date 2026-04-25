"""Tests for the structural Verilog parser."""

from __future__ import annotations

from pathlib import Path

import pytest

from waveform_mcp.verilog_parser import parse_verilog


def _write(tmp_path: Path, name: str, source: str) -> str:
    p = tmp_path / name
    p.write_text(source)
    return str(p)


def test_ansi_ports(tmp_path: Path) -> None:
    src = """\
module top (
    input clk,
    input [7:0] data,
    output reg done
);
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    assert result["module"]["name"] == "top"
    assert result["module"]["line"] == 1

    ports = {p["name"]: p for p in result["module"]["ports"]}
    assert set(ports.keys()) == {"clk", "data", "done"}
    assert ports["clk"]["direction"] == "input"
    assert ports["data"]["direction"] == "input"
    assert ports["data"]["width"] == "[7:0]"
    assert ports["done"]["direction"] == "output"
    assert ports["clk"]["line"] == 2
    assert ports["data"]["line"] == 3
    assert ports["done"]["line"] == 4


def test_old_style_ports(tmp_path: Path) -> None:
    src = """\
module top (clk, data, done);
    input clk;
    input [7:0] data;
    output done;
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    ports = {p["name"]: p for p in result["module"]["ports"]}
    assert ports["clk"]["direction"] == "input"
    assert ports["clk"]["line"] == 2
    assert ports["data"]["width"] == "[7:0]"
    assert ports["data"]["line"] == 3
    assert ports["done"]["direction"] == "output"
    assert ports["done"]["line"] == 4


def test_nets(tmp_path: Path) -> None:
    src = """\
module top (input a, output b);
    wire net1;
    wire [3:0] bus;
    reg state;
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    nets = {n["name"]: n for n in result["nets"]}
    assert set(nets.keys()) == {"net1", "bus", "state"}
    assert nets["net1"]["kind"] == "wire"
    assert nets["bus"]["width"] == "[3:0]"
    assert nets["state"]["kind"] == "reg"
    assert nets["net1"]["line"] == 2
    assert nets["bus"]["line"] == 3
    assert nets["state"]["line"] == 4


def test_simple_instantiation(tmp_path: Path) -> None:
    src = """\
module top (input clk, input rst, output [7:0] q);
    wire [7:0] mid;
    counter u_cnt (.clk(clk), .rst(rst), .q(mid));
    buffer  u_buf (.in(mid), .out(q));
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    insts = result["instances"]
    assert len(insts) == 2

    cnt = insts[0]
    assert cnt["module_type"] == "counter"
    assert cnt["instance_name"] == "u_cnt"
    assert cnt["line"] == 3
    conns = {c["port"]: c["net"] for c in cnt["connections"]}
    assert conns == {"clk": "clk", "rst": "rst", "q": "mid"}

    buf = insts[1]
    assert buf["module_type"] == "buffer"
    assert buf["instance_name"] == "u_buf"
    assert buf["line"] == 4
    conns = {c["port"]: c["net"] for c in buf["connections"]}
    assert conns == {"in": "mid", "out": "q"}


def test_multiline_instantiation(tmp_path: Path) -> None:
    src = """\
module top (
    input clk,
    output [3:0] q
);
    counter u_cnt (
        .clk(clk),
        .rst(1'b0),
        .q(q)
    );
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    inst = result["instances"][0]
    assert inst["module_type"] == "counter"
    assert inst["instance_name"] == "u_cnt"
    assert inst["line"] == 5
    conns = {c["port"]: c["net"] for c in inst["connections"]}
    assert conns["clk"] == "clk"
    assert conns["rst"] == "1'b0"
    assert conns["q"] == "q"


def test_parameter_override(tmp_path: Path) -> None:
    src = """\
module top (input clk, output [7:0] q);
    counter #(.WIDTH(8)) u_cnt (.clk(clk), .q(q));
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    inst = result["instances"][0]
    assert inst["module_type"] == "counter"
    assert inst["instance_name"] == "u_cnt"


def test_parameterized_module_header_ports(tmp_path: Path) -> None:
    src = """\
module top #(
    parameter WIDTH = 8,
    parameter DEPTH = 4
) (
    input clk,
    input [WIDTH-1:0] din,
    output [DEPTH-1:0] dout
);
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    ports = {p["name"]: p for p in result["module"]["ports"]}

    assert result["module"]["name"] == "top"
    assert set(ports.keys()) == {"clk", "din", "dout"}
    assert ports["clk"]["direction"] == "input"
    assert ports["din"]["width"] == "[WIDTH-1:0]"
    assert ports["dout"]["direction"] == "output"


def test_compact_ansi_port_declarations(tmp_path: Path) -> None:
    src = """\
module immgen (
    input[2:0] immsel,
    input[24:0] inst,
    output reg[31:0] imm
);
endmodule
"""
    result = parse_verilog(_write(tmp_path, "immgen.v", src))
    ports = {p["name"]: p for p in result["module"]["ports"]}

    assert set(ports.keys()) == {"immsel", "inst", "imm"}
    assert ports["immsel"]["direction"] == "input"
    assert ports["immsel"]["width"] == "[2:0]"
    assert ports["imm"]["direction"] == "output"
    assert ports["imm"]["width"] == "[31:0]"


def test_block_comment_stripping(tmp_path: Path) -> None:
    src = """\
/* a license
   block */
module top (input clk, output q);
    /* foo bar */ wire mid;
    counter u_cnt (.clk(clk), .q(mid));
    /* this looks like a module: module fake( */
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    assert result["module"]["name"] == "top"
    assert result["module"]["line"] == 3
    assert len(result["instances"]) == 1


def test_line_comment_stripping(tmp_path: Path) -> None:
    src = """\
module top (input clk, output q);  // header comment
    counter u_cnt (.clk(clk), .q(q));  // an instance
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    assert len(result["instances"]) == 1
    assert result["instances"][0]["instance_name"] == "u_cnt"


def test_no_module_raises(tmp_path: Path) -> None:
    src = "// just a comment\n"
    with pytest.raises(ValueError):
        parse_verilog(_write(tmp_path, "empty.v", src))


def test_missing_file_raises(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        parse_verilog(str(tmp_path / "nope.v"))


def test_connection_with_expression(tmp_path: Path) -> None:
    src = """\
module top (input clk, input [1:0] op, input v, output q);
    sub u_sub (
        .clk(clk),
        .en(v && (op == 2'b01 || op == 2'b10)),
        .out(q)
    );
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    inst = result["instances"][0]
    conns = {c["port"]: c for c in inst["connections"]}
    # The full expression is preserved as the net text
    assert "v" in conns["en"]["net"]
    assert "op" in conns["en"]["net"]
    # And bare identifier references are extracted
    assert set(conns["en"]["net_idents"]) == {"v", "op"}
    # Simple identifier connections still work
    assert conns["clk"]["net_idents"] == ["clk"]
    assert conns["out"]["net_idents"] == ["q"]


def test_assigns_simple(tmp_path: Path) -> None:
    src = """\
module top (input a, input b, output y, output z);
    wire mid;
    assign y = a & b;
    assign z = mid;
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    assigns = result["assigns"]
    assert len(assigns) == 2
    assert assigns[0]["lhs"] == "y"
    assert set(assigns[0]["rhs_idents"]) == {"a", "b"}
    assert assigns[0]["line"] == 3
    assert assigns[1]["lhs"] == "z"
    assert assigns[1]["rhs_idents"] == ["mid"]
    assert assigns[1]["line"] == 4


def test_always_block_reads_writes(tmp_path: Path) -> None:
    src = """\
module top (input clk, input rst, input d, output reg q);
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            q <= 1'b0;
        end else begin
            q <= d;
        end
    end
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    blocks = result["procedurals"]
    assert len(blocks) == 1
    blk = blocks[0]
    assert blk["kind"] == "always"
    assert "q" in blk["writes"]
    assert "rst" in blk["reads"]
    assert "d" in blk["reads"]
    # Sensitivity-list signals are excluded from the block analysis (already
    # consumed by the parser); reads should not include keywords.
    assert "posedge" not in blk["reads"]


def test_always_comb_with_case(tmp_path: Path) -> None:
    src = """\
module top (input [1:0] sel, input a, input b, output reg y);
    always @(*) begin
        case (sel)
            2'b00: y = a;
            2'b01: y = b;
            default: y = 1'b0;
        endcase
    end
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    blk = result["procedurals"][0]
    assert "y" in blk["writes"]
    assert set(blk["reads"]) >= {"sel", "a", "b"}


def test_keywords_not_treated_as_instances(tmp_path: Path) -> None:
    src = """\
module top (input clk, output q);
    reg state;
    always @(posedge clk) begin
        state <= ~state;
    end
    assign q = state;
endmodule
"""
    result = parse_verilog(_write(tmp_path, "top.v", src))
    assert result["instances"] == []


def test_hierarchy_recurses_into_submodules(tmp_path: Path) -> None:
    _write(tmp_path, "leaf.v", """\
module leaf (input din, output dout);
endmodule
""")
    _write(tmp_path, "mid.v", """\
module mid (input clk, output done);
    leaf u_leaf (.din(clk), .dout(done));
endmodule
""")
    top = _write(tmp_path, "top.v", """\
module top (input clk, output done);
    mid u_mid (.clk(clk), .done(done));
endmodule
""")

    result = parse_verilog(top)
    hierarchy = result["hierarchy"]

    assert hierarchy["moduleName"] == "top"
    mid = hierarchy["children"][0]
    assert mid["moduleName"] == "mid"
    assert mid["instanceName"] == "u_mid"
    assert mid["definitionFile"].endswith("mid.v")
    leaf = mid["children"][0]
    assert leaf["moduleName"] == "leaf"
    assert leaf["instanceName"] == "u_leaf"
    assert leaf["definitionFile"].endswith("leaf.v")
    assert [p["name"] for p in leaf["ports"]] == ["din", "dout"]


def test_hierarchy_marks_missing_submodule_unresolved(tmp_path: Path) -> None:
    top = _write(tmp_path, "top.v", """\
module top (input clk);
    missing_mod u_missing (.clk(clk));
endmodule
""")

    result = parse_verilog(top)
    child = result["hierarchy"]["children"][0]

    assert child["moduleName"] == "missing_mod"
    assert child["instanceName"] == "u_missing"
    assert child["unresolved"] is True
    assert child["children"] == []
    assert "definitionFile" not in child


def test_hierarchy_does_not_loop_on_recursive_modules(tmp_path: Path) -> None:
    top = _write(tmp_path, "loop.v", """\
module loop (input clk);
    loop u_loop (.clk(clk));
endmodule
""")

    result = parse_verilog(top)
    child = result["hierarchy"]["children"][0]

    assert child["moduleName"] == "loop"
    assert child["instanceName"] == "u_loop"
    assert child["unresolved"] is True
    assert child["children"] == []
