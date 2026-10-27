import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from release_policy import metadata, verified_candidate


class ReleasePolicyTest(unittest.TestCase):
    def test_candidates_keep_numeric_app_version(self):
        for suffix in ['pre.1', 'beta.2', 'rc.3', 'alpha.1']:
            result = metadata('v1.2.3-' + suffix, 'version: 1.2.3+64\n')
            self.assertEqual(result['name'], '1.2.3')
            self.assertEqual(result['code'], '64')
            self.assertTrue(result['prerelease'])
        self.assertFalse(metadata('v1.2.3', 'version: 1.2.3+64')['prerelease'])

    def test_rejects_mismatched_and_malformed_tags(self):
        for tag in ['v1.2.4', 'v1.2.3-rc', 'v1.2.3-rc.0', 'v1.2.3-rc.1\nname=bad']:
            with self.assertRaises(ValueError):
                metadata(tag, 'version: 1.2.3+64')
        with self.assertRaises(ValueError):
            metadata('v1.2.3-rc.1', 'version: 1.2.3-rc.1+64')

    def fixture(self, status='completed', conclusion='success', commit='head', assets=True):
        files = ['DawnMesh-1.2.3-release.' + ext for ext in ['apk', 'aab']]
        files += [f + '.sha256' for f in files[:]]
        release = {'tag_name': 'v1.2.3-rc.1', 'draft': False, 'prerelease': True,
                   'assets': [{'name': f, 'size': 1} for f in files] if assets else []}
        def get(path):
            if '/releases?' in path:
                return [release]
            if '/commits/' in path:
                return {'sha': commit}
            return {'workflow_runs': [{'id': 1, 'head_branch': 'v1.2.3-rc.1',
                    'name': 'Android release', 'status': status, 'conclusion': conclusion}]}
        return get

    def verify(self, get):
        return verified_candidate(metadata('v1.2.3', 'version: 1.2.3+64'),
                                  'owner/repo', 'head', 'Android release', 'android', get)

    def test_promotes_only_verified_same_commit(self):
        self.assertEqual(self.verify(self.fixture()), 'v1.2.3-rc.1')
        for params in [dict(commit='other'), dict(status='in_progress'),
                       dict(conclusion='failure'), dict(assets=False)]:
            with self.assertRaises(ValueError):
                self.verify(self.fixture(**params))

    def test_latest_failed_rerun_cannot_use_an_older_success(self):
        get = self.fixture()
        def rerun(path):
            result = get(path)
            if 'workflow_runs' in result:
                old = result['workflow_runs'][0]
                result['workflow_runs'].insert(0, {**old, 'id': 2, 'conclusion': 'failure'})
            return result
        with self.assertRaises(ValueError):
            self.verify(rerun)

    def test_ios_requires_app_and_checksum(self):
        get = self.fixture()
        def ios(path):
            result = get(path)
            if '/releases?' in path:
                result[0]['assets'] = [{'name': 'DawnMeshIOS-1.2.3-' + variant + suffix,
                                        'size': 1} for variant in ['unsigned.app.zip', 'wifi-aware-unsigned.app.zip']
                                       for suffix in ['', '.sha256']]
            if 'workflow_runs' in result:
                result['workflow_runs'][0]['name'] = 'iOS build and protocol checks'
            return result
        self.assertEqual(verified_candidate(metadata('v1.2.3', 'version: 1.2.3+64'),
            'owner/repo', 'head', 'iOS build and protocol checks', 'ios', ios), 'v1.2.3-rc.1')
        def missing_aware(path):
            result = ios(path)
            if '/releases?' in path:
                result[0]['assets'] = [a for a in result[0]['assets'] if 'wifi-aware' not in a['name']]
            return result
        with self.assertRaises(ValueError):
            verified_candidate(metadata('v1.2.3', 'version: 1.2.3+64'),
                'owner/repo', 'head', 'iOS build and protocol checks', 'ios', missing_aware)



if __name__ == '__main__':
    unittest.main()
