"""Run mutation testing and fail the build when too few mutants are caught.

Coverage says a line ran. Mutation testing says a test would have noticed if it were wrong:
mutmut rewrites the source many ways and reports how many of those edits broke a test.

`mutmut run` always exits 0, even with every mutant surviving, so it cannot gate anything on
its own. This reads the stats it exports and applies a floor, the way stryker.config.json
does for the TypeScript template.

    uv run python scripts/mutation.py          # gate at FLOOR
    uv run python scripts/mutation.py --floor 0  # measure without failing

A mutant that no test even exercises counts against the score exactly like one that ran and
survived. Both mean the same thing: nothing would have objected.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Floor, not a target. Measured on the rendered template: 100% with 4 mutants. Set under
# that with room for one gap, because at this size a single uncaught mutant is a large
# percentage. Raise it as the suite grows; never lower it to turn a red build green, and
# re-baseline deliberately once this repo has real code rather than scaffolding.
FLOOR = 80.0

STATS = Path("mutants") / "mutmut-cicd-stats.json"


def run(*args: str) -> None:
    """Run a mutmut subcommand, letting its output through to the log."""
    result = subprocess.run(["mutmut", *args], check=False)
    if result.returncode != 0:
        # `run` exits 0 even with survivors, so a non-zero code here is a real tool failure
        # (bad config, collection error) and must not be read as "no mutants caught".
        print(f"mutmut {args[0]} failed with exit code {result.returncode}", file=sys.stderr)
        raise SystemExit(result.returncode)


def score(stats: dict[str, int]) -> float:
    """Percentage of mutants a test objected to. A timeout counts as caught: the mutant made
    the code hang and the suite noticed, which is the outcome the gate is asking about."""
    total = stats.get("total", 0)
    if total == 0:
        return 0.0
    detected = stats.get("killed", 0) + stats.get("timeout", 0)
    return detected / total * 100


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--floor", type=float, default=FLOOR)
    parser.add_argument("--skip-run", action="store_true", help="reuse the last run's results")
    args = parser.parse_args()

    if not args.skip_run:
        run("run")
    run("export-cicd-stats")

    if not STATS.is_file():
        print(f"{STATS} was not written; cannot score this run", file=sys.stderr)
        return 1
    stats = json.loads(STATS.read_text(encoding="utf-8"))

    result = score(stats)
    gaps = stats.get("survived", 0) + stats.get("no_tests", 0)
    print(
        f"mutation score {result:.2f}% "
        f"({stats.get('killed', 0)} killed, {stats.get('survived', 0)} survived, "
        f"{stats.get('no_tests', 0)} never exercised, {stats.get('total', 0)} total)"
    )
    if result < args.floor:
        print(
            f"FAIL: {result:.2f}% is under the {args.floor:.2f}% floor, "
            f"{gaps} mutant(s) nothing would have caught. "
            "Run `mutmut browse` to see them.",
            file=sys.stderr,
        )
        return 1
    print(f"OK: at or above the {args.floor:.2f}% floor")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
