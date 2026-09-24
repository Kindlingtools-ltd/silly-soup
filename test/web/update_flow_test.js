// The page half of cache busting, from web/flutter_bootstrap.js.
//
// sw.js will not replace itself unasked, so this code decides when a nursery
// swaps builds. It has to get two opposite things right: never leave a tablet
// on an old build, and never restart the app under a child who is halfway
// through a soup. Both failures are invisible in review and obvious in a
// classroom, so the decision runs here against a fake browser.
//
// Run with `bun test test/web`.

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';

const SOURCE = readFileSync(
  new URL('../../web/flutter_bootstrap.js', import.meta.url),
  'utf8',
)
  // Flutter substitutes these at build time; neither has anything to do with
  // the update flow.
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '');

const STARTUP_MS = 8000;

function eventTarget(properties = {}) {
  const listeners = new Map();
  return Object.assign(
    {
      addEventListener(type, handler) {
        if (!listeners.has(type)) listeners.set(type, []);
        listeners.get(type).push(handler);
      },
      removeEventListener(type, handler) {
        const current = listeners.get(type) ?? [];
        listeners.set(
          type,
          current.filter((entry) => entry !== handler),
        );
      },
      dispatch(type) {
        for (const handler of [...(listeners.get(type) ?? [])]) handler();
      },
    },
    properties,
  );
}

function fakeWorker(name, messages) {
  const worker = eventTarget({
    name,
    state: 'installing',
    postMessage(message) {
      messages.push({ to: name, message });
    },
  });
  worker.reach = (state) => {
    worker.state = state;
    worker.dispatch('statechange');
  };
  return worker;
}

/// Boots web/flutter_bootstrap.js against a fake browser.
///
/// `hasController` is the thing that distinguishes a first visit — where the
/// worker claiming the page is normal and must not reload it — from a return
/// visit, where a change of controller means a new build took over.
function loadPage({ hasController = true, priorReloads = 0 } = {}) {
  const messages = [];
  const state = { now: 1_000_000, reloads: 0, updateChecks: 0, intervals: [] };

  const registration = eventTarget({
    installing: null,
    waiting: null,
    active: {},
    update() {
      state.updateChecks += 1;
      return Promise.resolve();
    },
  });

  const serviceWorker = eventTarget({
    controller: hasController ? { name: 'previous' } : null,
    registerOptions: null,
    register(url, options) {
      serviceWorker.registeredUrl = url;
      serviceWorker.registerOptions = options;
      return Promise.resolve(registration);
    },
    ready: Promise.resolve(registration),
  });

  const document = eventTarget({ visibilityState: 'visible' });
  const navigator = { serviceWorker };

  const storage = new Map([
    ['silly-soup-update-reloads', String(priorReloads)],
  ]);
  const sessionStorage = {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
  };

  const location = {
    href: 'https://silly-soup.example.com/',
    reload() {
      state.reloads += 1;
    },
  };

  const window = eventTarget({ location });
  const fakeDate = { now: () => state.now };

  new Function(
    'window',
    'document',
    'navigator',
    'location',
    'performance',
    'sessionStorage',
    'setInterval',
    'setTimeout',
    'console',
    'Date',
    '_flutter',
    SOURCE,
  )(
    window,
    document,
    navigator,
    location,
    { getEntriesByType: () => [] },
    sessionStorage,
    (handler) => state.intervals.push(handler),
    () => undefined,
    { warn: () => undefined },
    fakeDate,
    { loader: { load: () => undefined } },
  );

  return {
    state,
    messages,
    registration,
    serviceWorker,
    document,
    window,
    storage,
    skipWaitingSent: () =>
      messages.filter((entry) => entry.message.type === 'skip-waiting'),
    /// Fires `load` and lets the registration promise chain settle.
    async start() {
      window.dispatch('load');
      await Bun.sleep(0);
      await Bun.sleep(0);
    },
    /// A new build finishes installing behind the running page.
    async installUpdate() {
      const next = fakeWorker('next', messages);
      registration.installing = next;
      registration.dispatch('updatefound');
      registration.waiting = next;
      next.reach('installed');
      await Bun.sleep(0);
      return next;
    },
  };
}

describe('registering', () => {
  test('the worker script is never answered from a cache', async () => {
    // It is the only thing that tells the browser a new build exists, so a
    // cached copy of it is a nursery stuck on an old app.
    const page = loadPage();

    await page.start();

    expect(page.serviceWorker.registeredUrl).toBe('sw.js');
    expect(page.serviceWorker.registerOptions).toEqual({
      updateViaCache: 'none',
    });
  });

  test('a page left open is still asked to check now and then', async () => {
    // A tablet in a nursery can sit on the same page for days without ever
    // navigating, and navigation is the only thing that would otherwise check.
    const page = loadPage();
    await page.start();

    expect(page.state.intervals).toHaveLength(1);
    page.state.intervals[0]();
    expect(page.state.updateChecks).toBe(1);
  });

  test('coming back to the tab checks for a new build', async () => {
    const page = loadPage();
    await page.start();

    page.document.visibilityState = 'visible';
    page.document.dispatch('visibilitychange');

    expect(page.state.updateChecks).toBe(1);
  });
});

describe('taking a new build', () => {
  test('one that arrives before the child touches anything is taken at once', async () => {
    const page = loadPage();
    await page.start();

    await page.installUpdate();

    expect(page.skipWaitingSent()).toHaveLength(1);
  });

  test('one left waiting by an earlier visit is taken on the next load', async () => {
    // This is the case that makes a reload enough: the build was deferred
    // last time, and is picked up before the child starts anything.
    const page = loadPage();
    page.registration.waiting = fakeWorker('waiting', page.messages);

    await page.start();

    expect(page.skipWaitingSent()).toHaveLength(1);
  });

  test('swapping ends in exactly one reload', async () => {
    const page = loadPage();
    await page.start();
    await page.installUpdate();

    page.serviceWorker.dispatch('controllerchange');
    page.serviceWorker.dispatch('controllerchange');

    expect(page.state.reloads).toBe(1);
  });
});

describe('not interrupting a child', () => {
  test('a build arriving mid-soup waits', async () => {
    const page = loadPage();
    await page.start();
    page.document.dispatch('pointerdown');

    await page.installUpdate();

    expect(page.skipWaitingSent()).toHaveLength(0);
  });

  test('and is taken when the tablet is put down', async () => {
    const page = loadPage();
    await page.start();
    page.document.dispatch('pointerdown');
    await page.installUpdate();

    page.document.visibilityState = 'hidden';
    page.document.dispatch('visibilitychange');

    expect(page.skipWaitingSent()).toHaveLength(1);
  });

  test('a page that has been up a while is treated as in use', async () => {
    // Nobody has touched it, but the app may be reciting a soup out loud.
    const page = loadPage();
    await page.start();
    page.state.now += STARTUP_MS + 1;

    await page.installUpdate();

    expect(page.skipWaitingSent()).toHaveLength(0);
  });

  test('a hidden page is always a good moment', async () => {
    const page = loadPage();
    await page.start();
    page.document.dispatch('pointerdown');
    page.state.now += STARTUP_MS + 1;
    page.document.visibilityState = 'hidden';

    await page.installUpdate();

    expect(page.skipWaitingSent()).toHaveLength(1);
  });
});

describe('never restarting the app for nothing', () => {
  test('the first worker claiming a fresh visit does not reload', async () => {
    // Every first visit ends with a controllerchange. Reloading there would
    // restart the app in front of every new child.
    const page = loadPage({ hasController: false });
    await page.start();

    page.serviceWorker.dispatch('controllerchange');

    expect(page.state.reloads).toBe(0);
  });

  test('two builds behind one url cannot bounce a child between them', async () => {
    const page = loadPage({ priorReloads: 2 });
    await page.start();

    page.serviceWorker.dispatch('controllerchange');

    expect(page.state.reloads).toBe(0);
  });

  test('reloads are counted so the cap can be reached', async () => {
    const page = loadPage();
    await page.start();

    page.serviceWorker.dispatch('controllerchange');

    expect(page.storage.get('silly-soup-update-reloads')).toBe('1');
  });
});
