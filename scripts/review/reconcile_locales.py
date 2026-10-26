#!/usr/bin/env python3
"""Reviewer-approved static localization assets: add missing keys only."""
import json
from pathlib import Path
import subprocess

summary = []
for locale in ['en', 'es', 'vi']:
    for name in ['actions', 'ai', 'common', 'help', 'native', 'plan', 'scenarios', 'spatial']:
        path = Path(f'content/locales/{locale}/{name}.json')
        current = json.loads(path.read_text())
        counts = {}
        for ref in ['5f95135', 'a9efc8f']:
            donor = json.loads(subprocess.check_output(['git', 'show', f'{ref}:{path}']))
            if not isinstance(donor, dict) or not all(isinstance(value, str) for value in donor.values()):
                raise ValueError('non-static-localization')
            missing = {key: donor[key] for key in donor if key not in current}
            current.update(missing)
            counts[ref] = len(missing)
        if sum(counts.values()):
            path.write_text(json.dumps(current, ensure_ascii=False, indent=2) + '\n')
        summary.append({'path': str(path), 'added': counts, 'total': len(current)})
print(json.dumps(summary))
