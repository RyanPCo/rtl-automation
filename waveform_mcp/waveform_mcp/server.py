"""MCP server for waveform debugging."""

import json
from mcp.server.fastmcp import FastMCP

from .events import Event
from .waveform import count_events, find_nth_event_time, open_waveform

mcp = FastMCP("waveform-mcp")


@mcp.tool()
def find_nth_event(
    waveform_file: str,
    signals: list[str],
    events: list[dict],
    n: int,
    after_time: int = 0,
) -> str:
    """Find the nth time all signals have their corresponding events simultaneously.

    Args:
        waveform_file: Path to the waveform file (.vcd or .fst).
        signals: List of signal names (hierarchical, e.g. "top.module.signal").
        events: List of event specifications, same length as signals.
                Each event is a dict with:
                - "type": One of "rise", "fall", "become_x", "become_z",
                          "unbecome_x", "unbecome_z", "transition_to"
                - "value": Required only for "transition_to" events.
                Example: [{"type": "rise"}, {"type": "transition_to", "value": "b1010"}]
        n: Which occurrence to find (1-indexed, e.g., 1 for first, 2 for second).
        after_time: Only consider events after this simulation time (default: 0).

    Returns:
        JSON string with the result:
        - On success: {"time": <int>} - the simulation time of the nth occurrence
        - On not found: {"time": null, "message": "..."}
        - On error: {"error": "..."}
    """
    try:
        if len(signals) != len(events):
            return json.dumps({
                "error": f"signals and events must have same length (got {len(signals)} signals, {len(events)} events)"
            })

        reader = open_waveform(waveform_file)
        parsed_events = [Event.from_dict(e) for e in events]

        result = find_nth_event_time(reader, signals, parsed_events, n, after_time)

        if result is None:
            return json.dumps({
                "time": None,
                "message": f"Could not find occurrence #{n} of the specified events after time {after_time}"
            })

        return json.dumps({"time": result})

    except FileNotFoundError:
        return json.dumps({"error": f"Waveform file not found: {waveform_file}"})
    except KeyError as e:
        return json.dumps({"error": f"Signal not found: {e}"})
    except Exception as e:
        return json.dumps({"error": str(e)})


@mcp.tool()
def count_event_occurrences(
    waveform_file: str,
    signals: list[str],
    events: list[dict],
    after_time: int = 0,
) -> str:
    """Count how many times all signals have their corresponding events simultaneously.

    Args:
        waveform_file: Path to the waveform file (.vcd or .fst).
        signals: List of signal names (hierarchical, e.g. "top.module.signal").
        events: List of event specifications, same length as signals.
                Each event is a dict with:
                - "type": One of "rise", "fall", "become_x", "become_z",
                          "unbecome_x", "unbecome_z", "transition_to"
                - "value": Required only for "transition_to" events.
                Example: [{"type": "rise"}, {"type": "transition_to", "value": "b1010"}]
        after_time: Only consider events after this simulation time (default: 0).

    Returns:
        JSON string with the result:
        - On success: {"count": <int>} - number of times the events occurred
        - On error: {"error": "..."}
    """
    try:
        if len(signals) != len(events):
            return json.dumps({
                "error": f"signals and events must have same length (got {len(signals)} signals, {len(events)} events)"
            })

        reader = open_waveform(waveform_file)
        parsed_events = [Event.from_dict(e) for e in events]

        result = count_events(reader, signals, parsed_events, after_time)

        return json.dumps({"count": result})

    except FileNotFoundError:
        return json.dumps({"error": f"Waveform file not found: {waveform_file}"})
    except KeyError as e:
        return json.dumps({"error": f"Signal not found: {e}"})
    except Exception as e:
        return json.dumps({"error": str(e)})


def main():
    """Run the MCP server."""
    mcp.run()


if __name__ == "__main__":
    main()
