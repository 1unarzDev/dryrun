#!/usr/bin/env python3
"""Render a beacon-latency receipt (timing/status/servedBy codes only) into performance.md between markers."""
import json
import sys
from collections import defaultdict

doc_path, provider, parallel = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
receipts = []
for path in sys.argv[4:]:
    try:
        receipts.append(json.load(open(path)))
    except (OSError, ValueError):
        pass
if not receipts:
    sys.exit('no receipts')
groups = defaultdict(list)
for receipt in receipts:
    for s in receipt['samples']:
        groups[s['role']].append(s)
r = dict(started=min(x['started'] for x in receipts), finished=max(x['finished'] for x in receipts),
         runs=receipts[0]['runs'])


def pct(values, p):
    v = sorted(values)
    if not v:
        return None
    k = (len(v) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return round(v[lo] + (v[hi] - v[lo]) * (k - lo))


def fmt(ms):
    return '-' if ms is None else f"{ms / 1000:.1f}s"


order = ['preparation', 'debrief', 'resources', 'director_start', 'director_turn', 'director_operation']
lines = ["<!-- latency:begin -->",
         f"Run {r['started']} to {r['finished']}; chain starts at `{provider}`; {r['runs']} run(s) per role; " +
         ("one sequential stream per role, role streams concurrent" if parallel else "all requests sequential")
         + " against a private gateway on 127.0.0.1:8792.",
         "",
         "| Role | n | ok | p50 total | p90 total | max total | p50 TTFB | servedBy | status:reason | tool rounds |",
         "|---|---|---|---|---|---|---|---|---|---|"]
for role in order + sorted(set(groups) - set(order)):
    ss = groups.get(role)
    if not ss:
        continue
    totals = [s['totalMS'] for s in ss]
    ttfb = [s['ttfbMS'] for s in ss if 'ttfbMS' in s]
    ok = sum(1 for s in ss if s.get('status') in ('completed', 'needs_client_tools'))
    served, statuses = defaultdict(int), defaultdict(int)
    for s in ss:
        served[s.get('servedBy') or s.get('provider') or 'none'] += 1
        statuses[(s.get('status') or 'none') + (':' + s['reason'] if s.get('reason') else '')] += 1
    rounds = [s['toolRounds'] for s in ss if 'toolRounds' in s]
    lines.append(f"| {role} | {len(ss)} | {ok} | {fmt(pct(totals, .5))} | {fmt(pct(totals, .9))} | {fmt(max(totals))} | "
                 f"{fmt(pct(ttfb, .5))} | " + ', '.join(f"{k} x{v}" for k, v in sorted(served.items())) + " | "
                 + ', '.join(f"{k} x{v}" for k, v in sorted(statuses.items())) + " | "
                 + (', '.join(map(str, rounds)) if rounds else '-') + " |")
lines.append("<!-- latency:end -->")
block = '\n'.join(lines)
doc = open(doc_path).read()
a, b = doc.find('<!-- latency:begin -->'), doc.find('<!-- latency:end -->')
end = '<!-- latency:end -->'
doc = doc[:a] + block + doc[b + len(end):] if a >= 0 and b > a else doc + '\n' + block + '\n'
open(doc_path, 'w').write(doc)
print(block)
