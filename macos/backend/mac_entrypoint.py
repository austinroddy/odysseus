# mac_entrypoint.py — PyInstaller entrypoint for the macOS native app build.
#
# Normally starts the FastAPI/uvicorn server, same as app.py's own
# `__main__` block (APP_BIND / APP_PORT env vars, default 127.0.0.1:7000).
#
# Also supports a hidden `--run-script <path>` mode: instead of starting the
# server, it runs the given script in-process via `runpy`. This lets the
# frozen binary re-launch itself as a subprocess to run scripts that would
# otherwise need a separate Python interpreter — under a freeze,
# sys.executable is this binary itself, not a bare interpreter, so
# `sys.executable <script>` can't work the way it does in normal source
# runs. The built-in MCP servers (memory/RAG/image-gen/email, spawned by
# src/builtin_mcp.py) rely on this. See
# src/runtime_paths.py:get_script_subprocess_args for the caller side.
import os
import sys


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "--run-script":
        import runpy

        runpy.run_path(sys.argv[2], run_name="__main__")
        return

    import uvicorn

    from app import app

    bind_host = os.getenv("APP_BIND", "127.0.0.1")
    bind_port = int(os.getenv("APP_PORT", "7000"))
    uvicorn.run(app, host=bind_host, port=bind_port, log_level="info")


if __name__ == "__main__":
    main()
