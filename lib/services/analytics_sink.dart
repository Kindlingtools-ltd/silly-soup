import 'package:flutter/foundation.dart';

import 'analytics_gtag_stub.dart'
    if (dart.library.js_interop) 'analytics_gtag_web.dart'
    as gtag;

/// Anything that can take an analytics event.
///
/// Pulled out behind an interface for the same reason the audio sink is: the
/// rules about *what* gets reported are worth testing, and they should be
/// testable without a browser, a tag, or a network.
abstract class AnalyticsSink {
  /// Send one event. Parameter values are strings, numbers or booleans — the
  /// only things GA4 accepts.
  void send(String name, Map<String, Object> parameters);
}

/// The real sink: Google Analytics 4, through the `gtag.js` tag in
/// `web/index.html`.
///
/// Web only. The conditional import above resolves to a no-op everywhere
/// else, so tests and the (not yet shipped) Android and iOS builds report
/// nothing at all rather than reporting into the void.
class GtagAnalyticsSink implements AnalyticsSink {
  const GtagAnalyticsSink();

  @override
  void send(String name, Map<String, Object> parameters) {
    try {
      gtag.sendGtagEvent(name, parameters);
    } catch (error) {
      // A blocked tag, an ad blocker, or a device that is offline. None of
      // those are the child's problem, so none of them surface.
      debugPrint('Silly Soup: could not report "$name" ($error)');
    }
  }
}

/// A sink that records what it was asked to report and sends nothing.
@visibleForTesting
class RecordingAnalyticsSink implements AnalyticsSink {
  final List<AnalyticsEvent> events = [];

  /// Event names in the order they were reported.
  List<String> get names => [for (final event in events) event.name];

  /// The first event called [name], or null when there was none.
  AnalyticsEvent? firstOf(String name) {
    for (final event in events) {
      if (event.name == name) return event;
    }
    return null;
  }

  /// Every event called [name], in order.
  List<AnalyticsEvent> allOf(String name) => [
    for (final event in events)
      if (event.name == name) event,
  ];

  @override
  void send(String name, Map<String, Object> parameters) {
    events.add(AnalyticsEvent(name, parameters));
  }
}

/// One reported event, kept so a test can assert on it.
@visibleForTesting
class AnalyticsEvent {
  const AnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;

  @override
  String toString() => 'AnalyticsEvent($name, $parameters)';
}
