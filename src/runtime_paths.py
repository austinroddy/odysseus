"""Helpers for resolving runtime paths in source and frozen builds."""

import os
import sys


def get_app_root() -> str:
    """Return the app root directory.

    In normal source runs, this is the repository root. In a frozen Windows
    build, it is the bundle content root (PyInstaller's internal directory)
    so bundled runtime folders like `static/`, `scripts/`, and `data/` stay
    together with the executable payload.
    """
    if getattr(sys, "frozen", False):
        return getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(sys.executable)))
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_default_data_dir() -> str:
    """Return the default path to the data directory.

    In normal runs, this is a 'data' subdirectory under the app root.
    In frozen builds, it is a persistent user directory (~/.odysseus/data)
    to prevent SQLite databases and other persistent files from being
    written to the ephemeral, temporary extraction bundle directory.
    """
    if getattr(sys, "frozen", False):
        return os.path.join(os.path.expanduser("~"), ".odysseus", "data")
    return os.path.join(get_app_root(), "data")


def get_script_subprocess_args(script_path: str) -> tuple[str, list[str]]:
    """Return (command, args) to run `script_path` as a Python subprocess.

    In normal source runs, this just execs the current interpreter against the
    script, same as always. In a frozen build there is no separate Python
    interpreter to exec — sys.executable is the frozen app binary itself, so
    naively re-running it would just relaunch the whole app instead of the
    intended script. Frozen builds instead support a hidden `--run-script
    <path>` mode (see macos/backend/mac_entrypoint.py) that re-launches the
    same binary and runs the given script in-process via runpy instead of
    starting the server. This keeps subprocess-based script launches (built-in
    MCP servers, etc.) working under a freeze with zero extra bundled runtime,
    since it's the same interpreter and already has every package the main
    app has.
    """
    if getattr(sys, "frozen", False):
        return sys.executable, ["--run-script", script_path]
    return sys.executable, [script_path]