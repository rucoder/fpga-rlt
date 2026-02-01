#!/usr/bin/env python3
"""
Verilator waiver file management tool.

Strategy (SIMPLIFIED - Verilator does the filtering for us!):
1. Pass existing waiver file (if it exists) to Verilator
2. Use --waiver-output to get ONLY NEW warnings (Verilator filters out active waivers)
3. Append new waivers to existing file

Key insight: When you pass an active waiver file to Verilator with --waiver-output,
Verilator only outputs waivers for warnings that are NOT already waived!

Usage:
    ./tools/manage_waivers.py generate [--module <name>]
    ./tools/manage_waivers.py list
    ./tools/manage_waivers.py clean [--dry-run]
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path
from typing import cast

import yaml


def rglob_sorted(root: Path, patterns: list[str]) -> list[Path]:
    """Find files matching patterns, sorted."""
    out: list[Path] = []
    if not root.exists():
        return out
    for pat in patterns:
        out.extend(root.rglob(pat))
    out = [p for p in out if p.is_file()]
    return sorted(set(out), key=lambda p: p.as_posix())


def discover_tops(sim_dir: Path, formal_dir: Path) -> list[tuple[str, Path]]:
    """Discover all top modules from sim and formal directories."""
    tops: list[tuple[str, Path]] = []

    # TB tops: sim/<mod>/tb_<mod>.sv
    for p in rglob_sorted(sim_dir, ["tb_*.sv"]):
        tops.append((p.stem, p))

    # Formal tops: formal/<mod>/<mod>_formal_top.sv
    for p in rglob_sorted(formal_dir, ["*_formal_top.sv"]):
        tops.append((p.stem, p))

    tops.sort(key=lambda x: (x[0], x[1].as_posix()))
    return tops


def get_module_name(top_name: str) -> str:
    """Extract module name from top name."""
    if top_name.startswith("tb_"):
        return top_name[3:]
    elif top_name.endswith("_formal_top"):
        return top_name[:-11]
    else:
        return top_name


def get_waiver_path(top_file: Path) -> Path:
    """Get the waiver file path for a top module."""
    top_name = top_file.stem
    module = get_module_name(top_name)
    return top_file.parent / f"{module}.vlt"


def load_exclude_config(repo: Path) -> list[str]:
    """Load exclude list from lint_config.yml"""
    config_file = repo / "lint_config.yml"
    if not config_file.exists():
        return []

    try:
        config = yaml.safe_load(config_file.read_text())
        if not isinstance(config, dict):
            return []
        if "exclude" not in config:
            return []
        excludes = config["exclude"]
        if isinstance(excludes, list):
            # Validate all items are strings
            return [str(item) for item in excludes if isinstance(item, str)]
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


def generate_waiver(top_name: str, filelist: Path, waiver_file: Path) -> bool:
    """
    Generate waiver file for a top module.

    Simple strategy:
    1. Pass existing waiver file (if exists) to Verilator
    2. Verilator with --waiver-output will ONLY output NEW warnings (it filters out active waivers!)
    3. Append new commented waivers to existing file

    Note: Waivers are generated as COMMENTED by default (user must uncomment to activate)
    """
    if not filelist.exists():
        print(f"  ERROR: Filelist not found: {filelist}", file=sys.stderr)
        return False

    # Read existing waiver content if it exists
    existing_content = ""
    is_new_file = not waiver_file.exists()

    if not is_new_file:
        existing_content = waiver_file.read_text()

    # Generate new waivers with verilator
    temp_waiver = waiver_file.with_suffix(".vlt.tmp")

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

    # IMPORTANT: Pass existing waiver file so Verilator filters out already-waived warnings
    if not is_new_file:
        cmd.append(str(waiver_file))

    print(f"  Generating waivers for {top_name}...")

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )

        if not temp_waiver.exists():
            print("  ERROR: Verilator did not create waiver file", file=sys.stderr)
            if result.stdout:
                print(f"  Output: {result.stdout}", file=sys.stderr)
            return False

        # Read new waiver content from Verilator
        new_content = temp_waiver.read_text()

        # Check if there are any new waivers (Verilator outputs "No waivers needed" if none)
        has_new_waivers = "lint_off" in new_content or "lint_on" in new_content

        if is_new_file:
            # New file - just use what Verilator generated
            waiver_file.write_text(new_content)
            print(f"  ✓ {waiver_file!s} (new)")
        elif has_new_waivers:
            # Append new waivers to existing file
            # Remove the header and empty lines from new content
            new_lines = new_content.splitlines()
            waiver_lines: list[str] = []
            for line in new_lines:
                stripped = line.strip()
                if stripped.startswith("// lint_off") or stripped.startswith(
                    "// lint_on"
                ):
                    waiver_lines.append(line)

            if waiver_lines:
                # Check for duplicates - don't add waivers that already exist
                existing_lines = existing_content.splitlines()
                unique_waivers: list[str] = []
                for new_waiver in waiver_lines:
                    # Check if this waiver already exists (as commented or uncommented)
                    stripped = new_waiver.strip()
                    # Remove "// " prefix if present to compare the actual waiver text
                    if stripped.startswith("// "):
                        waiver_text = stripped[3:]
                    else:
                        waiver_text = stripped

                    # Check if waiver already exists in any form
                    already_exists = False
                    for existing_line in existing_lines:
                        existing_stripped = existing_line.strip()
                        # Remove "// " prefix if present
                        if existing_stripped.startswith("// "):
                            existing_waiver = existing_stripped[3:]
                        else:
                            existing_waiver = existing_stripped

                        if waiver_text == existing_waiver:
                            already_exists = True
                            break

                    if not already_exists:
                        unique_waivers.append(str(new_waiver))

                if unique_waivers:
                    # Append unique waivers to existing file
                    with waiver_file.open("a") as f:
                        _ = f.write("\n")
                        _ = f.write("\n".join(unique_waivers))
                        _ = f.write("\n")
                    print(
                        f"  ✓ {waiver_file} (added {len(unique_waivers)} new waiver(s))"
                    )
                    if len(unique_waivers) < len(waiver_lines):
                        skipped = len(waiver_lines) - len(unique_waivers)
                        print(f"    (skipped {skipped:d} duplicate(s))")
                else:
                    print(f"  ✓ {waiver_file} (no changes - all waivers already exist)")
            else:
                print(f"  ✓ {waiver_file} (no changes)")
        else:
            # No new waivers needed
            print(f"  ✓ {waiver_file!s} (no new waivers)")

        temp_waiver.unlink()
        return True

    except subprocess.TimeoutExpired:
        print("  ERROR: Verilator timeout", file=sys.stderr)
        if temp_waiver.exists():
            temp_waiver.unlink()
        return False
    except Exception as e:
        print(f"  ERROR: {e}", file=sys.stderr)
        if temp_waiver.exists():
            temp_waiver.unlink()
        return False


def list_waivers(repo: Path) -> int:
    """List all existing waiver files."""
    sim_waivers = rglob_sorted(repo / "sim", ["*.vlt"])
    formal_waivers = rglob_sorted(repo / "formal", ["*.vlt"])

    print("Waiver files:")
    print("\nTestbench waivers:")
    for w in sim_waivers:
        rel = w.relative_to(repo)
        print(f"  {rel}")

    print("\nFormal waivers:")
    for w in formal_waivers:
        rel = w.relative_to(repo)
        print(f"  {rel}")

    total = len(sim_waivers) + len(formal_waivers)
    print(f"\nTotal: {total} waiver files")
    return 0


def clean_waivers(repo: Path, dry_run: bool = False) -> int:
    """Remove all waiver files."""
    sim_waivers = rglob_sorted(repo / "sim", ["*.vlt"])
    formal_waivers = rglob_sorted(repo / "formal", ["*.vlt"])
    all_waivers = sim_waivers + formal_waivers

    if not all_waivers:
        print("No waiver files found.")
        return 0

    print(
        f"{'Would remove' if dry_run else 'Removing'} {len(all_waivers)} waiver files..."
    )
    for w in all_waivers:
        rel = w.relative_to(repo)
        print(f"  {rel}")
        if not dry_run:
            w.unlink()

    if dry_run:
        print("\n(Dry run - no files deleted)")
    else:
        print(f"\n✓ Removed {len(all_waivers)} waiver files")

    return 0


def generate_all_waivers(repo: Path, module_filter: str | None = None) -> int:
    """Generate waiver files for all tops."""
    sim_dir = repo / "sim"
    formal_dir = repo / "formal"
    lint_dir = repo / "build" / "lint"

    if not lint_dir.exists():
        print("ERROR: build/lint directory not found.", file=sys.stderr)
        print(
            "Run './tools/gen_lint_filelists.py' first to generate filelists.",
            file=sys.stderr,
        )
        return 1

    # Load exclude list
    excludes = load_exclude_config(repo)

    # Discover tops
    all_tops = discover_tops(sim_dir, formal_dir)

    # Filter out excluded tops
    tops = []
    for top_name, top_path in all_tops:
        if is_excluded(top_name, top_path, excludes):
            continue
        tops.append((top_name, top_path))

    if not tops:
        print("No top modules found.")
        return 0

    # Filter by module if requested
    if module_filter:
        tops = [
            (name, path)
            for name, path in tops
            if module_filter in str(name) or module_filter in get_module_name(str(name))
        ]
        if not tops:
            print(f"No tops matching {module_filter!r} found.")
            return 0

    print(f"Generating waivers for {len(tops):d} modules...")
    print()

    success = 0
    failed = 0

    for top_name, top_file in tops:
        filelist = lint_dir / f"lint_{top_name}.f"
        waiver_file = get_waiver_path(top_file)

        if generate_waiver(str(top_name), filelist, waiver_file):
            success += 1
        else:
            failed += 1

    print()
    print(f"✓ Generated {success:d} waiver files")
    if failed > 0:
        print(f"✗ Failed: {failed:d}", file=sys.stderr)
        return 1

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Manage Verilator waiver files")

    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # Generate command
    gen_parser = subparsers.add_parser("generate", help="Generate waiver files")
    _ = gen_parser.add_argument("--module", help="Only generate for specific module")

    # List command
    _ = subparsers.add_parser("list", help="List all waiver files")

    # Clean command
    clean_parser = subparsers.add_parser("clean", help="Remove all waiver files")
    _ = clean_parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be deleted"
    )

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return 1

    repo = Path.cwd()

    if args.command == "list":
        return list_waivers(repo)

    elif args.command == "clean":
        dry_run = bool(getattr(args, "dry_run", False))
        return clean_waivers(repo, dry_run=dry_run)

    elif args.command == "generate":
        module_filter = cast(str | None, getattr(args, "module", None))
        return generate_all_waivers(repo, module_filter=module_filter)

    return 0


if __name__ == "__main__":
    sys.exit(main())
