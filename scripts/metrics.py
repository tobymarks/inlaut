#!/usr/bin/env python3
"""Daily snapshot of the public numbers: release downloads, stars, repo traffic.

GitHub only keeps 14 days of traffic and no download history, so this appends
one line per day to metrics/snapshots.jsonl (gitignored). Run it by hand or
from the LaunchAgent (see README, "Numbers"); `--report` prints the history.
"""
import datetime
import json
import os
import pathlib
import subprocess
import sys

REPO = "tobymarks/inlaut"
OUT = pathlib.Path(__file__).resolve().parent.parent / "metrics" / "snapshots.jsonl"
GH = next((p for p in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh") if os.path.exists(p)), "gh")


def gh(path, token):
    out = subprocess.run([GH, "api", path], capture_output=True, text=True,
                         env={**os.environ, "GH_TOKEN": token}, check=True).stdout
    return json.loads(out)


def snapshot():
    # The repo belongs to the private account; the machine's active gh account is the work one.
    token = subprocess.run([GH, "auth", "token", "-u", "tobymarks"],
                           capture_output=True, text=True, check=True).stdout.strip()
    repo = gh(f"repos/{REPO}", token)
    releases = gh(f"repos/{REPO}/releases?per_page=100", token)
    dmg, zips = 0, {}
    for release in releases:
        for asset in release["assets"]:
            if asset["name"].endswith(".dmg"):
                dmg += asset["download_count"]
            elif asset["name"].endswith(".zip"):
                zips[release["tag_name"]] = asset["download_count"]
    views = gh(f"repos/{REPO}/traffic/views", token)
    return {
        "date": datetime.date.today().isoformat(),
        "dmg_downloads": dmg,                # new installs, summed over all releases
        "zip_downloads": zips,               # Sparkle updates per release, roughly active users
        "stars": repo["stargazers_count"],
        "forks": repo["forks_count"],
        "views": {v["timestamp"][:10]: [v["count"], v["uniques"]] for v in views["views"]},
        "referrers": {r["referrer"]: [r["count"], r["uniques"]]
                      for r in gh(f"repos/{REPO}/traffic/popular/referrers", token)},
    }


def load():
    if not OUT.exists():
        return []
    return [json.loads(line) for line in OUT.read_text().splitlines() if line.strip()]


def report():
    rows = load()
    views = {}
    for row in rows:
        views.update(row["views"])
    print(f"{'date':<12}{'DMG':>6}{'+':>5}{'stars':>7}{'repo views':>12}{'unique':>8}  updates per release")
    previous = None
    for row in rows:
        delta = "" if previous is None else f"{row['dmg_downloads'] - previous:+d}"
        count, uniques = views.get(row["date"], ["", ""])
        zips = ", ".join(f"{tag} {n}" for tag, n in row["zip_downloads"].items())
        print(f"{row['date']:<12}{row['dmg_downloads']:>6}{delta:>5}{row['stars']:>7}{count:>12}{uniques:>8}  {zips}")
        previous = row["dmg_downloads"]
    if rows:
        print("\nReferrers (last 14 days):",
              ", ".join(f"{name} {n[0]}" for name, n in rows[-1]["referrers"].items()) or "none")


if __name__ == "__main__":
    if "--report" in sys.argv:
        report()
    else:
        rows = [row for row in load() if row["date"] != datetime.date.today().isoformat()]
        rows.append(snapshot())
        OUT.parent.mkdir(exist_ok=True)
        OUT.write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows))
        report()
