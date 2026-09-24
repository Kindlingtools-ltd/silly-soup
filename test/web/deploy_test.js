// The two things outside the app code that cache busting depends on.
//
// Neither shows up in a browser until it is already wrong in production, and
// both are one careless edit away from silently undoing the rest of this.
//
// Run with `bun test test/web`.

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

function read(path) {
  return readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
}

describe('the Cloudflare cache headers', () => {
  const headers = read('web/_headers');

  const policies = headers
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.toLowerCase().startsWith('cache-control:'))
    .map((line) => line.slice('cache-control:'.length).trim().toLowerCase());

  test('something is actually said about caching', () => {
    expect(policies.length).toBeGreaterThan(0);
  });

  test('every rule requires a fresh check before a stored copy is reused', () => {
    // Flutter's web output carries no content hashes: every build publishes
    // the same main.dart.wasm URL as the last one. A stored copy that may be
    // reused without asking is therefore a tablet stuck on an old build until
    // the browser happens to evict it.
    for (const policy of policies) {
      expect(policy).toContain('max-age=0');
      expect(policy).not.toContain('immutable');
    }
  });

  test('it ships from web/, which is what Cloudflare Pages reads', () => {
    // Anywhere else and Pages never sees it. `_redirects` is already proof
    // this is the right place.
    expect(read('web/_redirects')).toBeTruthy();
  });
});

describe('the build stamp in CI', () => {
  const workflow = read('.github/workflows/build.yml');

  test('the placeholder is substituted and then checked', () => {
    // Once to replace it, once to fail the build if the replacement missed.
    // An unstamped worker gives every build one shared cache and never
    // updates, which is the failure this whole change is about.
    const mentions = workflow.match(/__BUILD_ID__/g) ?? [];

    expect(mentions.length).toBeGreaterThanOrEqual(2);
  });

  test('the commit is compiled into the app so a grown-up can read it back', () => {
    expect(workflow).toContain('--dart-define=BUILD_ID=');
  });
});
