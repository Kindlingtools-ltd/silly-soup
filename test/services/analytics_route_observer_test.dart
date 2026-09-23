import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/services/services.dart';

Route<void> route(String? name) => MaterialPageRoute<void>(
  settings: RouteSettings(name: name),
  builder: (_) => const SizedBox.shrink(),
);

void main() {
  late RecordingAnalyticsSink sink;
  late AnalyticsRouteObserver observer;

  setUp(() {
    sink = RecordingAnalyticsSink();
    observer = AnalyticsRouteObserver(AnalyticsService(sink: sink));
  });

  List<Object?> screens() => [
    for (final event in sink.events) event.parameters['screen_name'],
  ];

  test('the app\'s first route is reported as home', () {
    observer.didPush(route(AnalyticsRouteObserver.homeRoute), null);

    expect(sink.names, ['page_view']);
    expect(screens(), ['home']);
  });

  test('pushing a named route reports it', () {
    observer.didPush(route('soup'), route('/'));

    expect(screens(), ['soup']);
  });

  test('going back reports the screen returned to, not the one left', () {
    observer.didPop(route('soup'), route(AnalyticsRouteObserver.homeRoute));

    expect(screens(), ['home']);
  });

  test('an unnamed route — a dialog or a sheet — is not a screen', () {
    observer
      ..didPush(route(null), null)
      ..didPush(route(''), null);

    expect(sink.events, isEmpty);
  });

  test('a replaced route is reported', () {
    observer.didReplace(newRoute: route('soup'), oldRoute: route('/'));

    expect(screens(), ['soup']);
  });
}
