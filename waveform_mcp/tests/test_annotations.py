import json
from pathlib import Path

import pytest

from waveform_mcp.annotations import annotate_wavedrom_bug
from waveform_mcp.server import annotate_wavedrom_bug as annotate_wavedrom_bug_tool


VCD_CONTENT = """$date
  today
$end
$version
  test
$end
$timescale 1ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 1 # valid $end
$var wire 8 " data [7:0] $end
$upscope $end
$enddefinitions $end
#0
0!
0#
b00000000 "
#5
1!
#10
0!
#12
b00000001 "
#15
1!
1#
#20
0!
#25
1!
b00000010 "
#30
0!
0#
#35
1!
b00000011 "
"""


def write_vcd(tmp_path: Path) -> Path:
    vcd_file = tmp_path / "trace.vcd"
    vcd_file.write_text(VCD_CONTENT)
    return vcd_file


def test_annotates_vcd_with_zero_based_inclusive_cycle_range(tmp_path: Path):
    vcd_file = write_vcd(tmp_path)

    result = annotate_wavedrom_bug(
        waveform_file=str(vcd_file),
        clock_signal="top.clk",
        cycle_start=1,
        cycle_end=2,
        signals=["top.valid", "top.data[7:0]"],
        diagnosis="valid asserted with bad data",
        context_cycles=1,
    )

    assert result["cycle_start"] == 1
    assert result["cycle_end"] == 2
    assert result["svg"].startswith("<svg")
    assert "WaveDrom" in result["svg"]
    assert '<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>' in result["svg"]
    assert "output_file" not in result
    assert not (tmp_path / "trace.wavedrom.cycles-1-2.svg").exists()

    wavejson = result["wavejson"]
    assert wavejson["signal"][0] == {
        "name": "cycle",
        "wave": "====",
        "data": ["0", "1", "2", "3"],
    }
    assert wavejson["signal"][2] == {"name": "top.valid", "wave": "01.0"}
    assert wavejson["signal"][3] == {
        "name": "top.data[7:0]",
        "wave": "====",
        "data": ["00000000", "00000001", "00000010", "00000011"],
    }
    assert wavejson["signal"][4] == {
        "name": "BUG",
        "wave": "x=.x",
        "data": ["valid asserted with bad data"],
    }


def test_context_cycles_clamp_to_trace_boundaries(tmp_path: Path):
    vcd_file = write_vcd(tmp_path)

    result = annotate_wavedrom_bug(
        waveform_file=str(vcd_file),
        clock_signal="top.clk",
        cycle_start=0,
        cycle_end=0,
        signals=["top.valid"],
        diagnosis="first cycle issue",
        context_cycles=10,
    )

    assert result["wavejson"]["signal"][0]["data"] == ["0", "1", "2", "3"]
    assert result["wavejson"]["signal"][-1]["wave"] == "=xxx"


def test_server_tool_returns_json_string(tmp_path: Path):
    vcd_file = write_vcd(tmp_path)

    payload = json.loads(
        annotate_wavedrom_bug_tool(
            waveform_file=str(vcd_file),
            clock_signal="top.clk",
            cycle_start=0,
            cycle_end=0,
            signals=["top.valid"],
            diagnosis="server path",
            background_color="#f8fafc",
        )
    )

    assert payload["svg"].startswith("<svg")
    assert 'fill="#f8fafc"' in payload["svg"]
    assert "output_file" not in payload
    assert payload["wavejson"]["signal"][-1]["data"] == ["server path"]


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"cycle_start": 2, "cycle_end": 1}, "cycle_start must be <= cycle_end"),
        ({"cycle_start": -1, "cycle_end": 1}, "must be non-negative"),
        ({"cycle_start": 0, "cycle_end": 99}, "exceeds available cycles"),
        ({"signals": []}, "signals must contain at least one signal"),
    ],
)
def test_rejects_invalid_cycle_requests(tmp_path: Path, kwargs: dict, message: str):
    vcd_file = write_vcd(tmp_path)
    params = {
        "waveform_file": str(vcd_file),
        "clock_signal": "top.clk",
        "cycle_start": 0,
        "cycle_end": 0,
        "signals": ["top.valid"],
        "diagnosis": "bad",
    }
    params.update(kwargs)

    with pytest.raises(ValueError, match=message):
        annotate_wavedrom_bug(**params)


def test_rejects_non_vcd_files(tmp_path: Path):
    fst_file = tmp_path / "trace.fst"
    fst_file.write_text("not a vcd")

    with pytest.raises(ValueError, match="only supports .vcd"):
        annotate_wavedrom_bug(
            waveform_file=str(fst_file),
            clock_signal="top.clk",
            cycle_start=0,
            cycle_end=0,
            signals=["top.valid"],
            diagnosis="bad",
        )


def test_rejects_missing_signals(tmp_path: Path):
    vcd_file = write_vcd(tmp_path)

    with pytest.raises(KeyError):
        annotate_wavedrom_bug(
            waveform_file=str(vcd_file),
            clock_signal="top.missing_clk",
            cycle_start=0,
            cycle_end=0,
            signals=["top.valid"],
            diagnosis="bad",
        )
