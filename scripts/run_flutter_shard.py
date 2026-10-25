"""Complete deterministic Flutter file shards with source-bound execution receipts.

Uses only Python stdlib and Flutter's additional JSON file reporter. No test
filters, timeout changes, new skips, concurrency changes or SDK installation.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


class ContractError(ValueError):
    pass


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(',', ':')).encode()).hexdigest()


def relative(path):
    if not isinstance(path, str):
        raise ContractError('noncanonical_test_path')
    value = PurePosixPath(path)
    if (not path or '\\' in path or value.is_absolute()
            or '..' in value.parts or value.as_posix() != path
            or any(ord(char) < 32 for char in path) or '?' in path or '#' in path):
        raise ContractError('noncanonical_test_path')
    return path


def git_head(root):
    value = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', value):
        raise ContractError('source_commit_required')
    return value


def tracked_paths(root):
    raw = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z'])
    return [item.decode() for item in raw.split(b'\0') if item]


def snapshot(root):
    root = root.resolve()
    commit = git_head(root)
    expected = os.environ.get('GITHUB_SHA')
    if expected and expected != commit:
        raise ContractError('checkout_commit_mismatch')
    inventory = []
    for path in sorted((root / 'app/test').rglob('*_test.dart')):
        name = relative(path.relative_to(root).as_posix())
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            raise ContractError('regular_test_file_required')
        inventory.append({'path': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    if not inventory:
        raise ContractError('empty_test_inventory')
    paths = set(tracked_paths(root))
    # Also bind generated/untracked local Dart helpers if present. CI checkouts
    # normally contain only tracked sources plus ignored SDK/build products.
    paths.update(p.relative_to(root).as_posix() for directory in ('app/lib', 'app/test')
        for p in (root / directory).rglob('*.dart'))
    manifest = []
    for name in sorted(paths):
        relative(name)
        path = root / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(root):
            raise ContractError('regular_source_file_required')
        manifest.append((name, hashlib.sha256(path.read_bytes()).hexdigest()))
    return {'commit': commit, 'source_sha256': digest(manifest), 'source_file_count': len(manifest),
        'inventory_sha256': digest(inventory), 'inventory': inventory}


def facts(value):
    return {key: item for key, item in value.items() if key != 'inventory'}


def partition(inventory, index, count=3):
    if type(count) is not int or count != 3 or type(index) is not int or not 0 <= index < count:
        raise ContractError('exact_three_shards_required')
    paths = [relative(row['path']) for row in inventory]
    if paths != sorted(set(paths)):
        raise ContractError('unique_sorted_inventory_required')
    selected = [path for offset, path in enumerate(paths) if offset % count == index]
    if not selected:
        raise ContractError('empty_selected_shard')
    return selected


def immutable_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    # No old success may survive or be silently replaced on a reused output.
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write('\n')


def report_path(value, root):
    if not isinstance(value, str) or '?' in value or '#' in value:
        raise ContractError('invalid_report_suite_path')
    path = Path(value)
    if not path.is_absolute():
        path = root / 'app' / path
    if not path.resolve().is_relative_to(root.resolve()):
        raise ContractError('foreign_report_suite')
    return relative(path.resolve().relative_to(root.resolve()).as_posix())


def read_report(path, root, selected):
    suites, tests, finished = {}, {}, {}
    starts, terminal, all_suites, error_events = [], [], [], 0
    try:
        with path.open(encoding='utf-8') as stream:
            for line in stream:
                event = json.loads(line)
                kind = event['type']
                if terminal:
                    raise ContractError('events_after_terminal_report')
                if kind == 'start':
                    starts.append(event.get('protocolVersion'))
                elif kind == 'suite':
                    suite = event['suite']
                    key = suite['id']
                    if type(key) is not int or key in suites:
                        raise ContractError('duplicate_report_suite')
                    suites[key] = report_path(suite['path'], root)
                elif kind == 'testStart':
                    test = event['test']
                    key = test['id']
                    if (type(key) is not int or key in tests or type(test['suiteID']) is not int
                            or test['suiteID'] not in suites or not isinstance(test['name'], str)):
                        raise ContractError('duplicate_or_foreign_report_test')
                    tests[key] = {'file': suites[test['suiteID']], 'name': test['name']}
                elif kind == 'testDone':
                    key = event['testID']
                    if (type(key) is not int or key not in tests or key in finished or type(event['hidden']) is not bool
                            or type(event['skipped']) is not bool
                            or event['result'] not in ('success', 'failure', 'error')
                            or event['skipped'] and event['result'] != 'success'):
                        raise ContractError('invalid_report_test_completion')
                    finished[key] = {**tests[key], **{key: event[key] for key in ('hidden', 'skipped', 'result')}}
                elif kind == 'allSuites':
                    if type(event['count']) is not int:
                        raise ContractError('invalid_report_suite_count')
                    all_suites.append(event['count'])
                elif kind == 'error':
                    error_events += 1
                elif kind == 'done':
                    terminal.append(event.get('success'))
    except (OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError) as error:
        raise ContractError('missing_or_malformed_report') from error
    if (starts != ['0.1.1'] or len(terminal) != 1 or type(terminal[0]) is not bool or set(tests) != set(finished) or not tests
            or all_suites != [len(selected)] or len(suites) != len(selected)
            or sorted(suites.values()) != sorted(selected)):
        raise ContractError('incomplete_or_foreign_report')
    visible = [row for row in finished.values() if not row['hidden']]
    if not visible:
        raise ContractError('no_visible_tests_executed')
    counts = {'passed': 0, 'skipped': 0, 'failed': 0, 'errors': 0, 'hidden': len(finished) - len(visible),
        'hidden_failures': 0, 'error_events': error_events}
    for row in finished.values():
        if row['hidden']:
            counts['hidden_failures'] += row['result'] != 'success'
        elif row['skipped']:
            counts['skipped'] += 1
        else:
            counts[{'success': 'passed', 'failure': 'failed', 'error': 'errors'}[row['result']]] += 1
    # Loading/setup events are excluded from user test counts. A platform skip
    # has result=success in this protocol and must never become a passed test.
    return {**counts, 'visible_tests': len(visible), 'observed_files': sorted(suites.values()),
        'execution_sha256': digest([finished[key] for key in sorted(finished)]),
        'report_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'terminal_success': terminal[0]}


def export_output(path, index, receipt):
    if path:
        value = json.dumps(receipt, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
        with Path(path).open('a', encoding='utf-8') as stream:
            stream.write(f'receipt_{index}={value}\n')


def run(root, index, count, receipt_path, flutter='flutter', github_output=None):
    root = root.resolve()
    if receipt_path.suffix != '.json' or receipt_path.is_symlink():
        raise ContractError('regular_json_receipt_required')
    receipt_path = receipt_path.resolve()
    before_path = receipt_path.with_suffix('.before.json')
    after_path = receipt_path.with_suffix('.after.json')
    events_path = receipt_path.with_suffix('.events.jsonl')
    if any(path.exists() or path.is_symlink() for path in (receipt_path, before_path, after_path, events_path)):
        raise ContractError('fresh_receipt_paths_required')
    before = snapshot(root)
    selected = partition(before['inventory'], index, count)
    immutable_json(before_path, before)
    receipt = {'version': 1, 'kind': 'flutter_file_shard', 'shard_index': index, 'shard_count': count,
        'run_id': os.environ.get('GITHUB_RUN_ID'), 'run_attempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
        'before': facts(before), 'all_files': before['inventory'],
        'selected_files': selected, 'selection_sha256': digest(selected),
        'status': 'incomplete', 'process_exit_code': None, 'execution': None}
    try:
        args = [flutter, 'test', '--no-pub', f'--file-reporter=json:{events_path}', '--',
            *(str(Path(path).relative_to('app')) for path in selected)]
        receipt['process_exit_code'] = subprocess.run(args, cwd=root / 'app', check=False).returncode
        receipt['execution'] = read_report(events_path, root, selected)
    except (OSError, ContractError) as error:
        receipt['error'] = str(error) if isinstance(error, ContractError) else 'flutter_process_start_failed'
    finally:
        try:
            after = snapshot(root)
            immutable_json(after_path, after)
            receipt['after'] = facts(after)
            receipt['sources_unchanged'] = before == after
        except (OSError, subprocess.SubprocessError, ContractError) as error:
            receipt['error'] = str(error) if isinstance(error, ContractError) else 'source_recheck_failed'
            receipt['sources_unchanged'] = False
        execution = receipt['execution'] or {}
        receipt['status'] = ('passed' if receipt['process_exit_code'] == 0
            and execution.get('terminal_success') is True
            and all(execution.get(key) == 0 for key in ('failed', 'errors', 'hidden_failures', 'error_events'))
            and receipt['sources_unchanged'] and 'error' not in receipt else 'failed')
        immutable_json(receipt_path, receipt)
        export_output(github_output, index, receipt)
    print(json.dumps({'shard': index, 'selected_files': len(selected), 'status': receipt['status'],
        'process_exit_code': receipt['process_exit_code'],
        'counts': ({key: receipt['execution'][key] for key in ('passed', 'skipped', 'failed', 'errors', 'hidden')}
            if receipt['execution'] else None),
        'receipt_sha256': hashlib.sha256(receipt_path.read_bytes()).hexdigest()}, sort_keys=True))
    return receipt['process_exit_code'] if receipt['process_exit_code'] else (0 if receipt['status'] == 'passed' else 2)


def verify(root, receipts, require_job_results=False):
    if require_job_results and any(os.environ.get(key) != 'success'
        for key in ('FLUTTER_TEST_JOB_RESULT', 'FLUTTER_STATIC_JOB_RESULT')):
        raise ContractError('all_test_and_static_jobs_must_succeed')
    if len(receipts) != 3 or sorted(row.get('shard_index') for row in receipts) != [0, 1, 2]:
        raise ContractError('exact_three_distinct_receipts_required')
    current = snapshot(root)
    union = []
    for receipt in receipts:
        index = receipt['shard_index']
        selected = partition(current['inventory'], index, 3)
        execution = receipt.get('execution') or {}
        if (receipt.get('version') != 1 or receipt.get('kind') != 'flutter_file_shard'
                or receipt.get('shard_count') != 3 or receipt.get('status') != 'passed'
                or receipt.get('process_exit_code') != 0 or receipt.get('before') != facts(current)
                or receipt.get('after') != facts(current) or receipt.get('all_files') != current['inventory'] or receipt.get('sources_unchanged') is not True
                or receipt.get('selected_files') != selected or receipt.get('selection_sha256') != digest(selected)
                or execution.get('observed_files') != selected or execution.get('terminal_success') is not True
                or any(execution.get(key) != 0 for key in ('failed', 'errors', 'hidden_failures', 'error_events'))
                or any(type(execution.get(key)) is not int or execution[key] < 0
                    for key in ('passed', 'skipped', 'visible_tests'))
                or execution.get('visible_tests', 0) < 1
                or execution.get('visible_tests') != execution.get('passed', -1) + execution.get('skipped', -1)
                or any(receipt.get(key) != os.environ.get(env) for key, env in
                    (('run_id', 'GITHUB_RUN_ID'), ('run_attempt', 'GITHUB_RUN_ATTEMPT')))):
            raise ContractError('stale_incomplete_or_different_source_receipt')
        union.extend(selected)
    expected = [row['path'] for row in current['inventory']]
    if sorted(union) != expected or len(set(union)) != len(union):
        raise ContractError('file_union_must_be_exactly_once')
    return {'version': 1, 'status': 'passed', 'source_commit': current['commit'],
        'source_sha256': current['source_sha256'], 'inventory_sha256': current['inventory_sha256'],
        'all_files': len(expected), 'exactly_once': True, 'shards': 3,
        'passed': sum(row['execution']['passed'] for row in receipts),
        'skipped': sum(row['execution']['skipped'] for row in receipts),
        'receipt_sha256s': [digest(row) for row in sorted(receipts, key=lambda row: row['shard_index'])]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    commands = parser.add_subparsers(dest='command', required=True)
    run_parser = commands.add_parser('run')
    run_parser.add_argument('--shard-index', type=int, required=True, choices=range(3))
    run_parser.add_argument('--shard-count', type=int, choices=(3,), default=3)
    run_parser.add_argument('--receipt', type=Path, required=True)
    run_parser.add_argument('--flutter', default='flutter')
    run_parser.add_argument('--github-output', default=os.environ.get('GITHUB_OUTPUT'))
    verify_parser = commands.add_parser('verify')
    verify_parser.add_argument('--receipts', type=Path, nargs=3)
    verify_parser.add_argument('--from-env', action='store_true')
    verify_parser.add_argument('--receipt', type=Path, required=True)
    verify_parser.add_argument('--require-job-results', action='store_true')
    args = parser.parse_args(argv)
    try:
        if args.command == 'run':
            return run(args.root, args.shard_index, args.shard_count, args.receipt, args.flutter, args.github_output)
        if args.from_env == bool(args.receipts):
            raise ContractError('exact_one_receipt_input_mode_required')
        receipts = ([json.loads(os.environ[f'FLUTTER_RECEIPT_{index}']) for index in range(3)]
            if args.from_env else [json.loads(path.read_text()) for path in args.receipts])
        result = verify(args.root, receipts, args.require_job_results)
        immutable_json(args.receipt, result)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, subprocess.SubprocessError, KeyError, TypeError, ValueError) as error:
        print(f'Flutter shard contract failed: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
