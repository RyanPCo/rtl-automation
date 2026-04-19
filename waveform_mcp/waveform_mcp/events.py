"""Event type definitions for waveform signal transitions."""

from dataclasses import dataclass
from enum import Enum
from typing import Union


class EventType(str, Enum):
    """Types of signal events that can be detected."""

    RISE = "rise"
    FALL = "fall"
    BECOME_X = "become_x"
    BECOME_Z = "become_z"
    UNBECOME_X = "unbecome_x"
    UNBECOME_Z = "unbecome_z"
    TRANSITION_TO = "transition_to"


@dataclass
class Event:
    """Represents a signal event to detect.

    Attributes:
        event_type: The type of event to detect.
        value: For TRANSITION_TO events, the target value. None for other event types.
    """

    event_type: EventType
    value: str | None = None

    @classmethod
    def rise(cls) -> "Event":
        return cls(EventType.RISE)

    @classmethod
    def fall(cls) -> "Event":
        return cls(EventType.FALL)

    @classmethod
    def become_x(cls) -> "Event":
        return cls(EventType.BECOME_X)

    @classmethod
    def become_z(cls) -> "Event":
        return cls(EventType.BECOME_Z)

    @classmethod
    def unbecome_x(cls) -> "Event":
        return cls(EventType.UNBECOME_X)

    @classmethod
    def unbecome_z(cls) -> "Event":
        return cls(EventType.UNBECOME_Z)

    @classmethod
    def transition_to(cls, value: str) -> "Event":
        return cls(EventType.TRANSITION_TO, value)

    @classmethod
    def from_dict(cls, data: dict) -> "Event":
        """Parse an event from a dictionary representation.

        Args:
            data: Dictionary with 'type' and optionally 'value' keys.

        Returns:
            Parsed Event object.
        """
        event_type = EventType(data["type"])
        value = data.get("value")
        return cls(event_type, value)


def is_x(value: str) -> bool:
    """Check if a value contains X (unknown)."""
    return "x" in value.lower()


def is_z(value: str) -> bool:
    """Check if a value contains Z (high-impedance)."""
    return "z" in value.lower()


def check_event(prev_value: str, curr_value: str, event: Event) -> bool:
    """Check if a transition from prev_value to curr_value matches the event.

    Args:
        prev_value: Previous signal value.
        curr_value: Current signal value.
        event: The event to check for.

    Returns:
        True if the transition matches the event.
    """
    if prev_value == curr_value:
        return False

    match event.event_type:
        case EventType.RISE:
            # 0 -> 1 (for single bit) or low -> high for multi-bit
            prev_is_zero = prev_value in ("0", "b0", "B0") or (
                prev_value.startswith(("b", "B")) and all(c == "0" for c in prev_value[1:])
            )
            curr_is_one = curr_value in ("1", "b1", "B1") or (
                not is_x(curr_value) and not is_z(curr_value) and curr_value not in ("0", "b0", "B0")
                and not (curr_value.startswith(("b", "B")) and all(c == "0" for c in curr_value[1:]))
            )
            return prev_is_zero and curr_is_one

        case EventType.FALL:
            # 1 -> 0 (for single bit) or high -> low for multi-bit
            curr_is_zero = curr_value in ("0", "b0", "B0") or (
                curr_value.startswith(("b", "B")) and all(c == "0" for c in curr_value[1:])
            )
            prev_is_one = prev_value in ("1", "b1", "B1") or (
                not is_x(prev_value) and not is_z(prev_value) and prev_value not in ("0", "b0", "B0")
                and not (prev_value.startswith(("b", "B")) and all(c == "0" for c in prev_value[1:]))
            )
            return prev_is_one and curr_is_zero

        case EventType.BECOME_X:
            return not is_x(prev_value) and is_x(curr_value)

        case EventType.BECOME_Z:
            return not is_z(prev_value) and is_z(curr_value)

        case EventType.UNBECOME_X:
            return is_x(prev_value) and not is_x(curr_value)

        case EventType.UNBECOME_Z:
            return is_z(prev_value) and not is_z(curr_value)

        case EventType.TRANSITION_TO:
            return curr_value == event.value or curr_value.lower() == event.value.lower()

    return False
