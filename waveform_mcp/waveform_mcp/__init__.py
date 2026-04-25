"""Waveform MCP server for RTL debugging."""

from .annotations import annotate_wavedrom_bug
from .events import Event, EventType
from .server import mcp
from .waveform import (
    FSTReader,
    VCDReader,
    WaveformReader,
    count_events,
    find_nth_event_time,
    open_waveform,
)

__all__ = [
    "Event",
    "EventType",
    "annotate_wavedrom_bug",
    "FSTReader",
    "VCDReader",
    "WaveformReader",
    "count_events",
    "find_nth_event_time",
    "mcp",
    "open_waveform",
]
