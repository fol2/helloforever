#!/usr/bin/env python3
"""Check exported fight files against the mock API truth (lossless test)."""
import json, sys
from pathlib import Path

truth = json.load(open(sys.argv[1]))
base = Path(sys.argv[2])

def norm(v):
    if isinstance(v, dict):
        if not v:
            return []
        if all(isinstance(k, str) and k.isdigit() for k in v):
            return [norm(v[k]) for k in sorted(v, key=int)]
        return {k: norm(x) for k, x in v.items()}
    if isinstance(v, list):
        return [norm(x) for x in v]
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v

def diff(a, b, path=""):
    a, b = norm(a), norm(b)
    if isinstance(a, dict) and isinstance(b, dict):
        out = []
        for k in set(a) | set(b):
            if k not in a: out.append(f"{path}/{k}: missing in export")
            elif k not in b: out.append(f"{path}/{k}: extra in export")
            else: out += diff(a[k], b[k], f"{path}/{k}")
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): return [f"{path}: len {len(a)} != {len(b)}"]
        out = []
        for i, (x, y) in enumerate(zip(a, b)): out += diff(x, y, f"{path}[{i}]")
        return out
    if isinstance(a, float) or isinstance(b, float):
        return [] if abs(float(a) - float(b)) < 1e-9 else [f"{path}: {a} != {b}"]
    return [] if a == b else [f"{path}: {a!r} != {b!r}"]

files = {json.load(open(p))["key"]: json.load(open(p)) for p in base.glob("*/*/*/*.json") if p.name != "index.json" and ".gap." not in p.name and "legacy" not in str(p)}
bad = 0
for key, t in truth.items():
    rec = files.get(key)
    if not rec:
        print("MISSING", key); bad += 1; continue
    d = diff(rec["types"], t["types"], key)
    fields = sum(1 for _ in json.dumps(t["types"]).split(","))
    if d:
        bad += 1; print("DIFF", key, d[:5])
    else:
        print(f"LOSSLESS {key} {t['name']!r} rev={rec.get('rev')} types={len(rec['types'])} ~{fields} values, recaps={len(rec.get('recaps') or {})}")
print("exported files:", len(files), "truth sessions:", len(truth), "bad:", bad)
sys.exit(1 if bad else 0)
