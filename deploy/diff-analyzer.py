#!/usr/bin/env python3
"""
diff-analyzer.py — Analyze compatibility risk when upgrading Dify upstream.

Detects the current upstream base version automatically from git history,
then compares your custom patches against upstream changes between the
base and a target version.

Output: structured risk report (high/medium/low) showing which of your
custom patches may conflict with upstream changes.

Usage:
    ./diff-analyzer.py --target v1.15.0       # auto-detect base, check v1.15.0
    ./diff-analyzer.py --target v1.15.0 --json  # machine-readable output
    ./diff-analyzer.py --target main --repo /path/to/dify

Strategy for base version detection:
    1. Look for merge commits with messages matching "update to dify vX.Y.Z"
    2. Fallback: find the merge-base with langgenius/main, then nearest tag
    3. Fallback: ask user to specify --base explicitly
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Optional


# ── Data structures ────────────────────────────────────────────

@dataclass
class FileChange:
    path: str
    additions: int = 0
    deletions: int = 0

@dataclass
class RiskItem:
    """A custom patch file that overlaps with upstream changes."""
    path: str
    risk: str  # high / medium / low
    patch_commits: list[str] = field(default_factory=list)
    upstream_commits: list[str] = field(default_factory=list)
    patch_additions: int = 0
    patch_deletions: int = 0
    upstream_additions: int = 0
    upstream_deletions: int = 0

@dataclass
class Report:
    base_version: str
    target_version: str
    base_commit: str
    target_commit: str
    custom_commits_count: int
    high_risk: list[RiskItem] = field(default_factory=list)
    medium_risk: list[RiskItem] = field(default_factory=list)
    low_risk: list[RiskItem] = field(default_factory=list)
    only_patch_files: list[str] = field(default_factory=list)  # your files, no upstream conflict


# ── Git helpers ─────────────────────────────────────────────────

def run_git(repo: str, *args: str) -> str:
    """Run a git command and return stdout, or exit on failure."""
    cmd = ["git", "-C", repo] + list(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: git {' '.join(cmd[1:])} failed: {e.stderr.strip()}", file=sys.stderr)
        sys.exit(1)


def detect_base(repo: str) -> tuple[str, str]:
    """
    Auto-detect the upstream base version.

    Priority:
      1. Merge commit with "update to dify v<version>" in message
         → use its *upstream parent* (second parent) as the base commit,
         since that's the actual upstream tag/branch commit.
      2. git merge-base with langgenius/main, then nearest tag
      3. Exit with instructions to specify --base
    """
    # Strategy 1: search merge commit messages
    merges = run_git(repo, "log", "--oneline", "--merges", "-50", "--format=%H %P %s")
    for line in merges.splitlines():
        m = re.search(r'update to dify\s+v?([\d.]+)', line, re.IGNORECASE)
        if m:
            parts = line.split()
            if len(parts) >= 4:
                # Format: hash parent1 parent2 ... message
                # Upstream parent is typically the 2nd parent (index=2 in split)
                upstream_commit = parts[2]
            else:
                # Fallback: no parents (shouldn't happen for merge commits)
                upstream_commit = parts[0]
            return (f"v{m.group(1)}", upstream_commit)

    # Strategy 2: merge-base + nearest tag
    upstream = run_git(repo, "merge-base", "HEAD", "langgenius/main")
    if upstream:
        try:
            tag = run_git(repo, "describe", "--tags", "--abbrev=0", upstream)
            return (tag, upstream)
        except SystemExit:
            pass

    # Strategy 3: give up
    print("ERROR: Could not auto-detect base version.", file=sys.stderr)
    print("Use --base to specify manually, e.g.: --base v1.14.2", file=sys.stderr)
    sys.exit(1)


def resolve_rev(repo: str, rev: str) -> str:
    """Resolve a revision (branch, tag, ref) to a commit hash."""
    return run_git(repo, "rev-parse", rev)


def get_custom_commits(repo: str, base_commit: str) -> list[str]:
    """
    Get list of custom (non-upstream) commit hashes since base.
    Excludes merge commits.
    """
    output = run_git(repo, "log", "--oneline", "--no-merges",
                     "--format=%H", f"{base_commit}..HEAD")
    if not output:
        return []
    return output.splitlines()


def get_changed_files(repo: str, from_rev: str, to_rev: str) -> dict[str, FileChange]:
    """Get files changed between two revisions with line stats."""
    output = run_git(repo, "diff", "--numstat", f"{from_rev}..{to_rev}")
    result = {}
    if not output:
        return result
    for line in output.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        additions = int(parts[0]) if parts[0] != "-" else 0
        deletions = int(parts[1]) if parts[1] != "-" else 0
        path = parts[2]
        result[path] = FileChange(path=path, additions=additions, deletions=deletions)
    return result


def get_commits_for_file(repo: str, commit_range: str, path: str) -> list[str]:
    """Get commit SHAs that touched a specific file in a commit range."""
    output = run_git(repo, "log", "--oneline", "--format=%H|%s", commit_range, "--", path)
    if not output:
        return []
    return output.splitlines()


def classify_risk(patch: FileChange, upstream: FileChange) -> str:
    """
    Classify conflict risk: high / medium / low.

    Heuristics:
    - Both sides modified heavily (>50 lines total)     → high
    - Both sides modified moderately (10-50 lines)       → medium
    - One side has trivial changes (<10 lines)            → low
    - Both sides have trivial changes                     → low
    """
    patch_total = patch.additions + patch.deletions
    upstream_total = upstream.additions + upstream.deletions

    if patch_total > 50 and upstream_total > 50:
        return "high"
    if patch_total > 50 or upstream_total > 50:
        return "medium"
    if patch_total > 10 and upstream_total > 10:
        return "medium"
    return "low"


# ── Core logic ──────────────────────────────────────────────────

def analyze(repo: str, base_version: str, base_commit: str, target_rev: str) -> Report:
    try:
        target_commit = resolve_rev(repo, target_rev)
    except SystemExit:
        print(f"ERROR: Cannot resolve target revision '{target_rev}'", file=sys.stderr)
        sys.exit(1)

    # Fetch if needed (target may be on a remote tag)
    target_tag = None
    if target_rev.startswith("v"):
        tags = run_git(repo, "tag", "-l", target_rev)
        if not tags:
            print(f"Fetching tags from upstream to find {target_rev}...", file=sys.stderr)
            run_git(repo, "fetch", "langgenius", "--tags")
        # Resolve again after fetch
        target_commit = resolve_rev(repo, target_rev)

    custom_commits = get_custom_commits(repo, base_commit)
    if not custom_commits:
        print("WARNING: No custom commits found since base version.", file=sys.stderr)
        return Report(
            base_version=base_version,
            target_version=target_rev,
            base_commit=base_commit,
            target_commit=target_commit,
            custom_commits_count=0,
        )

    # Files changed by your custom patches
    patch_files = get_changed_files(repo, base_commit, "HEAD")

    # Files changed upstream between base and target
    upstream_files = get_changed_files(repo, base_commit, target_commit)

    # Find overlap
    overlap_paths = set(patch_files.keys()) & set(upstream_files.keys())
    only_patch_paths = sorted(set(patch_files.keys()) - set(upstream_files.keys()))

    report = Report(
        base_version=base_version,
        target_version=target_rev,
        base_commit=base_commit,
        target_commit=target_commit,
        custom_commits_count=len(custom_commits),
    )

    # Analyze overlapping files
    for path in sorted(overlap_paths):
        patch = patch_files[path]
        upstream = upstream_files[path]
        risk = classify_risk(patch, upstream)

        # Get the commits for context
        patch_commit_list = get_commits_for_file(
            repo, f"{base_commit}..HEAD", path
        )
        upstream_commit_list = get_commits_for_file(
            repo, f"{base_commit}..{target_commit}", path
        )

        item = RiskItem(
            path=path,
            risk=risk,
            patch_commits=[c.split("|")[0][:8] for c in patch_commit_list[:5]],
            upstream_commits=[c.split("|")[0][:8] for c in upstream_commit_list[:5]],
            patch_additions=patch.additions,
            patch_deletions=patch.deletions,
            upstream_additions=upstream.additions,
            upstream_deletions=upstream.deletions,
        )

        if risk == "high":
            report.high_risk.append(item)
        elif risk == "medium":
            report.medium_risk.append(item)
        else:
            report.low_risk.append(item)

    report.only_patch_files = sorted(only_patch_paths)

    return report


# ── Formatters ──────────────────────────────────────────────────

BOLD = "\033[1m"
RED = "\033[31m"
YELLOW = "\033[33m"
GREEN = "\033[32m"
CYAN = "\033[36m"
DIM = "\033[2m"
RESET = "\033[0m"


def format_plain(report: Report) -> str:
    """Human-readable risk report."""
    lines = []
    lines.append("")
    lines.append(f"╔══════════════════════════════════════════════════════════════╗")
    lines.append(f"║  Dify Upgrade Compatibility Analysis                           ║")
    lines.append(f"╠══════════════════════════════════════════════════════════════╣")
    lines.append(f"║  Base:    {report.base_version:<50s}  ║")
    lines.append(f"║  Target:  {report.target_version:<50s}  ║")
    lines.append(f"║  Custom commits: {report.custom_commits_count:<4d}  (since {report.base_commit[:8]})" + " " * 22 + "║")
    lines.append(f"╚══════════════════════════════════════════════════════════════╝")
    lines.append("")

    # Summary
    high_count = len(report.high_risk)
    mid_count = len(report.medium_risk)
    low_count = len(report.low_risk)
    only_count = len(report.only_patch_files)

    lines.append(f"  Risk Summary:")
    lines.append(f"    {RED}HIGH  : {high_count:3d}{RESET}  — must review carefully, high chance of conflicts")
    lines.append(f"    {YELLOW}MEDIUM: {mid_count:3d}{RESET}  — review recommended, some overlap")
    lines.append(f"    {GREEN}LOW   : {low_count:3d}{RESET}  — minor overlap, quick check")
    lines.append(f"    {DIM}ONLY  : {only_count:3d}{RESET}  — your patch files, no upstream changes")
    lines.append("")

    # High risk detail
    if report.high_risk:
        lines.append(f"{RED}▸ HIGH RISK ({high_count} files){RESET}")
        lines.append(f"  These files are heavily modified by both your patches AND upstream.")
        lines.append(f"  Review each one carefully before upgrading.")
        lines.append("")
        for item in report.high_risk:
            lines.append(f"  {RED}▶ {item.path}{RESET}")
            lines.append(f"    Patch:  +{item.patch_additions}/-{item.patch_deletions} lines  |  Upstream: +{item.upstream_additions}/-{item.upstream_deletions} lines")
            if item.patch_commits:
                lines.append(f"    Your commits: {', '.join(item.patch_commits)}")
            if item.upstream_commits:
                lines.append(f"    Upstream:     {', '.join(item.upstream_commits)}")
            lines.append("")
    else:
        lines.append(f"{GREEN}✓ No high-risk files{RESET}")
        lines.append("")

    # Medium risk
    if report.medium_risk:
        lines.append(f"{YELLOW}▸ MEDIUM RISK ({mid_count} files){RESET}")
        lines.append("")
        for item in report.medium_risk:
            lines.append(f"  {YELLOW}▶ {item.path}{RESET}")
            lines.append(f"    Patch: +{item.patch_additions}/-{item.patch_deletions}  |  Upstream: +{item.upstream_additions}/-{item.upstream_deletions}")
            lines.append("")

    # Low risk
    if report.low_risk:
        lines.append(f"{GREEN}▸ LOW RISK ({low_count} files){RESET}")
        lines.append("")
        for item in report.low_risk:
            lines.append(f"  {GREEN}▶ {item.path}{RESET}  (+{item.patch_additions}/-{item.patch_deletions} vs +{item.upstream_additions}/-{item.upstream_deletions})")
        lines.append("")

    # Only-patch files
    if report.only_patch_files:
        lines.append(f"{DIM}▸ YOUR PATCH ONLY ({only_count} files) — unchanged upstream{RESET}")
        lines.append(f"  No upstream changes in these files. Low risk, but verify")
        lines.append(f"  they don't depend on changed upstream APIs.")
        lines.append("")
        for p in report.only_patch_files[:20]:
            lines.append(f"  {DIM}• {p}{RESET}")
        if only_count > 20:
            lines.append(f"  {DIM}  ... and {only_count - 20} more{RESET}")
        lines.append("")

    # Recommendations
    lines.append(f"{BOLD}▸ Recommended workflow:{RESET}")
    lines.append(f"  1. Review each {RED}HIGH{RESET} file above; resolve conflicts first")
    lines.append(f"  2. Check {YELLOW}MEDIUM{RESET} files for subtle API/signature changes")
    lines.append(f"  3. Quick scan {GREEN}LOW{RESET} files")
    lines.append(f"  4. Rebuild: docker build → start-local.sh test → deploy.sh")
    lines.append("")

    return "\n".join(lines)


def format_json(report: Report) -> str:
    """JSON output for scripting / CI."""
    return json.dumps({
        "base_version": report.base_version,
        "target_version": report.target_version,
        "base_commit": report.base_commit,
        "target_commit": report.target_commit,
        "custom_commits_count": report.custom_commits_count,
        "summary": {
            "high": len(report.high_risk),
            "medium": len(report.medium_risk),
            "low": len(report.low_risk),
            "only_patch": len(report.only_patch_files),
        },
        "high_risk": [{
            "path": r.path,
            "patch_additions": r.patch_additions,
            "patch_deletions": r.patch_deletions,
            "upstream_additions": r.upstream_additions,
            "upstream_deletions": r.upstream_deletions,
            "your_commits": r.patch_commits,
            "upstream_commits": r.upstream_commits,
        } for r in report.high_risk],
        "medium_risk": [{
            "path": r.path,
            "patch_additions": r.patch_additions,
            "patch_deletions": r.patch_deletions,
            "upstream_additions": r.upstream_additions,
            "upstream_deletions": r.upstream_deletions,
        } for r in report.medium_risk],
        "low_risk": [{
            "path": r.path,
            "patch_additions": r.patch_additions,
            "patch_deletions": r.patch_deletions,
            "upstream_additions": r.upstream_additions,
            "upstream_deletions": r.upstream_deletions,
        } for r in report.low_risk],
        "only_patch_files": report.only_patch_files,
    }, indent=2)


# ── Main ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Analyze Dify upgrade compatibility — custom patches vs upstream changes.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --target v1.15.0
  %(prog)s --target v1.15.0 --json
  %(prog)s --target main --repo /path/to/dify --base v1.14.2
        """,
    )
    parser.add_argument("--target", required=True,
                        help="Target upstream version (tag, branch, or commit)")
    parser.add_argument("--base", default=None,
                        help="Base upstream version (auto-detected if omitted)")
    parser.add_argument("--repo", default=None,
                        help="Path to dify repository (default: auto-detect from script location)")
    parser.add_argument("--json", action="store_true",
                        help="Output machine-readable JSON")

    args = parser.parse_args()

    # Determine repo path
    if args.repo:
        repo = os.path.abspath(args.repo)
    else:
        # Assume script is in .hub/deploy/, dify is at .hub/dify/
        script_dir = os.path.dirname(os.path.abspath(__file__))
        repo = os.path.normpath(os.path.join(script_dir, "..", "dify"))
        if not os.path.isdir(os.path.join(repo, ".git")):
            # Fallback: try relative to cwd (which should be .hub/)
            repo = os.path.join(os.getcwd(), "dify")
            if not os.path.isdir(os.path.join(repo, ".git")):
                print("ERROR: Cannot find dify git repository. Use --repo to specify.", file=sys.stderr)
                sys.exit(1)

    # Detect base
    if args.base:
        base_version = args.base
        base_commit = resolve_rev(repo, args.base)
    else:
        base_version, base_commit = detect_base(repo)

    print(f"→ Base: {base_version} ({base_commit[:8]})", file=sys.stderr)
    print(f"→ Target: {args.target}", file=sys.stderr)
    print(f"→ Analyzing diffs...", file=sys.stderr)

    report = analyze(repo, base_version, base_commit, args.target)

    if args.json:
        print(format_json(report))
    else:
        print(format_plain(report))


if __name__ == "__main__":
    main()
