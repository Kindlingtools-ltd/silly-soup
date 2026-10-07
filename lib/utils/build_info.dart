/// Which build of the app is running.
///
/// Stamped by CI with the commit being deployed, the same value the service
/// worker names its cache after. Two tablets showing different things is the
/// hard thing to diagnose about a cached app, and this is what makes it a
/// question a grown-up can answer out loud.
class BuildInfo {
  const BuildInfo._();

  /// Empty in a local `flutter run`, which has no deploy to identify.
  static const String buildId = String.fromEnvironment('BUILD_ID');

  static bool get isStamped => buildId.isNotEmpty;

  /// The short form, the way a commit is quoted in conversation.
  static String get shortBuildId =>
      buildId.length > 7 ? buildId.substring(0, 7) : buildId;
}
