'use strict';

// Silly Soup's service worker.
//
// Flutter's own service worker is now a no-op that unregisters itself, so an
// app that has to keep working when the nursery wifi drops needs its own.
//
// Two jobs that pull in opposite directions: start instantly with no network,
// and never leave a nursery running last term's build. The shape that does
// both:
//
//   * Everything is served cache-first out of a cache named after the build,
//     the page included. A load is therefore always one whole build. Serving
//     the page network-first instead — what this file used to do — meant a
//     reload after a deploy fetched the new index.html while this worker was
//     still handing out the previous main.dart.wasm from its cache, so the
//     child got a mixed build, or more often the old one, and only the reload
//     after that came good.
//   * A new build is noticed because the browser re-fetches this file from the
//     network on every navigation, bypassing the HTTP cache. A new BUILD_ID
//     makes these bytes different, so every deploy produces an update.
//   * The new worker then WAITS. Taking over on its own would delete the cache
//     the running app is still reading from, mid-soup. The page decides when
//     the moment is right and sends `skip-waiting` — see flutter_bootstrap.js.
//   * Network fetches carry ?v=<build id>, so a caching proxy between the
//     nursery and Cloudflare cannot answer a request for the new build with
//     the old bytes. The response is stored under the plain URL, which is what
//     the app asks for.

// Replaced at build time with the commit SHA. .github/workflows/build.yml
// fails the build if this placeholder survives, because an unstamped worker
// would give every build the same cache and none of the above would happen.
const BUILD_ID = '__BUILD_ID__';
const CACHE = `silly-soup-${BUILD_ID}`;

// Enough to get as far as booting. The rest arrives via `warm`.
const SHELL = [
  'index.html',
  'flutter_bootstrap.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
];

/// The same URL, tagged with the build it is being fetched for.
function versioned(url) {
  const target = new URL(url, self.location.href);
  target.searchParams.set('v', BUILD_ID);
  return target.toString();
}

/// Fetch from the network under the versioned URL, store under the plain one.
async function cacheFresh(cache, url) {
  const response = await fetch(versioned(url));
  if (!response || response.status !== 200) return;
  await cache.put(new URL(url, self.location.href).toString(), response);
}

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // One bad URL must not fail the whole install.
      await Promise.all(
        SHELL.map((url) => cacheFresh(cache, url).catch(() => undefined)),
      );

      // Nothing is running yet on a first visit, so there is nobody to
      // interrupt and waiting would only leave the visit uncached. An update,
      // on the other hand, waits to be invited: `self.registration.active` is
      // the worker currently serving a child.
      if (!self.registration.active) await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name.startsWith('silly-soup-') && name !== CACHE)
          .map((name) => caches.delete(name)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (!data) return;

  // The page has decided this is a good moment to swap builds.
  if (data.type === 'skip-waiting') {
    event.waitUntil(self.skipWaiting());
    return;
  }

  // What this browser actually downloaded. Which renderer and which bundle
  // that is depends on the browser, so the page is the only thing that knows.
  if (data.type !== 'warm' || !Array.isArray(data.urls)) return;

  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      const wanted = data.urls.filter((url) => {
        try {
          return new URL(url, self.location.href).origin === self.location.origin;
        } catch (error) {
          return false;
        }
      });
      await Promise.all(
        wanted.map(async (url) => {
          if (await cache.match(url)) return;
          await cacheFresh(cache, url).catch(() => undefined);
        }),
      );
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  let url;
  try {
    url = new URL(request.url);
  } catch (error) {
    return;
  }
  if (url.origin !== self.location.origin) return;

  // Any route is the same single page, and it must be THIS build's copy of it
  // — the one whose bundle is in this cache. The network is the fallback, not
  // the first choice; a newer index.html reaches the child by way of a new
  // worker, never by being dropped into an older one's cache.
  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        const cache = await caches.open(CACHE);
        const cached = await cache.match('index.html');
        if (cached) return cached;
        return fetch(request);
      })(),
    );
    return;
  }

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(request);
      if (cached) return cached;

      const response = await fetch(versioned(request.url));
      // 200 and not merely ok: a 206 for a seeked audio clip is half a file,
      // and the Cache API rejects it anyway.
      if (response && response.status === 200) {
        await cache.put(request.url, response.clone());
      }
      return response;
    })(),
  );
});
