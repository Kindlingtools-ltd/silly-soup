/// Dismisses the HTML boot splash in web/index.html.
///
/// The splash is painted by the page itself so that something is on screen
/// while the engine downloads. Flutter has to be the one to take it away:
/// only the app knows when the sound bank and the adult's settings are in and
/// a real frame has been drawn, and hiding it any earlier would show a blank
/// scaffold instead.
///
/// A no-op off the web, where there is no splash to dismiss.
library;

export 'boot_splash_stub.dart'
    if (dart.library.js_interop) 'boot_splash_web.dart';
