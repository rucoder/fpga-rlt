#!/usr/bin/env python3
"""
Verilator multi-pass wrapper for Veridian LSP.

This script is called by veridian.yml instead of verilator directly.
It reads a pre-generated list of tops and filelists (created by gen_lint_filelists.py)
and runs verilator for each top, aggregating the output.

DO NOT scan for files here - this runs in the LSP hot path!
"""

import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def setup_logging(log_dir: Path) -> Path:
    """Setup log file."""
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "verilator_multi.log"
    return log_file


def log_write(log_file: Path, msg: str) -> None:
    """Write message to log file with timestamp."""
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        with log_file.open("a") as f:
            _ = f.write(f"[{timestamp}] {msg}\n")
    except Exception:
        pass  # Don't fail if logging fails


def read_tops(tops_file: Path) -> list[str]:
    """Read list of top modules from pre-generated file."""
    if not tops_file.exists():
        return []
    return [line.strip() for line in tops_file.read_text().splitlines() if line.strip()]


def find_tops_for_file(
    target_file: Path, lint_dir: Path, all_tops: list[str], log_file: Path
) -> list[str]:
    """Find which top(s) contain the target file by checking their filelists."""
    matching_tops = []
    target_abs = target_file.resolve()

    log_write(log_file, f"Searching for tops that include: {target_abs}")

    for top in all_tops:
        filelist = lint_dir / f"lint_{top}.f"
        if not filelist.exists():
            continue

        # Read the filelist and expand any -f references
        files_in_top = set()
        lines_to_process = [filelist]

        while lines_to_process:
            current_file = lines_to_process.pop()
            if not current_file.exists():
                continue

            for line in current_file.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("//") or line.startswith("#"):
                    continue

                # Handle -f include
                if line.startswith("-f "):
                    included = Path(line[3:].strip())
                    lines_to_process.append(included)
                # Handle -v library file or regular file
                elif line.startswith("-v "):
                    files_in_top.add(Path(line[3:].strip()).resolve())
                elif line.endswith(".sv") or line.endswith(".v"):
                    files_in_top.add(Path(line).resolve())

        if target_abs in files_in_top:
            matching_tops.append(top)
            log_write(log_file, f"  -> Found in top: {top}")

    if not matching_tops:
        log_write(log_file, "  -> File not found in any top, will lint all tops")

    return matching_tops


def run_verilator(
    top: str, filelist: Path, waiver_file: Path, base_args: list[str], log_file: Path
) -> tuple[int, str]:
    """Run verilator for a single top module."""
    cmd = ["verilator", "--top-module", top]
    cmd.extend(base_args)

    if filelist.exists():
        cmd.extend(["-f", str(filelist)])

    # Add waiver file if it exists (must be on command line, not in filelist!)
    if waiver_file.exists():
        cmd.append(str(waiver_file))

    # Log full command line
    cmd_line = " ".join(shlex.quote(str(arg)) for arg in cmd)
    log_write(log_file, f"FULL COMMAND: {cmd_line}")

    result = subprocess.run(cmd, text=True)
    log_write(log_file, f"Verilator exit code: {result.returncode}")
    return result.returncode, ""


def main() -> int:
    # Read pre-generated tops list
    repo_root = Path.cwd()
    tops_file = repo_root / "build" / "lint" / "tops.txt"
    lint_dir = repo_root / "build" / "lint"

    # Setup logging
    log_dir = lint_dir / "logs"
    log_file = setup_logging(log_dir)

    log_write(log_file, "=== verilator_multi.py invoked ===")
    log_write(log_file, f"CWD: {repo_root}")
    log_write(log_file, f"RAW Args from Veridian: {sys.argv[1:]}")

    # Veridian passes verilator args from veridian.yml
    # Filter out .sv/.v files - those come from the filelist only!
    filtered_files = [
        arg for arg in sys.argv[1:] if (arg.endswith(".sv") or arg.endswith(".v"))
    ]
    base_args = [
        arg for arg in sys.argv[1:] if not (arg.endswith(".sv") or arg.endswith(".v"))
    ]

    if filtered_files:
        log_write(
            log_file, f"FILTERED OUT these files from command line: {filtered_files}"
        )
    log_write(log_file, f"Final Args (after filtering): {base_args}")
    log_write(log_file, f"Log file: {log_file}")
    log_write(log_file, "")

    if not tops_file.exists():
        msg = f"WARNING: {tops_file} not found. Run 'make lint-lists' to generate filelists."
        log_write(log_file, msg)
        return 0  # Don't fail LSP if lists aren't generated yet

    all_tops = read_tops(tops_file)
    log_write(log_file, f"Found {len(all_tops)} tops: {all_tops}")
    log_write(log_file, "")

    if not all_tops:
        msg = "No tops found in tops.txt"
        log_write(log_file, msg)
        return 0

    # If a specific file was passed, find which top(s) it belongs to
    tops_to_lint = all_tops
    if filtered_files:
        target_file = Path(filtered_files[0])  # Use first file if multiple
        matching_tops = find_tops_for_file(target_file, lint_dir, all_tops, log_file)

        # If file is in rtl/ directory, it's a library module - lint it standalone
        if target_file.is_relative_to(repo_root / "rtl"):
            log_write(
                log_file, "RTL file detected - linting as standalone library module"
            )
            log_write(log_file, "")
            rtl_lib_f = repo_root / "build" / "rtl_lib.f"
            cmd = ["verilator"]
            cmd.extend(base_args)
            cmd.extend(["-f", str(rtl_lib_f)])
            cmd.append(str(target_file))  # Add target file as input
            cmd_line = " ".join(shlex.quote(str(arg)) for arg in cmd)
            log_write(log_file, f"FULL COMMAND: {cmd_line}")
            result = subprocess.run(cmd, text=True)
            log_write(log_file, f"Exit code: {result.returncode}")
            return 0

        if matching_tops:
            tops_to_lint = matching_tops
            log_write(log_file, f"Will lint only these tops: {tops_to_lint}")
        log_write(log_file, "")

    any_fail = False

    for top in tops_to_lint:
        filelist = lint_dir / f"lint_{top}.f"

        if not filelist.exists():
            msg = f"Skipping {top}: {filelist} not found"
            log_write(log_file, msg)
            continue

        # Find waiver file for this top
        if top.startswith("tb_"):
            module = top[3:]
            waiver_file = repo_root / "sim" / module / f"{module}.vlt"
        elif top.endswith("_formal_top"):
            module = top[:-11]
            waiver_file = repo_root / "formal" / module / f"{module}.vlt"
        else:
            waiver_file = Path("/dev/null")  # Doesn't exist

        log_write(log_file, f"--- Linting {top} ---")
        log_write(log_file, f"Filelist: {filelist}")
        if waiver_file.exists():
            log_write(log_file, f"Waiver: {waiver_file}")

        rc, _ = run_verilator(top, filelist, waiver_file, base_args, log_file)

        if rc != 0:
            any_fail = True

    log_write(
        log_file,
        f"=== Completed with {len(tops_to_lint)} tops, {'warnings/errors found' if any_fail else 'all clean'} ===",
    )

    # Always return 0 for LSP - diagnostics are in stdout
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
