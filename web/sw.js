'use strict';

// Silly Soup's service worker.
//
// Flutter's own service worker is now a no-op that unregisters itself, so an
// app that has to keep working when the nursery wifi drops needs its own.
//
// Strategy:
//   * the page itself is network-first, so a new deploy is picked up as soon
//     as there is a network, and falls back to the cached shell when there
//     is not;
//   * everything else is cache-first, because the cache is scoped to one
//     build and cannot serve a stale asset against a fresh index.html;
//   * after the app has booted, the page tells the worker which resources it
//     actually loaded and those are cached too. That is what makes the very
//     first visit enough — rather than guessing at build time which renderer
//     this particular browser will pick out of the 48MB of alternatives.

// Replaced at build time with the commit SHA. A new build gets a new cache,
// and the old one is deleted on activate, so index.html and main.dart.wasm
// can never come from different builds.
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

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      // One bad URL must not fail the whole install.
      await Promise.all(
        SHELL.map((url) => cache.add(url).catch(() => undefined)),
      );
      await self.skipWaiting();
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
  if (!data || data.type !== 'warm' || !Array.isArray(data.urls)) return;

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
          await cache.add(url).catch(() => undefined);
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

  if (request.mode === 'navigate') {
    event.respondWith(
      (async () => {
        try {
          const response = await fetch(request);
          await put(request, response.clone());
          return response;
        } catch (error) {
          const cache = await caches.open(CACHE);
          const cached =
            (await cache.match(request)) ||
            (await cache.match('index.html')) ||
            (await cache.match('./'));
          if (cached) return cached;
          throw error;
        }
      })(),
    );
    return;
  }

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(request);
      if (cached) return cached;
      const response = await fetch(request);
      await put(request, response.clone());
      return response;
    })(),
  );
});

async function put(request, response) {
  if (!response || response.status !== 200 || response.type !== 'basic') return;
  const cache = await caches.open(CACHE);
  await cache.put(request, response);
}
