#!/usr/bin/env python3
"""Receipt-only capture and reviewer-mediated release. Not an OS sandbox.

Run commands after --. Never place secrets/protected content in command arguments.
Reviewers alone use release; approval is a semantic attestation, not automated proof.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path('/private/tmp/dryrun-protected')
RELEASED = Path(__file__).resolve().parents[2] / 'docs/integration/released'
FIELDS = {'report_id', 'run_ids', 'feature', 'fixture_snapshot', 'versions',
          'criteria', 'synopsis', 'fact_findings', 'failures', 'likely_stage',
          'references', 'recommendations', 'retests', 'limitations', 'next_owner',
          'review_kind', 'reviewer_attestation'}


def emit(**values):
    print(json.dumps(values, sort_keys=True))


def capture(command, timeout=120):
    run_id = 'run-' + uuid.uuid4().hex
    folder = ROOT / run_id
    folder.mkdir(parents=True, mode=0o700)
    started = time.monotonic()
    status = 'failed'
    code = None
    process = None
    try:
        with (folder / 'stdout').open('wb') as out, (folder / 'stderr').open('wb') as err:
            process = subprocess.Popen(command, stdout=out, stderr=err,
                                       start_new_session=True)
            code = process.wait(timeout=timeout)
        status = 'succeeded' if code == 0 else 'failed'
    except subprocess.TimeoutExpired:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        status = 'timed_out'
    except BaseException:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        # Exception strings can echo arbitrary arguments and protected paths.
        status = 'capture_failed'
    receipt = dict(run_id=run_id, status=status, exit_code=code,
                   elapsed_ms=int((time.monotonic()-started)*1000),
                   evidence_handle=run_id)
    (folder / 'receipt.json').write_text(json.dumps(receipt))
    return receipt


def release(path):
    report = json.loads(Path(path).read_text())
    if not isinstance(report, dict) or set(report) - FIELDS:
        raise ValueError()
    required = {'report_id', 'run_ids', 'synopsis', 'limitations', 'reviewer_attestation'}
    if not required <= set(report) or report['reviewer_attestation'] != 'semantic-review-complete-no-protected-content':
        raise ValueError()
    rid = report['report_id']
    if not isinstance(rid, str) or not re.fullmatch(r'report-[a-z0-9-]{1,80}', rid):
        raise ValueError()
    serialized = json.dumps(report, indent=2)
    # Defense in depth only. Reviewer must inspect semantic disclosure separately.
    forbidden = ['data:image/', 'BEGIN PRIVATE KEY', 'DRYRUN_PROTECTED_MARKER_',
                 '"raw_output"', '"response_body"', '"transcript"', '"screenshot_base64"']
    if any(token in serialized for token in forbidden):
        raise ValueError()
    RELEASED.mkdir(parents=True, exist_ok=True)
    destination = RELEASED / (rid + '.json')
    with destination.open('x') as stream:
        stream.write(serialized + '\n')
    return rid


def preflight():
    checks = []
    marker = 'DRYRUN_PROTECTED_MARKER_' + uuid.uuid4().hex
    # Exercise actual child stdout/stderr, failures, assertion text, malformed
    # parsing, resumed prior output, capture preview and automatic-return analogue.
    cases = ["print(m)", "import sys; print(m, file=sys.stderr); sys.exit(2)",
             "assert False, m", "import json; json.loads(m)",
             "print({'prior_generated':m, 'resumed':True})",
             "print({'capture_preview':m})", "print('Final automatic return: '+m)"]
    for case in cases:
        receipt = capture([sys.executable, '-c', 'm='+repr(marker)+'; '+case])
        checks.append(marker not in json.dumps(receipt))
    # A timed-out captured child must not leave its own descendants running.
    sentinel = ROOT / ('timeout-sentinel-' + uuid.uuid4().hex)
    descendant = ('import time; from pathlib import Path; time.sleep(2); '
                  + 'Path(' + repr(str(sentinel)) + ').write_text("synthetic")')
    parent = ('import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",'
              + repr(descendant) + ']); time.sleep(30)')
    timed = capture([sys.executable, '-c', parent], timeout=1)
    time.sleep(2)
    checks.append(timed['status'] == 'timed_out' and not sentinel.exists())
    # Invalid and suspicious reports cannot be released; do not publish the marker.
    suspicious = ROOT / ('preflight-' + uuid.uuid4().hex + '.json')
    suspicious.write_text(json.dumps(dict(report_id='report-preflight-blocked', run_ids=[],
        synopsis=marker, limitations=[], reviewer_attestation='semantic-review-complete-no-protected-content')))
    try:
        release(suspicious)
        checks.append(False)
    except Exception:
        checks.append(True)
    emit(preflight='passed' if all(checks) else 'blocked', checks=len(checks),
         scope='synthetic-delivery-controls-only')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--timeout', type=int, default=120,
                        help='Capture timeout in seconds, 1 through 1800')
    parser.add_argument('mode', choices=['capture', 'release', 'preflight'])
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not 1 <= args.timeout <= 1800:
        raise ValueError()
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.mode == 'capture':
        command = args.arguments
        if len(command) >= 2 and command[0] == '--timeout':
            args.timeout = int(command[1])
            if not 1 <= args.timeout <= 1800:
                raise ValueError()
            command = command[2:]
        if command and command[0] == '--':
            command = command[1:]
        emit(**capture(command, timeout=args.timeout))
    elif args.mode == 'preflight':
        preflight()
    else:
        emit(status='released', report_id=release(args.arguments[0]))


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        emit(status='blocked', reason='reviewer-required')
        sys.exit(1)
