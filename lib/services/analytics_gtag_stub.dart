// Everywhere that is not the web build: there is no tag to talk to, so
// nothing is reported. Selected by the conditional import in
// `analytics_sink.dart`, which is what keeps `dart:js_interop` out of the
// VM build the tests run on.

void sendGtagEvent(String name, Map<String, Object> parameters) {
  // Deliberately empty.
}
