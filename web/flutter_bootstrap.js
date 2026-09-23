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

if ('serviceWorker' in navigator) {
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').then(function () {
      return navigator.serviceWorker.ready;
    }).then(function (registration) {
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
    }).catch(function (error) {
      console.warn('Silly Soup: offline cache unavailable', error);
    });
  });
}
