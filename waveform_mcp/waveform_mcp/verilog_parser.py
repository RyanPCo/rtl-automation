"""Structural Verilog/SystemVerilog parser.

Extracts module name, ports, nets (wire/reg), and submodule instantiations
with 1-based source line numbers, suitable for rendering a block diagram.
Only the first module in a file is parsed.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Optional

VERILOG_KEYWORDS = frozenset({
    "module", "endmodule", "input", "output", "inout", "wire", "reg", "logic",
    "always", "always_ff", "always_comb", "always_latch", "assign",
    "begin", "end", "if", "else", "case", "endcase", "casex", "casez",
    "for", "while", "do", "repeat", "forever",
    "generate", "endgenerate", "genvar",
    "parameter", "localparam", "defparam",
    "posedge", "negedge", "edge",
    "initial", "function", "endfunction", "task", "endtask",
    "specify", "endspecify", "primitive", "endprimitive",
    "automatic", "static", "const", "default",
    "typedef", "struct", "union", "enum", "packed",
    "import", "export", "package", "endpackage",
    "interface", "endinterface", "modport", "clocking", "endclocking",
    "return", "break", "continue",
})

PORT_DIRECTIONS = {"input", "output", "inout"}

_MODULE_RE = re.compile(r"\bmodule\s+(\w+)", re.MULTILINE)
_WIDTH_RE = r"(?:\[[^\]]+\])?"
_BODY_PORT_RE = re.compile(
    rf"\b(input|output|inout)\s*(?:wire\s*|reg\s*|logic\s*)?({_WIDTH_RE})\s*([\w\s,]+?)\s*;",
)
_NET_RE = re.compile(
    rf"\b(wire|reg)\s+({_WIDTH_RE})\s*([\w\s,]+?)\s*;",
)
_ANSI_PORT_RE = re.compile(
    rf"(input|output|inout)\s*(?:wire\s*|reg\s*|logic\s*)?({_WIDTH_RE})\s*(\w+)"
)
_IDENT_RE = re.compile(r"\b([a-zA-Z_]\w*)\b")


def _strip_block_comments(source: str) -> str:
    """Replace /* ... */ blocks with spaces, preserving newlines for line accuracy."""
    def repl(match: re.Match[str]) -> str:
        text = match.group(0)
        return "".join("\n" if c == "\n" else " " for c in text)
    return re.sub(r"/\*.*?\*/", repl, source, flags=re.DOTALL)


def _strip_line_comments(line: str) -> str:
    """Remove // line comments (naive — does not honor strings)."""
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def _line_number(source: str, char_index: int) -> int:
    """Return 1-based line number containing the given character index."""
    return source.count("\n", 0, char_index) + 1


def _parse_ansi_ports(header: str, header_start_line: int) -> list[dict]:
    """Parse ANSI-style port list from inside the module header parentheses."""
    ports: list[dict] = []
    last_dir: Optional[str] = None
    last_width = "1"
    for match in re.finditer(
        rf"(?:(input|output|inout)\s*)?(?:wire\s*|reg\s*|logic\s*)?({_WIDTH_RE})?\s*(\w+)\s*(?:,|$|\))",
        header,
        re.DOTALL,
    ):
        direction, width, name = match.group(1), match.group(2), match.group(3)
        if name in VERILOG_KEYWORDS or not name:
            continue
        if direction:
            last_dir = direction
            last_width = width or "1"
        if last_dir is None:
            continue
        port_line = header_start_line + header[: match.start()].count("\n")
        ports.append({
            "name": name,
            "direction": last_dir,
            "width": width or last_width,
            "line": port_line,
        })
    return ports


def _split_names(names_blob: str) -> list[str]:
    return [n.strip() for n in names_blob.split(",") if n.strip()]


def _extract_identifiers(expr: str) -> list[str]:
    """Return distinct bare identifier references in a Verilog expression."""
    seen: set[str] = set()
    out: list[str] = []
    for match in _IDENT_RE.finditer(expr):
        ident = match.group(1)
        if ident in VERILOG_KEYWORDS or ident in PORT_DIRECTIONS:
            continue
        start = match.start()
        # Skip macro names (`IDENT)
        if start > 0 and expr[start - 1] == "`":
            continue
        # Skip Verilog number-literal type suffixes (e.g. 8'hFF, 1'b0): the
        # identifier follows a `'` and the previous chars are digits.
        if start > 0 and expr[start - 1] == "'":
            continue
        if ident not in seen:
            seen.add(ident)
            out.append(ident)
    return out


def _parse_port_connections(blob: str) -> list[dict]:
    """Parse named port connections `.port(expr)` from inside an instance's port list.

    Handles arbitrary nested parens in the expression.
    """
    conns: list[dict] = []
    i = 0
    n = len(blob)
    while i < n:
        # Find next '.<ident>('
        if blob[i] != ".":
            i += 1
            continue
        j = i + 1
        m = _IDENT_RE.match(blob, j)
        if not m:
            i += 1
            continue
        port = m.group(1)
        k = m.end()
        # Skip whitespace before '('
        while k < n and blob[k].isspace():
            k += 1
        if k >= n or blob[k] != "(":
            i = k
            continue
        close = _find_matching_paren(blob, k)
        if close < 0:
            break
        expr = blob[k + 1 : close].strip()
        conns.append({
            "port": port,
            "net": expr,
            "net_idents": _extract_identifiers(expr),
        })
        i = close + 1
    return conns


def _find_matching_paren(source: str, open_idx: int) -> int:
    """Given index of an open '(', return index of the matching ')'. -1 if none."""
    depth = 0
    i = open_idx
    while i < len(source):
        c = source[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _find_block_end(text: str, start: int) -> int:
    """Find the end of a procedural block starting at `start`.

    If text[start:] begins with `begin`, returns the index just past the matching
    `end`. Otherwise returns the index just past the next `;` (single statement).
    """
    n = len(text)
    pos = start
    while pos < n and text[pos].isspace():
        pos += 1
    if text[pos:pos + 5] == "begin" and (pos + 5 >= n or not text[pos + 5].isalnum() and text[pos + 5] != "_"):
        depth = 1
        i = pos + 5
        while i < n and depth > 0:
            # Tokenize loosely: look for begin/end/case/endcase keywords
            m = re.match(r"\b(begin|end|case|casex|casez|endcase|fork|join|join_any|join_none|function|endfunction|task|endtask)\b", text[i:])
            if m:
                kw = m.group(1)
                if kw in ("begin", "case", "casex", "casez", "fork", "function", "task"):
                    depth += 1
                elif kw in ("end", "endcase", "join", "join_any", "join_none", "endfunction", "endtask"):
                    depth -= 1
                i += len(kw)
            else:
                i += 1
        return i
    # Single statement until next ';'
    semi = text.find(";", pos)
    return semi + 1 if semi >= 0 else n


def _parse_assigns(body: str, body_start: int, source: str) -> list[dict]:
    """Find continuous `assign LHS = RHS;` statements (top-level only)."""
    assigns: list[dict] = []
    for match in re.finditer(r"\bassign\b", body):
        pos = match.end()
        while pos < len(body) and body[pos].isspace():
            pos += 1
        # Skip optional drive strength `(strong0, strong1)` etc. — rare; ignore for now
        # LHS: identifier with optional bit/part-select
        m = re.match(r"(\w+)(\s*\[[^\]]+\])?", body[pos:])
        if not m:
            continue
        lhs = m.group(1)
        if lhs in VERILOG_KEYWORDS:
            continue
        pos += m.end()
        while pos < len(body) and body[pos].isspace():
            pos += 1
        # Expect '='
        if pos >= len(body) or body[pos] != "=":
            continue
        pos += 1
        # Find statement-terminating ';' at paren depth 0
        depth = 0
        rhs_start = pos
        while pos < len(body):
            c = body[pos]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == ";" and depth == 0:
                break
            pos += 1
        rhs = body[rhs_start:pos]
        rhs_idents = [i for i in _extract_identifiers(rhs) if i != lhs]
        assigns.append({
            "lhs": lhs,
            "rhs_idents": rhs_idents,
            "line": _line_number(source, body_start + match.start()),
        })
    return assigns


_LHS_ASSIGN_RE = re.compile(
    r"\b(\w+)\s*(?:\[[^\]]+\])?\s*(?:<=|(?<![<>=!~])=(?!=))"
)


def _parse_procedurals(body: str, body_start: int, source: str) -> list[dict]:
    """Find each `always*`/`initial` block; record read/write identifier sets."""
    blocks: list[dict] = []
    for match in re.finditer(r"\b(always(?:_ff|_comb|_latch)?|initial)\b", body):
        kind = match.group(1)
        pos = match.end()
        while pos < len(body) and body[pos].isspace():
            pos += 1
        # Skip optional sensitivity list `@(...)` or `@*` or `@ident`
        if pos < len(body) and body[pos] == "@":
            pos += 1
            while pos < len(body) and body[pos].isspace():
                pos += 1
            if pos < len(body) and body[pos] == "(":
                close = _find_matching_paren(body, pos)
                if close < 0:
                    continue
                pos = close + 1
            elif pos < len(body) and body[pos] == "*":
                pos += 1
            else:
                # @ident — skip identifier
                im = _IDENT_RE.match(body, pos)
                if im:
                    pos = im.end()
            while pos < len(body) and body[pos].isspace():
                pos += 1
        block_end = _find_block_end(body, pos)
        block_text = body[pos:block_end]

        # Writes: LHS of `<=` or `=` (excluding `==`, `<=` comparison handled by negative lookbehind)
        writes: list[str] = []
        seen_w: set[str] = set()
        for lm in _LHS_ASSIGN_RE.finditer(block_text):
            name = lm.group(1)
            if name in VERILOG_KEYWORDS or name in PORT_DIRECTIONS:
                continue
            if name not in seen_w:
                seen_w.add(name)
                writes.append(name)

        # Reads: all identifiers minus writes (excluding keywords/macros etc.)
        all_idents = _extract_identifiers(block_text)
        reads = [i for i in all_idents if i not in seen_w]

        blocks.append({
            "kind": kind,
            "reads": reads,
            "writes": writes,
            "line": _line_number(source, body_start + match.start()),
        })
    return blocks


def _parse_module_ports(filepath: str) -> dict[str, str]:
    """Parse a Verilog file and return a dict mapping port name → direction."""
    try:
        result = _parse_verilog_flat(filepath, annotate_connections=False)
        return {p["name"]: p["direction"] for p in result["module"]["ports"]}
    except (FileNotFoundError, ValueError):
        return {}


def _find_submodule_file(module_type: str, search_dir: Path) -> Optional[Path]:
    """Search for a file defining the given module in the same directory tree."""
    for ext in (".v", ".sv"):
        candidate = search_dir / f"{module_type}{ext}"
        if candidate.exists():
            return candidate
    # Also check subdirectories one level deep
    for ext in (".v", ".sv"):
        for child in search_dir.iterdir():
            if child.is_dir():
                candidate = child / f"{module_type}{ext}"
                if candidate.exists():
                    return candidate
    return None


def _parse_verilog_flat(filepath: str, annotate_connections: bool = True) -> dict:
    """Parse a Verilog/SystemVerilog file and return structural data.

    Returns a dict with keys: file, module, nets, instances. Raises
    FileNotFoundError if the file does not exist and ValueError if no
    module declaration is found.
    """
    path = Path(filepath)
    if not path.exists():
        raise FileNotFoundError(f"File not found: {filepath}")

    raw = path.read_text(encoding="utf-8", errors="replace")
    source = _strip_block_comments(raw)
    # Strip line comments per-line (preserves line indices)
    cleaned_lines = [_strip_line_comments(ln) for ln in source.split("\n")]
    source = "\n".join(cleaned_lines)

    module_match = _MODULE_RE.search(source)
    if not module_match:
        raise ValueError("No module declaration found")

    module_name = module_match.group(1)
    module_line = _line_number(source, module_match.start())

    # Find the module body: from header end to first 'endmodule'. A module can
    # have an optional parameter block before the actual port list:
    #   module foo #(parameter W = 8) (input [W-1:0] a);
    header_pos = module_match.end()
    while header_pos < len(source) and source[header_pos].isspace():
        header_pos += 1
    if header_pos < len(source) and source[header_pos] == "#":
        header_pos += 1
        while header_pos < len(source) and source[header_pos].isspace():
            header_pos += 1
        if header_pos >= len(source) or source[header_pos] != "(":
            raise ValueError("Malformed module parameter block")
        param_close = _find_matching_paren(source, header_pos)
        if param_close < 0:
            raise ValueError("Malformed module parameter block")
        header_pos = param_close + 1
        while header_pos < len(source) and source[header_pos].isspace():
            header_pos += 1

    header_paren = header_pos if header_pos < len(source) and source[header_pos] == "(" else -1
    ansi_ports: list[dict] = []
    body_start: int

    if header_paren >= 0:
        # Could still be old-style with empty () or no port list before ;
        header_close = _find_matching_paren(source, header_paren)
        semi_after = source.find(";", header_close + 1 if header_close >= 0 else module_match.end())
        if header_close < 0 or semi_after < 0:
            raise ValueError("Malformed module header")
        header_inner = source[header_paren + 1 : header_close]
        if header_inner.strip():
            ansi_ports = _parse_ansi_ports(
                header_inner,
                _line_number(source, header_paren + 1),
            )
        body_start = semi_after + 1
    else:
        # No parens at all (rare); treat next ';' as end of header
        semi_after = source.find(";", module_match.end())
        if semi_after < 0:
            raise ValueError("Malformed module header")
        body_start = semi_after + 1

    end_match = re.search(r"\bendmodule\b", source[body_start:])
    body_end = body_start + end_match.start() if end_match else len(source)
    body = source[body_start:body_end]

    # Body-style port declarations
    body_ports: list[dict] = []
    for match in _BODY_PORT_RE.finditer(body):
        direction = match.group(1)
        width = match.group(2) or "1"
        for name in _split_names(match.group(3)):
            decl_line = _line_number(source, body_start + match.start())
            body_ports.append({
                "name": name,
                "direction": direction,
                "width": width,
                "line": decl_line,
            })

    # Merge: prefer ANSI ports; supplement with body-style declarations.
    # If a port appears both places (header lists name, body declares direction),
    # ANSI wins for direction/line. Body-only ports are appended.
    seen_port_names = {p["name"] for p in ansi_ports}
    merged_ports = list(ansi_ports)
    for p in body_ports:
        if p["name"] not in seen_port_names:
            merged_ports.append(p)
            seen_port_names.add(p["name"])

    # Net declarations
    nets: list[dict] = []
    for match in _NET_RE.finditer(body):
        kind = match.group(1)
        width = match.group(2) or "1"
        for name in _split_names(match.group(3)):
            if name in seen_port_names:
                continue  # already declared as a port
            nets.append({
                "name": name,
                "kind": kind,
                "width": width,
                "line": _line_number(source, body_start + match.start()),
            })

    # Instantiations: walk lines, attempt to parse each as an instance.
    instances: list[dict] = []
    body_lines = body.split("\n")
    line_starts: list[int] = []
    cursor = 0
    for line in body_lines:
        line_starts.append(cursor)
        cursor += len(line) + 1  # +1 for the newline

    for line_idx, raw_line in enumerate(body_lines):
        stripped = raw_line.lstrip()
        if not stripped or stripped.startswith(("//", "/*", "*")):
            continue
        leading_ws = len(raw_line) - len(stripped)
        # First token must be a non-keyword identifier
        word_match = re.match(r"(\w+)", stripped)
        if not word_match:
            continue
        module_type = word_match.group(1)
        if module_type in VERILOG_KEYWORDS or module_type in PORT_DIRECTIONS:
            continue

        # Walk forward through `body` to look for `[#(...)] <name> (`
        pos = line_starts[line_idx] + leading_ws + len(module_type)
        # Skip whitespace (across lines)
        while pos < len(body) and body[pos].isspace():
            pos += 1
        # Optional parameter override
        if pos < len(body) and body[pos] == "#":
            pos += 1
            while pos < len(body) and body[pos].isspace():
                pos += 1
            if pos >= len(body) or body[pos] != "(":
                continue
            close = _find_matching_paren(body, pos)
            if close < 0:
                continue
            pos = close + 1
            while pos < len(body) and body[pos].isspace():
                pos += 1
        # Instance name
        name_match = re.match(r"(\w+)", body[pos:])
        if not name_match:
            continue
        instance_name = name_match.group(1)
        if instance_name in VERILOG_KEYWORDS:
            continue
        pos += len(instance_name)
        # Skip whitespace and an optional unpacked-array dimension `[N]`
        while pos < len(body) and body[pos].isspace():
            pos += 1
        if pos < len(body) and body[pos] == "[":
            close_br = body.find("]", pos)
            if close_br < 0:
                continue
            pos = close_br + 1
            while pos < len(body) and body[pos].isspace():
                pos += 1
        # Open paren of port list
        if pos >= len(body) or body[pos] != "(":
            continue
        open_paren = pos
        close_paren = _find_matching_paren(body, open_paren)
        if close_paren < 0:
            continue
        port_blob = body[open_paren + 1 : close_paren]
        connections = _parse_port_connections(port_blob)
        inst_line = _line_number(source, body_start + line_starts[line_idx] + leading_ws)
        instances.append({
            "module_type": module_type,
            "instance_name": instance_name,
            "line": inst_line,
            "connections": connections,
        })

    assigns = _parse_assigns(body, body_start, source)
    procedurals = _parse_procedurals(body, body_start, source)

    if annotate_connections:
        # Look up submodule files to annotate connection directions.
        search_dir = path.parent
        submod_cache: dict[str, dict[str, str]] = {}
        for inst in instances:
            mt = inst["module_type"]
            if mt not in submod_cache:
                sub_file = _find_submodule_file(mt, search_dir)
                submod_cache[mt] = _parse_module_ports(str(sub_file)) if sub_file else {}
            port_dirs = submod_cache[mt]
            for conn in inst["connections"]:
                conn["direction"] = port_dirs.get(conn["port"], "unknown")
    else:
        for inst in instances:
            for conn in inst["connections"]:
                conn["direction"] = "unknown"

    return {
        "file": str(path.resolve()),
        "module": {
            "name": module_name,
            "line": module_line,
            "ports": merged_ports,
        },
        "nets": nets,
        "instances": instances,
        "assigns": assigns,
        "procedurals": procedurals,
    }


def _ports_from_connections(inst: dict) -> list[dict]:
    """Fallback ports for unresolved modules, based on known connection directions."""
    ports: list[dict] = []
    seen: set[str] = set()
    for conn in inst["connections"]:
        direction = conn.get("direction")
        if direction not in PORT_DIRECTIONS or conn["port"] in seen:
            continue
        seen.add(conn["port"])
        ports.append({
            "name": conn["port"],
            "direction": direction,
            "width": "1",
            "line": inst["line"],
        })
    return ports


def _build_hierarchy(
    parsed: dict,
    instance_name: Optional[str],
    instance_line: int,
    instance_file: str,
    node_id: str,
    stack: set[tuple[str, str]],
) -> dict:
    """Build a recursive module hierarchy rooted at an already-parsed module."""
    module_name = parsed["module"]["name"]
    definition_file = parsed["file"]
    key = (definition_file, module_name)

    node = {
        "id": node_id,
        "moduleName": module_name,
        "definitionFile": definition_file,
        "definitionLine": parsed["module"]["line"],
        "instanceFile": instance_file,
        "instanceLine": instance_line,
        "ports": parsed["module"]["ports"],
        "children": [],
    }
    if instance_name is not None:
        node["instanceName"] = instance_name

    if key in stack:
        node["unresolved"] = True
        return node

    next_stack = set(stack)
    next_stack.add(key)
    search_dir = Path(definition_file).parent

    for inst in parsed["instances"]:
        child_file = _find_submodule_file(inst["module_type"], search_dir)
        child_id = f"{node_id}/{inst['instance_name']}"
        if child_file is None:
            node["children"].append({
                "id": child_id,
                "moduleName": inst["module_type"],
                "instanceName": inst["instance_name"],
                "instanceFile": definition_file,
                "instanceLine": inst["line"],
                "ports": _ports_from_connections(inst),
                "children": [],
                "unresolved": True,
            })
            continue

        try:
            child_parsed = _parse_verilog_flat(str(child_file))
        except (FileNotFoundError, ValueError):
            node["children"].append({
                "id": child_id,
                "moduleName": inst["module_type"],
                "instanceName": inst["instance_name"],
                "instanceFile": definition_file,
                "instanceLine": inst["line"],
                "ports": _ports_from_connections(inst),
                "children": [],
                "unresolved": True,
            })
            continue

        node["children"].append(_build_hierarchy(
            child_parsed,
            inst["instance_name"],
            inst["line"],
            definition_file,
            child_id,
            next_stack,
        ))

    return node


def parse_verilog(filepath: str) -> dict:
    """Parse a Verilog/SystemVerilog file and return structural and hierarchy data."""
    parsed = _parse_verilog_flat(filepath)
    parsed["hierarchy"] = _build_hierarchy(
        parsed,
        None,
        parsed["module"]["line"],
        parsed["file"],
        "top",
        set(),
    )
    return parsed
