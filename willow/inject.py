"""Insert text at the cursor of the frontmost app: clipboard + synthetic Cmd+V.

The previous clipboard contents are restored afterwards (plain text only).
"""
import subprocess
import time


def _pbpaste() -> str | None:
    try:
        result = subprocess.run(["pbpaste"], capture_output=True, timeout=5)
        return result.stdout.decode("utf-8", "replace")
    except Exception:
        return None


def _pbcopy(text: str):
    subprocess.run(["pbcopy"], input=text.encode(), timeout=5, check=True)


def insert_text(text: str, restore_clipboard: bool = True):
    previous = _pbpaste() if restore_clipboard else None
    _pbcopy(text)
    subprocess.run([
        "osascript", "-e",
        'tell application "System Events" to keystroke "v" using command down',
    ], capture_output=True, timeout=10)
    if previous is not None:
        # Give the paste a moment to land before swapping the clipboard back.
        time.sleep(0.4)
        _pbcopy(previous)
