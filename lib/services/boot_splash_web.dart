import 'dart:js_interop';

/// Defined unconditionally in web/index.html, so this is always callable.
@JS('sillySoupBootSplashDone')
external void _bootSplashDone();

/// Fades out the HTML splash and removes it from the layout.
///
/// Safe to call more than once — the page ignores repeat calls.
void dismissBootSplash() => _bootSplashDone();
