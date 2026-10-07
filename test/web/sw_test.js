// What web/sw.js does, exercised rather than read.
//
// The worker decides which build a nursery is running, and every interesting
// case is a lifecycle event nobody watches happen: an update installing behind
// a child who is mid-soup, a stale cache being swept, a proxy sitting between
// the tablet and Cloudflare. So it runs here in a stand-in for the service
// worker global scope, with a fake Cache API and a fake network.
//
// Run with `bun test test/web`.

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const ORIGIN = 'https://silly-soup.example.com';
const SOURCE = readFileSync(new URL('../../web/sw.js', import.meta.url), 'utf8');

function absolute(resource) {
  const raw = typeof resource === 'string' ? resource : resource.url;
  return new URL(raw, `${ORIGIN}/`).toString();
}

class FakeCache {
  constructor() {
    this.entries = new Map();
  }

  async put(request, response) {
    this.entries.set(absolute(request), response);
  }

  async match(request) {
    return this.entries.get(absolute(request));
  }

  keys() {
    return [...this.entries.keys()];
  }
}

class FakeCacheStorage {
  constructor() {
    this.caches = new Map();
  }

  async open(name) {
    if (!this.caches.has(name)) this.caches.set(name, new FakeCache());
    return this.caches.get(name);
  }

  async keys() {
    return [...this.caches.keys()];
  }

  async delete(name) {
    return this.caches.delete(name);
  }
}

/// Loads web/sw.js into a fake global scope, stamped the way CI stamps it.
function loadWorker({ buildId = 'build1', updating = false, network } = {}) {
  const storage = new FakeCacheStorage();
  const requested = [];

  const scope = {
    location: { href: `${ORIGIN}/sw.js`, origin: ORIGIN },
    // During the install of an UPDATE this is the worker still serving a
    // child; on a first install there is nothing there.
    registration: { active: updating ? { id: 'previous' } : null },
    clients: {
      claimed: 0,
      async claim() {
        scope.clients.claimed += 1;
      },
    },
    skipWaitingCalls: 0,
    async skipWaiting() {
      scope.skipWaitingCalls += 1;
    },
    listeners: new Map(),
    addEventListener(type, handler) {
      if (!scope.listeners.has(type)) scope.listeners.set(type, []);
      scope.listeners.get(type).push(handler);
    },
  };

  const respond = network ?? ((url) => new Response(`bytes of ${url}`));
  const fakeFetch = async (resource) => {
    const url = typeof resource === 'string' ? resource : resource.url;
    requested.push(url);
    return respond(url);
  };

  // Exactly what CI does to build/web/sw.js before it is deployed.
  const stamped = SOURCE.replaceAll('__BUILD_ID__', buildId);
  new Function('self', 'caches', 'fetch', stamped)(scope, storage, fakeFetch);

  return { scope, storage, requested, cacheName: `silly-soup-${buildId}` };
}

/// Fires one event at the worker and waits for the work it signed up for.
async function dispatch(scope, type, event = {}) {
  const pending = [];
  let answer;
  event.waitUntil = (promise) => pending.push(promise);
  event.respondWith = (promise) => {
    answer = promise;
  };

  for (const handler of scope.listeners.get(type) ?? []) handler(event);
  await Promise.all(pending);
  return answer === undefined ? undefined : answer;
}

function request(url, { method = 'GET', mode = 'no-cors' } = {}) {
  return { url: absolute(url), method, mode };
}

async function installed(options = {}) {
  const worker = loadWorker(options);
  await dispatch(worker.scope, 'install');
  worker.requested.length = 0;
  return worker;
}

describe('the build stamp', () => {
  test('the placeholder CI replaces is still in the file', () => {
    // Without it `sed` in .github/workflows/build.yml is a no-op, every build
    // shares one cache, and no browser ever sees a new one.
    expect(SOURCE).toContain('__BUILD_ID__');
  });

  test('the cache is named after the build', async () => {
    const worker = await installed({ buildId: 'abc123' });

    expect(await worker.storage.keys()).toEqual(['silly-soup-abc123']);
  });
});

describe('installing', () => {
  test('a first visit caches the shell and takes over at once', async () => {
    const worker = loadWorker({ buildId: 'first' });

    await dispatch(worker.scope, 'install');

    const cache = await worker.storage.open('silly-soup-first');
    expect(cache.keys()).toContain(`${ORIGIN}/index.html`);
    expect(cache.keys()).toContain(`${ORIGIN}/flutter_bootstrap.js`);
    expect(cache.keys()).toContain(`${ORIGIN}/manifest.json`);
    // Nobody is playing yet, so there is nothing to interrupt.
    expect(worker.scope.skipWaitingCalls).toBe(1);
  });

  test('an update prepares itself but waits to be invited', async () => {
    const worker = loadWorker({ buildId: 'second', updating: true });

    await dispatch(worker.scope, 'install');

    // The cache is ready...
    const cache = await worker.storage.open('silly-soup-second');
    expect(cache.keys()).toContain(`${ORIGIN}/index.html`);
    // ...but taking over now would delete the cache a running soup is reading.
    expect(worker.scope.skipWaitingCalls).toBe(0);
  });

  test('the page can tell a waiting update that now is a good moment', async () => {
    const worker = loadWorker({ buildId: 'second', updating: true });
    await dispatch(worker.scope, 'install');

    await dispatch(worker.scope, 'message', { data: { type: 'skip-waiting' } });

    expect(worker.scope.skipWaitingCalls).toBe(1);
  });

  test('one unreachable shell file does not fail the whole install', async () => {
    const worker = loadWorker({
      buildId: 'patchy',
      network: (url) =>
        url.includes('favicon')
          ? Promise.reject(new Error('offline'))
          : new Response('ok'),
    });

    await dispatch(worker.scope, 'install');

    const cache = await worker.storage.open('silly-soup-patchy');
    expect(cache.keys()).toContain(`${ORIGIN}/index.html`);
    expect(cache.keys()).not.toContain(`${ORIGIN}/favicon.png`);
  });

  test('a shell file the server could not serve is not cached', async () => {
    const worker = loadWorker({
      buildId: 'broken',
      network: (url) =>
        url.includes('manifest')
          ? new Response('nope', { status: 404 })
          : new Response('ok'),
    });

    await dispatch(worker.scope, 'install');

    const cache = await worker.storage.open('silly-soup-broken');
    expect(cache.keys()).not.toContain(`${ORIGIN}/manifest.json`);
  });
});

describe('activating', () => {
  test('the previous build is swept and this one is kept', async () => {
    const worker = await installed({ buildId: 'new' });
    await worker.storage.open('silly-soup-old');
    await worker.storage.open('some-other-app');

    await dispatch(worker.scope, 'activate');

    expect(await worker.storage.keys()).toEqual([
      'silly-soup-new',
      'some-other-app',
    ]);
    expect(worker.scope.clients.claimed).toBe(1);
  });
});

describe('serving the page', () => {
  test('a reload gets this build\'s page, not whatever the network has', async () => {
    // The bug this replaced: the page was network-first, so a reload after a
    // deploy paired the new index.html with this cache's old bundle.
    const worker = await installed({ buildId: 'running' });

    const response = await dispatch(worker.scope, 'fetch', {
      request: request('/', { mode: 'navigate' }),
    });

    expect(await response.text()).toContain('index.html');
    expect(worker.requested).toEqual([]);
  });

  test('a deep link gets the same single page', async () => {
    const worker = await installed({ buildId: 'running' });

    const response = await dispatch(worker.scope, 'fetch', {
      request: request('/grown-ups', { mode: 'navigate' }),
    });

    expect(await response.text()).toContain('index.html');
  });

  test('with nothing cached yet the page comes from the network', async () => {
    const worker = loadWorker({ buildId: 'cold' });

    const response = await dispatch(worker.scope, 'fetch', {
      request: request('/', { mode: 'navigate' }),
    });

    expect(await response.text()).toContain('bytes of');
    expect(worker.requested).toEqual([`${ORIGIN}/`]);
  });
});

describe('serving assets', () => {
  test('a cached asset never touches the network', async () => {
    const worker = await installed({ buildId: 'warmed' });

    const response = await dispatch(worker.scope, 'fetch', {
      request: request('/flutter_bootstrap.js'),
    });

    expect(await response.text()).toContain('flutter_bootstrap.js');
    expect(worker.requested).toEqual([]);
  });

  test('a miss is fetched tagged with the build and stored untagged', async () => {
    // The tag is what stops a caching proxy answering the new build with the
    // bytes it kept for the old one. The app still asks for the plain URL.
    const worker = await installed({ buildId: 'tagged' });

    await dispatch(worker.scope, 'fetch', {
      request: request('/main.dart.wasm'),
    });

    expect(worker.requested).toEqual([`${ORIGIN}/main.dart.wasm?v=tagged`]);
    const cache = await worker.storage.open('silly-soup-tagged');
    expect(cache.keys()).toContain(`${ORIGIN}/main.dart.wasm`);
  });

  test('the shell is fetched tagged too', async () => {
    const worker = loadWorker({ buildId: 'tagged' });

    await dispatch(worker.scope, 'install');

    for (const url of worker.requested) {
      expect(url).toContain('?v=tagged');
    }
  });

  test('a partial response is served but not cached', async () => {
    const worker = await installed({
      buildId: 'seeking',
      network: () => new Response('half a clip', { status: 206 }),
    });

    const response = await dispatch(worker.scope, 'fetch', {
      request: request('/assets/assets/audio/words/banana.mp3'),
    });

    expect(response.status).toBe(206);
    const cache = await worker.storage.open('silly-soup-seeking');
    expect(cache.keys()).not.toContain(
      `${ORIGIN}/assets/assets/audio/words/banana.mp3`,
    );
  });

  test('another origin is left to the browser', async () => {
    const worker = await installed({ buildId: 'running' });

    const answer = await dispatch(worker.scope, 'fetch', {
      request: { url: 'https://www.googletagmanager.com/gtag/js', method: 'GET' },
    });

    expect(answer).toBeUndefined();
  });

  test('a POST is left to the browser', async () => {
    const worker = await installed({ buildId: 'running' });

    const answer = await dispatch(worker.scope, 'fetch', {
      request: request('/anything', { method: 'POST' }),
    });

    expect(answer).toBeUndefined();
  });
});

describe('warming', () => {
  test('what the page actually loaded is cached, tagged, under plain urls', async () => {
    const worker = await installed({ buildId: 'warm1' });

    await dispatch(worker.scope, 'message', {
      data: {
        type: 'warm',
        urls: [
          `${ORIGIN}/main.dart.wasm`,
          `${ORIGIN}/canvaskit/skwasm.wasm`,
          'https://www.googletagmanager.com/gtag/js',
        ],
      },
    });

    expect(worker.requested.sort()).toEqual([
      `${ORIGIN}/canvaskit/skwasm.wasm?v=warm1`,
      `${ORIGIN}/main.dart.wasm?v=warm1`,
    ]);
    const cache = await worker.storage.open('silly-soup-warm1');
    expect(cache.keys()).toContain(`${ORIGIN}/main.dart.wasm`);
  });

  test('something already cached is not fetched again', async () => {
    const worker = await installed({ buildId: 'warm2' });

    await dispatch(worker.scope, 'message', {
      data: { type: 'warm', urls: [`${ORIGIN}/index.html`] },
    });

    expect(worker.requested).toEqual([]);
  });

  test('a message from somewhere else is ignored', async () => {
    const worker = await installed({ buildId: 'warm3', updating: true });

    await dispatch(worker.scope, 'message', { data: null });
    await dispatch(worker.scope, 'message', { data: { type: 'something' } });
    await dispatch(worker.scope, 'message', { data: { type: 'warm' } });

    expect(worker.requested).toEqual([]);
    // Nothing here is an invitation to swap builds under a child.
    expect(worker.scope.skipWaitingCalls).toBe(0);
  });
});
