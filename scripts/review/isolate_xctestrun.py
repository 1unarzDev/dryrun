#!/usr/bin/env python3
"""Copy generated test configuration, forcing the unit app host into memory."""
import plistlib
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
source = next(root.glob('*.xctestrun'))
data = plistlib.loads(source.read_bytes())
data['DryRunTests']['CommandLineArguments'] = ['-uiTestingInMemory']


def fix(value):
    if isinstance(value, str):
        return value.replace('__TESTROOT__', str(root))
    if isinstance(value, list):
        return [fix(item) for item in value]
    if isinstance(value, dict):
        return {key: fix(item) for key, item in value.items()}
    return value


Path(sys.argv[2]).write_bytes(plistlib.dumps(fix(data)))
