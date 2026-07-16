import json
import re
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "VISUALS_DB.md"
MANIFEST = ROOT / "Assets" / "Data" / "visuals" / "default.json"
SECTION_RE = re.compile(r"^## (.+?) \((\d+)\)$")
ID_RE = re.compile(r"^[a-z0-9_.:-]+$")
SNAPSHOT_RE = re.compile(r"Source commit: `([0-9a-f]{7,40})`")
SOURCE_REF_RE = re.compile(
    r"(?<![A-Za-z0-9_])((?:\.\./)?(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+"
    r"\.(?:lua|py|pescene|json)):(\d+)"
)
ASSET_RE = re.compile(
    r"^(?:Assets/|Textures/|Objects/|\.\./Textures/|ui/).+\.(?:png|json|pescene)$"
)


def split_row(line):
    marker = "\0"
    return [
        cell.replace(marker, "|").strip()
        for cell in line.strip()[1:-1].replace(r"\|", marker).split("|")
    ]


def asset_path(value):
    value = value.removeprefix("input: ")
    if value.startswith("Assets/"):
        return ROOT / value
    if value.startswith("../"):
        return (ROOT / "Assets" / "Scenes" / value).resolve()
    if value.startswith("ui/"):
        return ROOT / "Assets" / "Textures" / value
    return ROOT / "Assets" / value


def source_paths(value, by_name):
    if value.startswith("Assets/"):
        return [ROOT / value]
    if value.startswith("Scripts/"):
        return [ROOT / "Assets" / value]
    if value.startswith(("shared/", "modes/", "Player/")):
        return [ROOT / "Assets" / "Scripts" / value]
    if value.startswith("tools/"):
        return [ROOT / value]
    if value.startswith("../"):
        return [(ROOT / "Assets" / "Scenes" / value).resolve()]
    if value.endswith(".pescene"):
        return [ROOT / "Assets" / "Scenes" / value]
    return by_name[Path(value).name]


def main():
    text = DOC.read_text(encoding="utf-8")
    lines = text.splitlines()
    errors = []
    claimed = {}
    counts = Counter()
    ids = defaultdict(list)
    concrete_assets = 0
    section = None

    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        manifest = {}
        errors.append(f"invalid runtime manifest: {exc}")

    manifest_paths = 0

    def check_manifest(value, key):
        nonlocal manifest_paths
        if isinstance(value, dict):
            for child_key, child in value.items():
                check_manifest(child, f"{key}.{child_key}" if key else child_key)
            return
        if not isinstance(value, str):
            errors.append(f"manifest {key}: expected path string")
            return
        manifest_paths += 1
        if not value.startswith(("Textures/", "Objects/")):
            errors.append(f"manifest {key}: invalid asset path {value!r}")
        elif not (ROOT / "Assets" / value).exists():
            errors.append(f"manifest {key}: missing asset {value}")

    check_manifest(manifest, "")

    for line_number, line in enumerate(lines, 1):
        match = SECTION_RE.match(line)
        if match:
            section = match.group(1)
            claimed[section] = int(match.group(2))
            continue
        if line.startswith("## "):
            section = None
            continue
        if not section or not line.startswith("| ") or line.startswith(("| id |", "|---")):
            continue

        cells = split_row(line)
        if len(cells) != 8:
            errors.append(f"line {line_number}: expected 8 columns, found {len(cells)}")
            continue
        record_id, name, _, assets, _, _, _, _ = cells
        counts[section] += 1
        ids[record_id].append(line_number)
        if not ID_RE.fullmatch(record_id):
            errors.append(f"line {line_number}: invalid id {record_id!r}")
        if not name:
            errors.append(f"line {line_number}: empty name for {record_id}")

        for value in assets.split("<br>"):
            value = value.strip()
            candidate = value.removeprefix("input: ")
            if not ASSET_RE.fullmatch(candidate) or any(char in candidate for char in "<>{}"):
                continue
            concrete_assets += 1
            if not asset_path(value).exists():
                errors.append(f"line {line_number}: missing asset {candidate}")

    confidence_ids = []
    in_confidence = False
    for line_number, line in enumerate(lines, 1):
        if line == "### Confidence exceptions":
            in_confidence = True
            continue
        if in_confidence and line.startswith("## "):
            break
        if not in_confidence or not line.startswith("| ") or line.startswith(("| id |", "|---")):
            continue
        cells = split_row(line)
        if len(cells) != 3:
            errors.append(f"line {line_number}: confidence exception must have 3 columns")
            continue
        confidence_ids.append(cells[0])

    for name, expected in claimed.items():
        if counts[name] != expected:
            errors.append(f"section {name}: expected {expected} records, found {counts[name]}")
    for record_id, line_numbers in ids.items():
        if len(line_numbers) > 1:
            errors.append(f"duplicate id {record_id!r} on lines {line_numbers}")
    for record_id in confidence_ids:
        if record_id not in ids:
            errors.append(f"confidence exception {record_id!r} has no matching record")

    summary = re.search(r"\*\*(\d+) records total\*\*", text)
    if not summary or int(summary.group(1)) != sum(counts.values()):
        errors.append("record total does not match the category tables")

    snapshot = SNAPSHOT_RE.search(text)
    if not snapshot:
        errors.append("missing source commit")
    elif subprocess.run(
        ["git", "cat-file", "-e", f"{snapshot.group(1)}^{{commit}}"],
        cwd=ROOT,
        capture_output=True,
    ).returncode:
        errors.append(f"source commit {snapshot.group(1)} is not present in this repository")

    by_name = defaultdict(list)
    for path in ROOT.rglob("*"):
        if path.is_file() and "__pycache__" not in path.parts:
            by_name[path.name].append(path)

    line_counts = {}
    ambiguous_refs = 0
    checked_refs = 0
    for value, raw_line in SOURCE_REF_RE.findall(text):
        paths = source_paths(value, by_name)
        if len(paths) != 1:
            ambiguous_refs += 1
            continue
        path = paths[0]
        if not path.exists():
            errors.append(f"missing source reference {value}")
            continue
        if path not in line_counts:
            line_counts[path] = len(path.read_text(encoding="utf-8").splitlines())
        checked_refs += 1
        if int(raw_line) > line_counts[path]:
            errors.append(f"source reference {value}:{raw_line} exceeds {line_counts[path]} lines")

    if errors:
        print("VISUALS_DB validation failed:")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)

    print(
        f"VISUALS_DB OK: {sum(counts.values())} unique records, "
        f"{concrete_assets} audit assets, {manifest_paths} runtime paths, "
        f"{checked_refs} source references "
        f"({ambiguous_refs} ambiguous basenames skipped)"
    )


if __name__ == "__main__":
    main()
