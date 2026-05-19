"""Minimal reporter: ledger + best + profile → markdown."""

import argparse
import json
from datetime import datetime
from pathlib import Path

import pandas as pd


def caveats(profile: dict, ok_runs: int) -> list[str]:
    out = []
    cb = profile.get("class_balance") or {}
    if cb:
        minority = min(cb.values())
        if minority < 0.2:
            out.append(f"class imbalance — minority class is {minority:.0%} of rows")
    if profile["rows"] < 10_000:
        out.append(f"small dataset ({profile['rows']:,} rows) — single-fold evaluation")
    if ok_runs < 2:
        out.append("only one successful run; comparison is informational")
    return out


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--best", required=True, type=Path)
    p.add_argument("--ledger", required=True, type=Path)
    p.add_argument("--profile", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    args = p.parse_args()

    profile = json.loads(args.profile.read_text())
    best = json.loads(args.best.read_text())
    ledger = pd.read_csv(args.ledger, sep="\t")

    ok = ledger[ledger["status"] == "ok"]

    lines = [
        f"# Tabular ML Report — {datetime.now():%Y-%m-%d}",
        "",
        "## Executive summary",
        "",
        f"We analyzed **{profile['rows']:,} rows** to predict **`{profile['target']}`** "
        f"({profile['target_type'].replace('_', ' ')}). "
        f"Best model: **{best['model']}** with "
        f"**{best['primary_metric_name']} = {float(best['primary_metric_value']):.4f}**.",
        "",
        "## What we tried",
        "",
        "| run_id | model | metric | value | status | seconds |",
        "|---|---|---|---|---|---|",
    ]
    for _, r in ledger.iterrows():
        # Failed rows may have an empty or non-numeric metric column. Use status as the gate.
        v = "—"
        if r["status"] == "ok" and pd.notna(r["primary_metric_value"]):
            try:
                v = f"{float(r['primary_metric_value']):.4f}"
            except (TypeError, ValueError):
                pass
        lines.append(
            f"| `{r['run_id']}` | {r['model']} | {r['primary_metric_name']} | {v} | {r['status']} | {r['duration_s']} |"
        )

    cs = caveats(profile, len(ok))
    if cs:
        lines += ["", "## Caveats", ""] + [f"- {c}" for c in cs]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n")

    print(json.dumps({
        "report": str(args.out),
        "winner": best["model"],
        "metric": best["primary_metric_name"],
        "value": float(best["primary_metric_value"]),
        "caveat": cs[0] if cs else None,
    }))


if __name__ == "__main__":
    main()
