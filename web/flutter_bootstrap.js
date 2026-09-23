{{flutter_js}}
{{flutter_build_config}}

// Loaded without `serviceWorkerSettings` on purpose. Flutter's own service
// worker only unregisters itself now, and registering it would evict ours at
// the same scope. Silly Soup ships web/sw.js instead — see that file.
_flutter.loader.load();

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
