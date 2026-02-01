#!/usr/bin/env python3
"""
Lint all tops from the command line (for Makefile).

This script reads the pre-generated tops list and lint_config.yml,
then runs verilator for each top, respecting configuration and waivers.

Unlike verilator_multi.py (which is for LSP/Zed), this script:
- Runs from the Makefile
- Shows full verilator output
- Respects lint_config.yml settings
- Exits with error code if any top fails
"""

import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, cast

import yaml


def read_tops(tops_file: Path) -> list[str]:
    """Read list of top modules from pre-generated file."""
    if not tops_file.exists():
        return []
    return [line.strip() for line in tops_file.read_text().splitlines() if line.strip()]


def read_lint_config(config_file: Path) -> dict[str, Any]:
    """Read lint configuration from lint_config.yml."""
    if not config_file.exists():
        return {}

    try:
        with config_file.open() as f:
            config = yaml.safe_load(f)
            if not isinstance(config, dict):
                return {}
            return cast(dict[str, Any], config)
    except Exception as e:
        print(f"Warning: Failed to read {config_file}: {e}", file=sys.stderr)
        return {}


def get_verilator_args(config: dict[str, Any]) -> list[str]:
    """Extract verilator arguments from config."""
    args: list[str] = []

    # Get lint_only settings
    lint_only = config.get("lint_only", {})
    if not isinstance(lint_only, dict):
        lint_only = {}

    # Always lint-only mode
    args.append("--lint-only")

    # Language
    sv = lint_only.get("sv", True)
    if isinstance(sv, bool) and sv:
        args.append("-sv")

    # Timing
    timing = lint_only.get("timing", True)
    if isinstance(timing, bool) and timing:
        args.append("--timing")

    # Warning level
    wall = lint_only.get("Wall", True)
    if isinstance(wall, bool) and wall:
        args.append("-Wall")

    # Additional flags
    extra_flags = lint_only.get("extra_flags", [])
    if isinstance(extra_flags, list):
        for flag in extra_flags:
            if isinstance(flag, str):
                args.append(flag)

    return args


def find_waiver_file(top: str, repo_root: Path) -> Path:
    """Find waiver file for a top module."""
    if top.startswith("tb_"):
        module = top[3:]
        return repo_root / "sim" / module / f"{module}.vlt"
    elif top.endswith("_formal_top"):
        module = top[:-11]
        return repo_root / "formal" / module / f"{module}.vlt"
    else:
        return Path("/dev/null")  # Doesn't exist


def run_verilator_for_top(
    top: str, filelist: Path, waiver_file: Path, base_args: list[str]
) -> int:
    """Run verilator for a single top, return exit code."""
    cmd = ["verilator", "--top-module", top]
    cmd.extend(base_args)
    cmd.extend(["-f", str(filelist)])

    # Add waiver file if it exists (must be on command line, not in filelist!)
    if waiver_file.exists():
        cmd.append(str(waiver_file))

    # Show command being run
    cmd_line = " ".join(shlex.quote(str(arg)) for arg in cmd)
    print(f"  Command: {cmd_line}", file=sys.stderr)

    # Run verilator, let output flow directly
    result = subprocess.run(cmd)
    return result.returncode


def main() -> int:
    repo_root = Path.cwd()
    lint_dir = repo_root / "build" / "lint"
    tops_file = lint_dir / "tops.txt"
    config_file = repo_root / "lint_config.yml"

    # Read configuration
    config = read_lint_config(config_file)
    base_args = get_verilator_args(config)

    print(f"Lint configuration: {' '.join(base_args)}", file=sys.stderr)
    print("", file=sys.stderr)

    # Check if tops file exists
    if not tops_file.exists():
        print(f"ERROR: {tops_file} not found.", file=sys.stderr)
        print("Run 'make lint-lists' first to generate filelists.", file=sys.stderr)
        return 1

    # Read tops
    tops = read_tops(tops_file)
    if not tops:
        print("ERROR: No tops found in tops.txt", file=sys.stderr)
        return 1

    print(f"Linting {len(tops)} tops: {', '.join(tops)}", file=sys.stderr)
    print("", file=sys.stderr)

    # Lint each top
    failed_tops = []
    for top in tops:
        print(f"=== Linting {top} ===", file=sys.stderr)

        filelist = lint_dir / f"lint_{top}.f"
        if not filelist.exists():
            print(f"  Skipping: {filelist} not found", file=sys.stderr)
            print("", file=sys.stderr)
            continue

        waiver_file = find_waiver_file(top, repo_root)
        if waiver_file.exists():
            print(f"  Waiver file: {waiver_file}", file=sys.stderr)

        rc = run_verilator_for_top(top, filelist, waiver_file, base_args)

        if rc != 0:
            failed_tops.append(top)
            print(f"  FAILED (exit code {rc})", file=sys.stderr)
        else:
            print("  PASSED", file=sys.stderr)

        print("", file=sys.stderr)

    # Summary
    print("=" * 70, file=sys.stderr)
    if failed_tops:
        print(f"FAILED: {len(failed_tops):d} top(s) had errors:", file=sys.stderr)
        for top in failed_tops:
            print(f"  - {top}", file=sys.stderr)
        return 1
    else:
        print(f"SUCCESS: All {len(tops)} tops passed lint", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
