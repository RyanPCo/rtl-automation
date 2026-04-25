"""WaveDrom annotation helpers for VCD bug reports."""

import json
from bisect import bisect_right
from pathlib import Path

from .waveform import SignalChange, VCDReader


def annotate_wavedrom_bug(
    waveform_file: str,
    clock_signal: str,
    cycle_start: int,
    cycle_end: int,
    signals: list[str],
    diagnosis: str,
    context_cycles: int = 2,
    background_color: str = "#ffffff",
) -> dict:
    """Render an annotated WaveDrom SVG for a VCD bug report."""
    if Path(waveform_file).suffix.lower() != ".vcd":
        raise ValueError("annotate_wavedrom_bug only supports .vcd files")

    if cycle_start < 0 or cycle_end < 0:
        raise ValueError("cycle_start and cycle_end must be non-negative")
    if cycle_start > cycle_end:
        raise ValueError("cycle_start must be <= cycle_end")
    if context_cycles < 0:
        raise ValueError("context_cycles must be non-negative")
    if not signals:
        raise ValueError("signals must contain at least one signal")

    reader = VCDReader(waveform_file)
    available_signals = set(reader.list_signals())
    _require_signal(available_signals, clock_signal)
    for signal in signals:
        _require_signal(available_signals, signal)

    clock_changes = reader.get_signal_changes(clock_signal)
    rising_edges = _rising_edge_times(clock_changes)
    if not rising_edges:
        raise ValueError(f"Clock signal has no rising edges: {clock_signal}")
    if cycle_end >= len(rising_edges):
        raise ValueError(
            f"cycle_end {cycle_end} exceeds available cycles 0..{len(rising_edges) - 1}"
        )

    window_start = max(0, cycle_start - context_cycles)
    window_end = min(len(rising_edges) - 1, cycle_end + context_cycles)
    cycle_numbers = list(range(window_start, window_end + 1))
    sample_times = [rising_edges[cycle] for cycle in cycle_numbers]

    wavejson = {
        "head": {"text": "Annotated waveform"},
        "signal": [
            {
                "name": "cycle",
                "wave": "=" * len(cycle_numbers),
                "data": [str(c) for c in cycle_numbers],
            },
            {"name": clock_signal, "wave": "p" * len(cycle_numbers)},
        ],
        "config": {"hscale": 2},
    }

    for signal in signals:
        changes = reader.get_signal_changes(signal)
        samples = [_value_at(changes, sample_time) for sample_time in sample_times]
        wavejson["signal"].append(_signal_to_wavejson(signal, samples))

    wavejson["signal"].append(
        _bug_annotation_row(
            cycle_numbers=cycle_numbers,
            cycle_start=cycle_start,
            cycle_end=cycle_end,
            diagnosis=diagnosis,
        )
    )

    svg = _add_svg_background(_render_svg(wavejson), background_color)
    return {
        "svg": svg,
        "wavejson": wavejson,
        "cycle_start": cycle_start,
        "cycle_end": cycle_end,
    }


def _require_signal(available_signals: set[str], signal: str) -> None:
    if signal not in available_signals:
        raise KeyError(signal)


def _rising_edge_times(changes: list[SignalChange]) -> list[int]:
    edges = []
    previous = None
    for change in changes:
        current = _normalize_scalar(change.value)
        if previous == "0" and current == "1":
            edges.append(change.time)
        previous = current
    return edges


def _value_at(changes: list[SignalChange], time: int) -> str:
    change_times = [change.time for change in changes]
    index = bisect_right(change_times, time) - 1
    if index < 0:
        return "x"
    return changes[index].value


def _signal_to_wavejson(name: str, samples: list[str]) -> dict:
    if all(_is_scalar(sample) for sample in samples):
        return {"name": name, "wave": _scalar_wave(samples)}

    wave = []
    data = []
    previous = None
    for sample in samples:
        if sample == previous:
            wave.append(".")
            continue
        wave.append("=")
        data.append(_format_value(sample))
        previous = sample

    return {"name": name, "wave": "".join(wave), "data": data}


def _scalar_wave(samples: list[str]) -> str:
    wave = []
    previous = None
    for sample in samples:
        value = _normalize_scalar(sample)
        if value == previous:
            wave.append(".")
        else:
            wave.append(value)
            previous = value
    return "".join(wave)


def _bug_annotation_row(
    cycle_numbers: list[int],
    cycle_start: int,
    cycle_end: int,
    diagnosis: str,
) -> dict:
    wave = []
    in_bug = False
    for cycle in cycle_numbers:
        if cycle_start <= cycle <= cycle_end:
            wave.append("." if in_bug else "=")
            in_bug = True
        else:
            wave.append("x")
            in_bug = False

    return {
        "name": "BUG",
        "wave": "".join(wave),
        "data": [_normalize_diagnosis(diagnosis)],
    }


def _is_scalar(value: str) -> bool:
    return len(value) == 1 and _normalize_scalar(value) in {"0", "1", "x", "z"}


def _normalize_scalar(value: str) -> str:
    normalized = value.lower()
    if normalized in {"0", "1", "x", "z"}:
        return normalized
    return "x"


def _format_value(value: str) -> str:
    return value if value else "x"


def _normalize_diagnosis(diagnosis: str) -> str:
    return " ".join(diagnosis.split()) or "Bug"


def _render_svg(wavejson: dict) -> str:
    try:
        import wavedrom
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Missing Python dependency: wavedrom. Install waveform_mcp dependencies with "
            'python3 -m pip install -e "waveform_mcp" from the repo root.'
        ) from exc

    return wavedrom.render(json.dumps(wavejson)).tostring()


def _add_svg_background(svg: str, background_color: str) -> str:
    if not background_color:
        return svg

    root_end = svg.find(">")
    if root_end == -1:
        return svg

    background = (
        f'<rect x="0" y="0" width="100%" height="100%" '
        f'fill="{_escape_xml_attr(background_color)}"/>'
    )
    return f"{svg[:root_end + 1]}{background}{svg[root_end + 1:]}"


def _escape_xml_attr(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace('"', "&quot;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )
