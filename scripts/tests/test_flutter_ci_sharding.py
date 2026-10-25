"""Stdlib fake-Flutter process contracts; no Flutter/Dart/app/DB/network import."""
import copy
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'run_flutter_shard.py'
spec = importlib.util.spec_from_file_location('flutter_ci_runner', SCRIPT)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)
SHA = 'a' * 40

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
assert args[:2] == ['test', '--no-pub']
report = Path(args[2].removeprefix('--file-reporter=json:'))
assert args[3] == '--'
files = args[4:]
mode = os.environ.get('FAKE_MODE', 'success')
events = [{'type': 'start', 'protocolVersion': '0.1.1'}]
testid = 0
for index, file in enumerate(files):
    suite = index * 100
    events.append({'type': 'suite', 'suite': {'id': suite, 'path': str(Path(file).resolve())}})
    for name, hidden, skipped in [('loading', True, False), ('actual pass', False, False), ('platform skip', False, True)]:
        testid += 1
        events.append({'type': 'testStart', 'test': {'id': testid, 'suiteID': suite, 'name': name}})
        result = 'failure' if mode == 'failure' and name == 'actual pass' else 'success'
        if mode == 'failure' and name == 'actual pass':
            events.append({'type': 'error', 'testID': testid, 'error': 'synthetic assertion failure'})
        events.append({'type': 'testDone', 'testID': testid, 'result': result, 'hidden': hidden, 'skipped': skipped})
events.append({'type': 'allSuites', 'count': len(files)})
events.append({'type': 'done', 'success': mode != 'failure'})
if mode == 'missing':
    sys.exit(0)
if mode in ('truncated', 'source_change_truncated'):
    events.pop()
if mode == 'missing_start':
    events.pop(0)
if mode == 'wrong_protocol':
    events[0]['protocolVersion'] = '999'
if mode == 'foreign':
    events[1]['suite']['path'] = str(Path('../foreign_test.dart').resolve())
if mode == 'duplicate':
    events.insert(2, events[1])
if mode in ('source_change', 'source_change_truncated'):
    Path(files[0]).write_text('changed while fake test ran')
if mode == 'all_hidden':
    for event in events:
        if event['type'] == 'testDone':
            event['hidden'] = True
report.write_text(''.join(json.dumps(e) + '\n' for e in events))
if mode == 'malformed':
    report.write_text('{not json}\n')
if mode == 'process_fail':
    sys.exit(23)
sys.exit(1 if mode == 'failure' else 0)
'''


class FlutterShardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='flutter-ci-fake-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'app/test/nested').mkdir(parents=True)
        (self.root / 'app/lib').mkdir()
        for name in ['a_test.dart', 'b_test.dart', 'c_test.dart', 'd_test.dart', 'e_test.dart', 'nested/f_test.dart', 'nested/g_test.dart']:
            (self.root / 'app/test' / name).write_text('// artificial test file\n')
        (self.root / 'app/test/helper.dart').write_text('// not a standalone test\n')
        (self.root / 'app/lib/main.dart').write_text('// artificial product dependency\n')
        self.tracked = [p.relative_to(self.root).as_posix() for p in self.root.rglob('*.dart')]
        self.fake = self.root / 'fake_flutter'
        self.fake.write_text(FAKE)
        self.fake.chmod(0o700)
        self.env = patch.dict(os.environ, {'GITHUB_SHA': SHA, 'GITHUB_RUN_ID': '100', 'GITHUB_RUN_ATTEMPT': '1', 'FAKE_MODE': 'success'}, clear=False)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.head = patch.object(runner, 'git_head', return_value=SHA)
        self.paths = patch.object(runner, 'tracked_paths', return_value=self.tracked)
        self.head.start()
        self.paths.start()
        self.addCleanup(self.head.stop)
        self.addCleanup(self.paths.stop)

    def execute(self, index=0, mode='success', name=None):
        destination = self.root / 'receipts' / (name or f'shard-{index}.json')
        with patch.dict(os.environ, {'FAKE_MODE': mode}):
            result = runner.run(self.root, index, 3, destination, str(self.fake))
        return result, json.loads(destination.read_text())

    def receipts(self):
        return [self.execute(index)[1] for index in range(3)]

    def test_all_default_inventory_files_exactly_once_across_three_deterministic_collections(self):
        all_files = runner.snapshot(self.root)['inventory']
        selected = [runner.partition(all_files, index) for index in range(3)]
        self.assertEqual([len(files) for files in selected], [3, 2, 2])
        self.assertEqual(sorted(path for group in selected for path in group), [row['path'] for row in all_files])
        self.assertEqual(len(set(path for group in selected for path in group)), 7)
        self.assertNotIn('app/test/helper.dart', sum(selected, []))
        for index in range(3):
            self.assertEqual(selected[index], runner.partition(all_files, index))

    def test_real_fake_processes_cover_full_nonsharded_collection_with_exact_test_counts(self):
        receipts = self.receipts()
        complete = runner.verify(self.root, receipts)
        inventory = runner.snapshot(self.root)['inventory']
        path = self.root / 'baseline.jsonl'
        result = subprocess.run([str(self.fake), 'test', '--no-pub', f'--file-reporter=json:{path}', '--',
            *(str(Path(row['path']).relative_to('app')) for row in inventory)], cwd=self.root / 'app', check=False)
        self.assertEqual(result.returncode, 0)
        baseline = runner.read_report(path, self.root, [row['path'] for row in inventory])
        self.assertEqual(complete['all_files'], 7)
        self.assertTrue(complete['exactly_once'])
        self.assertEqual((complete['passed'], complete['skipped']), (baseline['passed'], baseline['skipped']))
        self.assertEqual((complete['passed'], complete['skipped']), (7, 7))
        self.assertEqual(sum(row['execution']['hidden'] for row in receipts), 7)
        def collected(path):
            events = [json.loads(line) for line in path.read_text().splitlines()]
            suites = {e['suite']['id']: e['suite']['path'] for e in events if e['type'] == 'suite'}
            starts = {e['test']['id']: e['test'] for e in events if e['type'] == 'testStart'}
            return [(suites[starts[e['testID']]['suiteID']], starts[e['testID']]['name'])
                for e in events if e['type'] == 'testDone' and not e['hidden']]
        complete_nodes = collected(path)
        partition_nodes = [node for index in range(3)
            for node in collected(self.root / 'receipts' / f'shard-{index}.events.jsonl')]
        self.assertEqual(sorted(complete_nodes), sorted(partition_nodes))
        self.assertEqual(len(partition_nodes), len(set(partition_nodes)))

    def test_existing_platform_skips_are_not_counted_as_passes(self):
        result, receipt = self.execute()
        self.assertEqual(result, 0)
        self.assertEqual(receipt['execution']['passed'], 3)
        self.assertEqual(receipt['execution']['skipped'], 3)
        self.assertEqual(receipt['execution']['visible_tests'], 6)
        self.assertEqual(receipt['execution']['hidden'], 3)

    def test_before_after_receipts_are_immutable_and_source_bound(self):
        self.execute()
        target = self.root / 'receipts/shard-0.json'
        before, after = target.with_suffix('.before.json'), target.with_suffix('.after.json')
        self.assertEqual(before.read_bytes(), after.read_bytes())
        with self.assertRaises(FileExistsError):
            runner.immutable_json(before, {'modified': True})
        with self.assertRaises(runner.ContractError):
            runner.run(self.root, 0, 3, target, str(self.fake))

    def test_invalid_counts_and_indices_fail_instead_of_empty_or_unsharded_success(self):
        inventory = runner.snapshot(self.root)['inventory']
        for index, count in [(0, 1), (0, 2), (0, 4), (3, 3), (-1, 3), (True, 3), (0, True)]:
            with self.subTest(index=index, count=count), self.assertRaises(runner.ContractError):
                runner.partition(inventory, index, count)
        with self.assertRaises(runner.ContractError):
            runner.partition(inventory[:1], 2)

    def test_duplicate_or_reordered_inventory_fails(self):
        inventory = runner.snapshot(self.root)['inventory']
        for values in ([*inventory, inventory[0]], list(reversed(inventory))):
            with self.assertRaises(runner.ContractError):
                runner.partition(values, 0)

    def test_missing_receipt_fails_verification(self):
        with self.assertRaises(runner.ContractError):
            runner.verify(self.root, self.receipts()[:2])

    def test_duplicate_shard_receipt_fails_verification(self):
        receipts = self.receipts()
        with self.assertRaises(runner.ContractError):
            runner.verify(self.root, [receipts[0], receipts[0], receipts[2]])

    def test_stale_run_or_attempt_is_not_reusable(self):
        receipts = self.receipts()
        for key, value in [('GITHUB_RUN_ID', '101'), ('GITHUB_RUN_ATTEMPT', '2')]:
            with patch.dict(os.environ, {key: value}), self.assertRaises(runner.ContractError):
                runner.verify(self.root, receipts)

    def test_changed_source_after_success_is_not_reusable(self):
        receipts = self.receipts()
        (self.root / 'app/lib/main.dart').write_text('// another revision\n')
        with self.assertRaises(runner.ContractError):
            runner.verify(self.root, receipts)

    def test_different_checkout_is_not_reusable(self):
        receipts = self.receipts()
        with patch.object(runner, 'git_head', return_value='b' * 40), patch.dict(os.environ, {'GITHUB_SHA': 'b' * 40}), self.assertRaises(runner.ContractError):
            runner.verify(self.root, receipts)

    def test_no_filter_or_timeout_forwarding_arguments_are_accepted(self):
        for flag in ['--name', '--tags', '--exclude-tags', '--fail-fast', '--run-skipped', '--total-shards', '--timeout']:
            with self.subTest(flag=flag), self.assertRaises(SystemExit):
                runner.main(['run', '--shard-index', '0', '--receipt', str(self.root / 'filtered.json'), flag, 'value'])

    def test_missing_truncated_malformed_duplicate_or_foreign_report_never_succeeds(self):
        for mode in ['missing', 'truncated', 'malformed', 'duplicate', 'foreign', 'missing_start', 'wrong_protocol', 'all_hidden', 'source_change_truncated']:
            with self.subTest(mode=mode):
                result, receipt = self.execute(mode=mode, name=mode + '.json')
                self.assertNotEqual(result, 0)
                self.assertEqual(receipt['status'], 'failed')
                self.assertIsNone(receipt['execution'])
                self.assertEqual(receipt['sources_unchanged'], mode != 'source_change_truncated')
                self.assertTrue((self.root / 'receipts' / (mode + '.before.json')).is_file())
                self.assertTrue((self.root / 'receipts' / (mode + '.after.json')).is_file())

    def test_subprocess_failure_preserves_exact_exit_even_with_successful_report(self):
        result, receipt = self.execute(mode='process_fail')
        self.assertEqual(result, 23)
        self.assertEqual(receipt['process_exit_code'], 23)
        self.assertEqual(receipt['status'], 'failed')
        self.assertTrue(receipt['execution']['terminal_success'])

    def test_assertion_failure_records_actual_failure_and_no_ready_receipt(self):
        result, receipt = self.execute(mode='failure')
        self.assertEqual(result, 1)
        self.assertEqual(receipt['execution']['failed'], 3)
        self.assertEqual(receipt['execution']['passed'], 0)
        self.assertFalse(receipt['execution']['terminal_success'])
        self.assertEqual(receipt['status'], 'failed')

    def test_source_mutation_during_child_execution_invalidates_receipt(self):
        result, receipt = self.execute(mode='source_change')
        self.assertNotEqual(result, 0)
        self.assertFalse(receipt['sources_unchanged'])
        self.assertEqual(receipt['status'], 'failed')

    def test_unexecuted_or_extra_file_cannot_be_hidden_in_success_receipt(self):
        receipts = self.receipts()
        for key in ['selected_files', 'observed_files']:
            changed = copy.deepcopy(receipts)
            target = changed[0] if key == 'selected_files' else changed[0]['execution']
            target[key] = target[key][1:]
            with self.assertRaises(runner.ContractError):
                runner.verify(self.root, changed)

    def test_static_build_failure_prevents_green_union(self):
        receipts = self.receipts()
        with patch.dict(os.environ, {'FLUTTER_TEST_JOB_RESULT': 'success', 'FLUTTER_STATIC_JOB_RESULT': 'failure'}), self.assertRaises(runner.ContractError):
            runner.verify(self.root, receipts, require_job_results=True)
        with patch.dict(os.environ, {'FLUTTER_TEST_JOB_RESULT': 'success', 'FLUTTER_STATIC_JOB_RESULT': 'success'}):
            self.assertEqual(runner.verify(self.root, receipts, require_job_results=True)['status'], 'passed')

    def test_checkout_commit_must_match_github_source(self):
        with patch.dict(os.environ, {'GITHUB_SHA': 'b' * 40}), self.assertRaises(runner.ContractError):
            runner.snapshot(self.root)

    def test_query_selector_paths_or_symlink_test_inputs_fail_closed(self):
        for name in ['../x_test.dart', '/x_test.dart', 'app/test/x_test.dart?name=one', 'app/test/x_test.dart#line', 'app//test/x_test.dart']:
            with self.subTest(name=name), self.assertRaises(runner.ContractError):
                runner.relative(name)
        (self.root / 'app/test/alias_test.dart').symlink_to(self.root / 'app/test/a_test.dart')
        with self.assertRaises(runner.ContractError):
            runner.snapshot(self.root)

    def test_missing_or_truncated_environment_receipts_fail_cli_without_green_output(self):
        target = self.root / 'verify.json'
        with patch.dict(os.environ, {'FLUTTER_RECEIPT_0': '{}', 'FLUTTER_RECEIPT_1': '{}', 'FLUTTER_RECEIPT_2': '{truncated'}):
            self.assertNotEqual(runner.main(['--root', str(self.root), 'verify', '--from-env', '--receipt', str(target)]), 0)
        self.assertFalse(target.exists())

    def test_current_scale_full_290_files_three_outputs_fit_existing_transport_limits(self):
        for index in range(283):
            path = self.root / 'app/test' / f'scale_{index:03d}_test.dart'
            path.write_text('// artificial transport scale fixture\n')
            self.tracked.append(path.relative_to(self.root).as_posix())
        output = self.root / 'scale-output'
        for index in range(3):
            self.assertEqual(runner.run(self.root, index, 3, self.root / f'scale-{index}.json', str(self.fake), output), 0)
        lines = output.read_text().splitlines()
        # GitHub documents UTF-16 job output accounting. Keep the complete
        # receipts well within the existing1MB allowance, without truncation.
        self.assertLess(len(output.read_text().encode('utf-16-le')), 1_000_000)
        self.assertTrue(all(len(line.encode()) < 128_000 for line in lines))
        receipts = [json.loads(line.split('=', 1)[1]) for line in lines]
        complete = runner.verify(self.root, receipts)
        self.assertEqual((complete['all_files'], complete['passed'], complete['skipped']), (290, 290, 290))

    def test_workflow_keeps_exact_matrix_static_job_and_existing_pinned_actions(self):
        text = (SCRIPT.parents[1] / '.github/workflows/checks.yml').read_text()
        self.assertIn('name: flutter-test-${{ matrix.shard }}', text)
        self.assertIn('needs: [flutter_tests, flutter_static]', text)
        self.assertIn('    name: flutter\n', text)
        self.assertIn('    strategy:\n      fail-fast: false\n      matrix:\n        shard: [0, 1, 2]', text)
        self.assertEqual(text.count('run: flutter analyze --no-pub'), 1)
        self.assertEqual(text.count('run: flutter build web --release --no-pub --no-web-resources-cdn --csp'), 1)
        self.assertNotIn('continue-on-error', text)
        self.assertNotIn('--run-skipped', text)
        self.assertIn('--require-job-results', text)
        for line in text.splitlines():
            if 'uses:' in line:
                self.assertRegex(line, r'@(3d3c42e5aac5ba805825da76410c181273ba90b1|5fda3b95a4ea91299a34e894583c3862153e4b97) ')

    def test_unique_github_output_names_round_trip_without_shell_or_multiline_injection(self):
        output = self.root / 'github-output'
        for index in range(3):
            target = self.root / 'receipts' / f'export-{index}.json'
            self.assertEqual(runner.run(self.root, index, 3, target, str(self.fake), output), 0)
        lines = output.read_text().splitlines()
        self.assertEqual([line.split('=', 1)[0] for line in lines], ['receipt_0', 'receipt_1', 'receipt_2'])
        receipts = [json.loads(line.split('=', 1)[1]) for line in lines]
        self.assertEqual(runner.verify(self.root, receipts)['all_files'], 7)


if __name__ == '__main__':
    unittest.main()
