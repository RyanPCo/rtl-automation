"""Waveform parsing for VCD and FST files."""

import subprocess
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path

from vcdvcd import VCDVCD

from .events import Event, check_event


@dataclass
class SignalChange:
    """A value change for a signal at a specific time."""

    time: int
    value: str


class WaveformReader(ABC):
    """Abstract base class for waveform file readers."""

    @abstractmethod
    def get_signal_changes(self, signal_name: str) -> list[SignalChange]:
        """Get all value changes for a signal.

        Args:
            signal_name: The hierarchical signal name.

        Returns:
            List of SignalChange objects ordered by time.
        """
        pass

    @abstractmethod
    def list_signals(self) -> list[str]:
        """List all signal names in the waveform.

        Returns:
            List of hierarchical signal names.
        """
        pass


class VCDReader(WaveformReader):
    """Reader for VCD (Value Change Dump) files."""

    def __init__(self, filepath: str | Path):
        self.filepath = Path(filepath)
        self._vcd = VCDVCD(str(self.filepath))

    def get_signal_changes(self, signal_name: str) -> list[SignalChange]:
        signal = self._vcd[signal_name]
        changes = []
        for time, value in signal.tv:
            changes.append(SignalChange(time=int(time), value=value))
        return changes

    def list_signals(self) -> list[str]:
        references = getattr(self._vcd, "references_to_ids", None)
        if isinstance(references, dict):
            return sorted(references.keys())

        signals = getattr(self._vcd, "signals", [])
        if isinstance(signals, dict):
            return sorted(signals.keys())
        if isinstance(signals, list):
            return sorted(str(signal) for signal in signals)

        return []


class FSTReader(WaveformReader):
    """Reader for FST (Fast Signal Trace) files.

    Uses fstdump (from GTKWave) to convert FST to VCD, then parses the VCD.
    """

    def __init__(self, filepath: str | Path):
        self.filepath = Path(filepath)
        self._vcd_content = self._convert_to_vcd()
        # Write to temp file for vcdvcd to parse
        self._temp_vcd = self.filepath.with_suffix(".tmp.vcd")
        self._temp_vcd.write_text(self._vcd_content)
        self._vcd = VCDVCD(str(self._temp_vcd))

    def _convert_to_vcd(self) -> str:
        """Convert FST to VCD using fstdump."""
        result = subprocess.run(
            ["fst2vcd", str(self.filepath)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout

    def get_signal_changes(self, signal_name: str) -> list[SignalChange]:
        signal = self._vcd[signal_name]
        changes = []
        for time, value in signal.tv:
            changes.append(SignalChange(time=int(time), value=value))
        return changes

    def list_signals(self) -> list[str]:
        references = getattr(self._vcd, "references_to_ids", None)
        if isinstance(references, dict):
            return sorted(references.keys())

        signals = getattr(self._vcd, "signals", [])
        if isinstance(signals, dict):
            return sorted(signals.keys())
        if isinstance(signals, list):
            return sorted(str(signal) for signal in signals)

        return []

    def __del__(self):
        # Clean up temp file
        if hasattr(self, "_temp_vcd") and self._temp_vcd.exists():
            self._temp_vcd.unlink()


def open_waveform(filepath: str | Path) -> WaveformReader:
    """Open a waveform file and return the appropriate reader.

    Args:
        filepath: Path to the waveform file (.vcd or .fst).

    Returns:
        WaveformReader instance for the file.

    Raises:
        ValueError: If the file extension is not supported.
    """
    path = Path(filepath)
    suffix = path.suffix.lower()

    if suffix == ".vcd":
        return VCDReader(path)
    elif suffix == ".fst":
        return FSTReader(path)
    else:
        raise ValueError(f"Unsupported waveform file format: {suffix}")


def find_nth_event_time(
    reader: WaveformReader,
    signals: list[str],
    events: list[Event],
    n: int,
    after_time: int = 0,
) -> int | None:
    """Find the nth time all signals have their corresponding events simultaneously.

    Args:
        reader: WaveformReader instance.
        signals: List of signal names.
        events: List of events, same length as signals. Each event corresponds
                to the signal at the same index.
        n: Which occurrence to find (1-indexed).
        after_time: Only consider events after this time.

    Returns:
        The time of the nth occurrence, or None if not found.
    """
    if len(signals) != len(events):
        raise ValueError("signals and events must have the same length")

    if n < 1:
        raise ValueError("n must be >= 1")

    # Get all changes for each signal
    all_changes: dict[str, list[SignalChange]] = {}
    for signal in signals:
        all_changes[signal] = reader.get_signal_changes(signal)

    # Collect all unique times where any signal changes (after after_time)
    all_times: set[int] = set()
    for changes in all_changes.values():
        for change in changes:
            if change.time > after_time:
                all_times.add(change.time)

    # Sort times
    sorted_times = sorted(all_times)

    # For each time, check if all signals have their events at that time
    occurrence_count = 0

    for time in sorted_times:
        all_matched = True

        for signal, event in zip(signals, events):
            changes = all_changes[signal]

            # Find the change at this time and the previous value
            prev_value = None
            curr_value = None

            for i, change in enumerate(changes):
                if change.time == time:
                    curr_value = change.value
                    # Find previous value
                    if i > 0:
                        prev_value = changes[i - 1].value
                    break
                elif change.time < time:
                    prev_value = change.value

            # If no change at this time for this signal, it doesn't match
            if curr_value is None:
                all_matched = False
                break

            # Check if the event matches
            if prev_value is None:
                # No previous value, can't determine transition
                all_matched = False
                break

            if not check_event(prev_value, curr_value, event):
                all_matched = False
                break

        if all_matched:
            occurrence_count += 1
            if occurrence_count == n:
                return time

    return None


def count_events(
    reader: WaveformReader,
    signals: list[str],
    events: list[Event],
    after_time: int = 0,
) -> int:
    """Count how many times all signals have their corresponding events simultaneously.

    Args:
        reader: WaveformReader instance.
        signals: List of signal names.
        events: List of events, same length as signals. Each event corresponds
                to the signal at the same index.
        after_time: Only consider events after this time.

    Returns:
        The number of occurrences.
    """
    if len(signals) != len(events):
        raise ValueError("signals and events must have the same length")

    # Get all changes for each signal
    all_changes: dict[str, list[SignalChange]] = {}
    for signal in signals:
        all_changes[signal] = reader.get_signal_changes(signal)

    # Collect all unique times where any signal changes (after after_time)
    all_times: set[int] = set()
    for changes in all_changes.values():
        for change in changes:
            if change.time > after_time:
                all_times.add(change.time)

    # Sort times
    sorted_times = sorted(all_times)

    # Count occurrences
    count = 0

    for time in sorted_times:
        all_matched = True

        for signal, event in zip(signals, events):
            changes = all_changes[signal]

            # Find the change at this time and the previous value
            prev_value = None
            curr_value = None

            for i, change in enumerate(changes):
                if change.time == time:
                    curr_value = change.value
                    if i > 0:
                        prev_value = changes[i - 1].value
                    break
                elif change.time < time:
                    prev_value = change.value

            if curr_value is None:
                all_matched = False
                break

            if prev_value is None:
                all_matched = False
                break

            if not check_event(prev_value, curr_value, event):
                all_matched = False
                break

        if all_matched:
            count += 1

    return count
