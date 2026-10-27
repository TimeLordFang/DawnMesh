#!/usr/bin/env python3
"""Validate numeric app versions, candidate tags and same-commit promotion."""
import argparse
import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def metadata(tag, pubspec):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', pubspec, re.M)
    if not match:
        raise ValueError('Use a numeric app version and integer build number in pubspec.yaml')
    name, code = match.groups()
    candidate = re.fullmatch(r'v' + re.escape(name) + r'-(pre|alpha|beta|rc)\.([1-9]\d*)', tag)
    if tag != 'v' + name and not candidate:
        raise ValueError(f'Tag must be v{name} or v{name}-pre/beta/rc.N; keep the app version numeric')
    return {'name': name, 'code': code, 'prerelease': bool(candidate), 'tag': tag}


def verified_candidate(meta, repo, head, workflow, platform, get):
    prefix = f'/repos/{repo}'
    releases = get(prefix + '/releases?per_page=100')
    pattern = re.compile(r'v' + re.escape(meta['name']) + r'-(pre|alpha|beta|rc)\.[1-9]\d*')
    suffixes = ['release.apk', 'release.aab'] if platform == 'android' else ['unsigned.app.zip', 'wifi-aware-unsigned.app.zip']
    app = 'DawnMesh' if platform == 'android' else 'DawnMeshIOS'
    required = {f'{app}-{meta["name"]}-{suffix}' for suffix in suffixes}
    required |= {name + '.sha256' for name in list(required)}
    for release in releases:
        tag = release['tag_name']
        if release.get('draft') or not release.get('prerelease') or not pattern.fullmatch(tag):
            continue
        commit = get(prefix + '/commits/' + urllib.parse.quote(tag, safe=''))['sha']
        if commit != head:
            continue
        assets = {a['name'] for a in release.get('assets', []) if a.get('size', 0) > 0}
        if not required.issubset(assets):
            raise ValueError(f'Candidate {tag} is missing required packages/checksums')
        runs = get(prefix + f'/actions/runs?head_sha={head}&per_page=100')['workflow_runs']
        runs = sorted((r for r in runs if r['head_branch'] == tag and r['name'] == workflow),
                      key=lambda r: r['id'], reverse=True)
        if not runs or runs[0]['status'] != 'completed' or runs[0]['conclusion'] != 'success':
            raise ValueError(f'The latest verification of candidate {tag} has not succeeded')
        return tag
    raise ValueError('No published, verified prerelease for this exact commit; validate an rc/beta first')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--pubspec', default='pubspec.yaml')
    parser.add_argument('--output')
    parser.add_argument('--verify-candidate', action='store_true')
    parser.add_argument('--workflow')
    parser.add_argument('--platform', choices=['android', 'ios'])
    args = parser.parse_args()
    meta = metadata(args.tag, Path(args.pubspec).read_text())
    if args.verify_candidate and not meta['prerelease']:
        token, repo = os.environ.get('GH_TOKEN'), os.environ.get('GITHUB_REPOSITORY')
        if not token or not repo or not args.workflow or not args.platform:
            raise ValueError('Promotion requires GH_TOKEN, GITHUB_REPOSITORY, workflow and platform')
        def get(path):
            req = urllib.request.Request('https://api.github.com' + path, headers={
                'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                'User-Agent': 'DawnMesh-release-policy'})
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
        meta['candidate'] = verified_candidate(meta, repo, head, args.workflow, args.platform, get)
    if args.output:
        with open(args.output, 'a') as output:
            for key, value in meta.items():
                output.write(f'{key}={str(value).lower() if isinstance(value, bool) else value}\n')
    print(json.dumps(meta))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, urllib.error.URLError) as error:
        raise SystemExit(f'Release policy: {error}')
