# -*- mode: python ; coding: utf-8 -*-
#
# PyInstaller spec for the macOS native app's embedded backend.
#
# This is deliberately separate from the repo-root Odysseus.spec, which is
# the Windows portable build (launcher.py entrypoint, tkinter splash, pystray
# tray icon, .ico icon) — none of that applies here, and editing it in place
# would risk regressing the Windows build. This spec instead points at
# mac_entrypoint.py, a small entrypoint with no Windows-only dependencies.
#
# Build from anywhere, e.g.:
#   pyinstaller macos/backend/Odysseus-macos.spec
# (paths below are resolved via SPECPATH, PyInstaller's built-in "directory
# containing this spec file" variable, so invocation cwd doesn't matter.)

import os

ROOT = os.path.abspath(os.path.join(SPECPATH, "..", ".."))


def root(*parts):
    return os.path.join(ROOT, *parts)


a = Analysis(
    [os.path.join(SPECPATH, "mac_entrypoint.py")],
    pathex=[ROOT],
    binaries=[],
    datas=[
        (root("static"), "static"),
        (root("scripts"), "scripts"),
        (root("mcp_servers"), "mcp_servers"),
        (root("services", "hwfit", "data"), "services/hwfit/data"),
        (root("config"), "config"),
        (root(".env.example"), ".env.example"),
    ],
    # services.youtube.youtube_handler and src.agent_tools are only reached
    # via string-based importlib/__import__ calls elsewhere in the codebase,
    # so PyInstaller's static import graph walk won't find them on its own.
    hiddenimports=["services.youtube.youtube_handler", "src.agent_tools"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="Odysseus",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    # UPX compression of large compiled deps (onnxruntime via fastembed,
    # cryptography, etc.) is one of the slowest parts of a PyInstaller
    # freeze — often several minutes by itself — for a modest bundle-size
    # win on a onedir build. Off by default; flip to True for a release
    # build where a smaller download size is worth the extra build time.
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    # No icon here — this binary lives hidden inside Contents/Resources and
    # is never Finder-visible; the .app bundle built around it in
    # macos/scripts/build.sh carries the real .icns.
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="Odysseus",
)
