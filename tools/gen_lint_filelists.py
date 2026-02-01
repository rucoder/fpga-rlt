#!/usr/bin/env python3
"""
Generate lint filelists and optionally generate/update waiver files.

This script scans rtl/, sim/, and formal/ directories to discover tops,
then generates filelist (.f) files for each top module.

Usage:
    # Generate filelists only:
    python tools/gen_lint_filelists.py

    # Generate filelists and update waivers:
    python tools/gen_lint_filelists.py --update-waivers

    # Generate filelists and regenerate all waivers from scratch:
    python tools/gen_lint_filelists.py --generate-waivers
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


def rglob_sorted(root: Path, patterns: list[str]) -> list[Path]:
    out: list[Path] = []
    if not root.exists():
        return out
    for pat in patterns:
        out.extend(root.rglob(pat))
    out = [p for p in out if p.is_file()]
    return sorted(set(out), key=lambda p: p.as_posix())


def write_text(path: Path, text: str) -> None:
    _ = path.parent.mkdir(parents=True, exist_ok=True)
    _ = path.write_text(text, encoding="utf-8")


def discover_tops(sim_dir: Path, formal_dir: Path) -> list[tuple[str, Path]]:
    tops: list[tuple[str, Path]] = []
    # TB tops: sim/<mod>/tb_<mod>.sv
    for p in rglob_sorted(sim_dir, ["tb_*.sv"]):
        tops.append((p.stem, p))

    # Formal tops: formal/<mod>/<mod>_formal_top.sv (your exception)
    for p in rglob_sorted(formal_dir, ["*_formal_top.sv"]):
        tops.append((p.stem, p))

    # Deterministic order
    tops.sort(key=lambda x: (x[0], x[1].as_posix()))
    return tops


def list_same_folder_units(top_file: Path) -> list[Path]:
    # Any .sv/.v next to the top might be helper compilation units.
    # Put them as libraries (-v) to avoid creating extra MULTITOP candidates.
    folder = top_file.parent
    units = rglob_sorted(folder, ["*.sv", "*.v"])
    return [p for p in units if p.resolve() != top_file.resolve()]


def find_waiver_file(top_name: str, top_file: Path) -> Path:
    """Find the waiver file for a given top module."""
    # Waivers are stored as <module>.vlt in the same directory as the top
    # For tb_<mod>, the module name is <mod>
    # For <mod>_formal_top, the module name is <mod>
    if top_name.startswith("tb_"):
        module = top_name[3:]
    elif top_name.endswith("_formal_top"):
        module = top_name[:-11]
    else:
        module = top_name

    return top_file.parent / f"{module}.vlt"


def generate_waiver_for_top(
    top_name: str, filelist: Path, waiver_file: Path, force: bool = False
) -> bool:
    """
    Generate or update waiver file for a top module.

    Args:
        top_name: Top module name
        filelist: Path to the filelist for this top
        waiver_file: Where to write the waiver file
        force: If True, regenerate from scratch. If False, update incrementally.

    Returns:
        True if successful, False otherwise
    """
    if not force and waiver_file.exists():
        print(f"  [waiver] Updating {waiver_file!s}")
        # Run verilator with existing waiver to get NEW warnings only
        # Then append them to the existing file
        temp_waiver = waiver_file.with_suffix(".vlt.tmp")
    else:
        print(f"  [waiver] Generating {waiver_file}")
        temp_waiver = waiver_file

    cmd = [
        "verilator",
        "--lint-only",
        "-sv",
        "--timing",
        "-Wall",
        "--top-module",
        top_name,
        "-f",
        str(filelist),
        "--waiver-output",
        str(temp_waiver),
    ]

    # If we have an existing waiver and we're updating, include it
    if not force and waiver_file.exists():
        _ = cmd.insert(-2, str(waiver_file))

    try:
        _ = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )

        # Verilator always returns success when generating waivers
        if temp_waiver.exists():
            if not force and temp_waiver != waiver_file:
                # For incremental updates, we generated to .tmp
                # Verilator overwrites, so we just move it
                temp_waiver.replace(waiver_file)
            return True
        else:
            print("    ERROR: Waiver file not created", file=sys.stderr)
            return False

    except subprocess.TimeoutExpired:
        print(f"    ERROR: Verilator timeout for {top_name}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"    ERROR: {e}", file=sys.stderr)
        return False


def load_lint_config(repo: Path) -> list[str]:
    """Load exclude list from lint_config.yml"""
    config_file = repo / "lint_config.yml"
    if not config_file.exists():
        return []

    try:
        config: Any = yaml.safe_load(config_file.read_text())
        if config and "exclude" in config:
            excludes: Any = config["exclude"]
            if isinstance(excludes, list):
                return excludes
    except Exception as e:
        print(f"Warning: Failed to parse {config_file}: {e}", file=sys.stderr)

    return []


def is_excluded(top_name: str, top_path: Path, excludes: list[str]) -> bool:
    """Check if a top should be excluded based on exclude list"""
    for pattern in excludes:
        # Pattern can match top name or directory name
        if pattern in top_name:
            return True
        if pattern in str(top_path.parent.name):
            return True
    return False


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Generate lint filelists and optionally manage waiver files"
    )
    _ = ap.add_argument("--build-dir", default="build", help="Build directory")
    _ = ap.add_argument(
        "--stamp", default="build/lint/.stamp", help="Stamp file for make"
    )
    _ = ap.add_argument(
        "--depfile", default="build/lint/gen.d", help="Dependency file for make"
    )

    waiver_group = ap.add_mutually_exclusive_group()
    _ = waiver_group.add_argument(
        "--generate-waivers",
        action="store_true",
        help="Regenerate all waiver files from scratch (overwrites existing)",
    )
    _ = waiver_group.add_argument(
        "--update-waivers",
        action="store_true",
        help="Update waiver files incrementally (preserves existing waivers)",
    )

    args = ap.parse_args()

    repo = Path(".").resolve()
    build_dir: Path = (repo / str(args.build_dir)).resolve()
    lint_dir: Path = build_dir / "lint"

    rtl_dir = repo / "rtl"
    sim_dir = repo / "sim"
    formal_dir = repo / "formal"

    # Load exclude list
    excludes: list[str] = load_lint_config(repo)

    # Discover HDL inputs (coarse)
    rtl_units = rglob_sorted(rtl_dir, ["*.sv", "*.v"])
    sim_units = rglob_sorted(sim_dir, ["*.sv", "*.v", "*.svh", "*.vh"])
    formal_units = rglob_sorted(formal_dir, ["*.sv", "*.v", "*.svh", "*.vh"])

    all_tops = discover_tops(sim_dir, formal_dir)

    # Filter out excluded tops
    tops = []
    excluded_count = 0
    for top_name, top_path in all_tops:
        if is_excluded(top_name, top_path, excludes):
            print(f"[exclude] {top_name}", file=sys.stderr)
            excluded_count += 1
        else:
            tops.append((top_name, top_path))

    if excluded_count > 0:
        print(f"[exclude] Excluded {excluded_count} tops", file=sys.stderr)

    # Outputs
    rtl_lib_f: Path = build_dir / "rtl_lib.f"
    tops_txt: Path = lint_dir / "tops.txt"
    stamp: Path = Path(str(args.stamp))
    depfile: Path = Path(str(args.depfile))

    # 1) rtl_lib.f: include dirs + RTL as libraries
    incdirs: list[Path] = [rtl_dir, sim_dir, formal_dir]
    lines: list[str] = []
    for d in incdirs:
        lines.append(f"+incdir+{d.as_posix()}")
    lines.append("")
    for f in rtl_units:
        lines.append(f"-v {f.as_posix()}")
    write_text(rtl_lib_f, "\n".join(lines) + "\n")

    # 2) tops.txt
    write_text(tops_txt, "\n".join([name for name, _ in tops]) + ("\n" if tops else ""))

    # 3) per-top lint_<top>.f
    flist_files: list[Path] = []
    all_top_related_inputs: list[Path] = []
    for top_name, top_file in tops:
        deps = list_same_folder_units(top_file)
        all_top_related_inputs += deps
        lint_f: Path = lint_dir / f"lint_{top_name}.f"
        flist_files.append(lint_f)

        flines: list[str] = []
        flines.append(f"-f {rtl_lib_f.as_posix()}")
        flines.append("")

        # NOTE: Waiver file is NOT included in filelist!
        # It must be specified on the command line separately to avoid conflicts
        # when generating waivers with --waiver-output

        for dep in deps:
            flines.append(f"-v {dep.as_posix()}")
        if deps:
            flines.append("")
        # top must be INPUT (not -v), otherwise "No Input Verilog file specified"
        flines.append(top_file.as_posix())

        write_text(lint_f, "\n".join(flines) + "\n")

    # 4) stamp + depfile (this is the "first-class" part)
    # Make will rebuild stamp if any listed dependency changes.
    inputs: list[Path] = []
    inputs += rtl_units
    inputs += sim_units
    inputs += formal_units
    inputs += [p for _, p in tops]
    inputs += all_top_related_inputs

    # Depfile format: <target>: <deps...>
    # Also add generator itself as a dep so changing it regenerates.
    inputs.append(Path(__file__).resolve())

    dep_line = (
        f"{stamp.as_posix()}: "
        + " ".join(
            [p.as_posix() for p in sorted(set(inputs), key=lambda p: p.as_posix())]
        )
        + "\n"
    )
    write_text(depfile, dep_line)

    # Touch stamp
    write_text(stamp, "ok\n")

    # Optional: print a short summary (nice in CI)
    print(f"[gen] {rtl_lib_f}")
    print(f"[gen] {tops_txt} ({len(tops)} tops, {excluded_count} excluded)")
    print(f"[gen] {len(flist_files)} lint filelists in {lint_dir}")
    print(f"[gen] depfile: {depfile}")

    # Generate/update waivers if requested
    generate_waivers = bool(getattr(args, "generate_waivers", False))
    update_waivers = bool(getattr(args, "update_waivers", False))

    if generate_waivers or update_waivers:
        print()
        mode = "Regenerating" if generate_waivers else "Updating"
        print(f"[waiver] {mode} waiver files...")

        success_count = 0
        fail_count = 0

        for top_name, top_file in tops:
            waiver_file: Path = find_waiver_file(str(top_name), top_file)
            filelist: Path = lint_dir / f"lint_{top_name}.f"

            if generate_waiver_for_top(
                str(top_name),
                filelist,
                waiver_file,
                force=generate_waivers,
            ):
                success_count += 1
            else:
                fail_count += 1

        print()
        print(f"[waiver] Generated/updated {success_count} waiver files")
        if fail_count > 0:
            print(f"[waiver] Failed: {fail_count}", file=sys.stderr)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
