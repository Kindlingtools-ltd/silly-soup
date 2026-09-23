import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// The web half of the analytics sink: hands one event to the `gtag.js` tag
// loaded by `web/index.html`.
//
// `dart:js_interop` rather than the older `dart:html`, because the app is
// built with `--wasm`. `dart.library.html` is false under dart2wasm, so a
// conditional import keyed on it would silently select the no-op stub and
// the app would report nothing at all from the build we actually ship.

void sendGtagEvent(String name, Map<String, Object> parameters) {
  // `gtag` is defined synchronously by the inline snippet in index.html, so
  // it is there even before googletagmanager.com has answered — and it is
  // absent only when the whole tag has been blocked or stripped.
  if (!globalContext.has('gtag')) return;
  _gtag('event'.toJS, name.toJS, parameters.jsify());
}

@JS('gtag')
external void _gtag(JSString command, JSString name, JSAny? parameters);
