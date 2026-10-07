{{flutter_js}}
{{flutter_build_config}}

// Silly Soup serves its own engine.
//
// Left to itself, the loader builds the CanvasKit/skwasm URL from
// `engineRevision` and fetches ~1.2MB of renderer from
// www.gstatic.com/flutter-canvaskit on every cold start. That is wrong here
// for three separate reasons:
//
//   * privacy — PRIVACY.md promises no third-party request of any kind, and
//     this app is used by three-year-olds. A cross-origin fetch hands a
//     nursery's IP address to Google before the chef has said hello.
//   * offline — sw.js only caches same-origin responses (it cannot read an
//     opaque cross-origin one), so the renderer was never cached and the
//     installed PWA could not boot without a network.
//   * speed — a second origin means another DNS lookup and TLS handshake on
//     the critical path, and the renderer cannot share the connection
//     everything else is already using.
//
// `canvasKitBaseUrl` points it at the copy `flutter build web` already puts
// in build/web/canvaskit. `fontFallbackBaseUrl` does the same for the Noto
// fallback fonts the engine reaches for when a glyph is missing from Poppins
// — see web/fallback-fonts/README.md.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
    fontFallbackBaseUrl: 'fallback-fonts/',
  },
});

// The page half of cache busting.
//
// sw.js serves one whole build and will not replace itself unasked, because
// swapping mid-soup would pull the cache out from under a running app. That
// leaves the decision here, where the app's state actually is:
//
//   * a build that finished installing during an earlier visit is taken now,
//     before the child has started anything;
//   * a build that arrives while the app is idle is taken straight away;
//   * one that arrives mid-soup waits until the tablet is put down, or failing
//     that until the next load, which finds it still waiting.
//
// Whichever it is, the swap ends in exactly one reload, so a grown-up who
// reloads after a deploy gets the new build rather than the one after that.
(function () {
  if (!('serviceWorker' in navigator)) return;

  // How long after a load a swap still counts as "the app is starting" rather
  // than "a child is halfway through a soup".
  var STARTUP_MS = 8000;

  // A tablet in a nursery can sit on the same page for days without ever
  // navigating, which is the only thing that would otherwise check.
  var UPDATE_EVERY_MS = 30 * 60 * 1000;

  // Two different builds behind one URL — a rollout part way through — could
  // otherwise bounce a child between them.
  var MAX_RELOADS = 2;
  var RELOAD_KEY = 'silly-soup-update-reloads';

  // A `controllerchange` on a page that began with no controller is the first
  // install claiming us, not a new build. Reloading for that would restart the
  // app on every first visit.
  var hadController = !!navigator.serviceWorker.controller;

  var loadedAt = Date.now();
  var touched = false;
  document.addEventListener('pointerdown', function () { touched = true; },
                            { once: true, capture: true });

  function reloadCount(delta) {
    try {
      var n = parseInt(sessionStorage.getItem(RELOAD_KEY) || '0', 10) || 0;
      if (delta) sessionStorage.setItem(RELOAD_KEY, String(n + delta));
      return n;
    } catch (error) {
      return 0;
    }
  }

  var reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (!hadController || reloading) return;
    if (reloadCount(0) >= MAX_RELOADS) return;
    reloading = true;
    reloadCount(1);
    window.location.reload();
  });

  function nothingToLose() {
    if (document.visibilityState === 'hidden') return true;
    return !touched && Date.now() - loadedAt < STARTUP_MS;
  }

  function promote(registration) {
    if (!registration.waiting) return;
    if (nothingToLose()) {
      registration.waiting.postMessage({ type: 'skip-waiting' });
      return;
    }
    document.addEventListener('visibilitychange', function later() {
      if (document.visibilityState !== 'hidden') return;
      document.removeEventListener('visibilitychange', later);
      if (registration.waiting) {
        registration.waiting.postMessage({ type: 'skip-waiting' });
      }
    });
  }

  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' })
      .then(function (registration) {
        promote(registration);

        registration.addEventListener('updatefound', function () {
          var installing = registration.installing;
          if (!installing) return;
          installing.addEventListener('statechange', function () {
            if (installing.state === 'installed') promote(registration);
          });
        });

        function check() { registration.update().catch(function () {}); }
        setInterval(check, UPDATE_EVERY_MS);
        document.addEventListener('visibilitychange', function () {
          if (document.visibilityState === 'visible') check();
        });

        return navigator.serviceWorker.ready.then(function () {
          return registration;
        });
      })
      .then(function (registration) {
        // Tell the worker what this browser actually downloaded, so one visit
        // is enough to make the app work with no network afterwards. Which
        // renderer and which wasm bundle that is depends on the browser, so
        // the page is the only thing that knows.
        function warm() {
          var target = registration.active || navigator.serviceWorker.controller;
          if (!target) return;
          var urls = performance.getEntriesByType('resource')
            .map(function (entry) { return entry.name; })
            .concat([location.href]);
          target.postMessage({ type: 'warm', urls: urls });
        }
        warm();
        // The heavy assets land after first paint, so sweep up again shortly.
        setTimeout(warm, 5000);
      })
      .catch(function (error) {
        console.warn('Silly Soup: offline cache unavailable', error);
      });
  });
})();
