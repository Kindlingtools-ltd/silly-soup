import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Drives one soup, from meeting the sound to the silly tasting.
///
/// The chef's turn is a timed sequence, so every step checks that it is still
/// the current soup before touching state: a child who backs out mid-way
/// must not be talked at by a chef from the soup before.
class SoupProvider extends ChangeNotifier {
  SoupProvider({
    required AudioService audio,
    AnalyticsService? analytics,
    Random? random,
    DateTime Function()? now,
  })
    // The lint wants `this._audio`, but Dart does not allow a private name as
    // a named parameter, so the field is assigned the long way round.
    // ignore: prefer_initializing_formals
    : _audio = audio,
       _analytics = analytics ?? AnalyticsService(),
       _random = random ?? Random(),
       _now = now ?? DateTime.now;

  final AudioService _audio;
  final AnalyticsService _analytics;
  final Random _random;
  final DateTime Function() _now;

  SoupSession? _session;
  DateTime? _startedAt;
  String _chefLine = '';
  bool _isStirring = false;
  bool _isChefBusy = false;
  int _generation = 0;
  int _praiseCounter = 0;
  int _chefItemsShown = 0;

  SoupSession? get session => _session;

  /// What the chef is saying right now, shown in the speech bubble.
  String get chefLine => _chefLine;

  bool get isStirring => _isStirring;

  /// True while the chef is modelling, so the shelf stays out of reach.
  bool get isChefBusy => _isChefBusy;

  /// How much of the chef's soup has gone in so far, so the pot can fill up
  /// in step with what the chef is saying.
  int get chefItemsShown => _chefItemsShown;

  bool get hasSession => _session != null;

  /// Pace: a whiteboard session is adult-led, so nothing advances on a timer.
  bool adultPaced = false;

  /// Shorter, flatter animation when the device or the adult asks for it.
  bool reducedMotion = false;

  /// Start a new soup for [sound].
  void start({
    required PhonemeSound sound,
    required SoundBank bank,
    required AppSettings settings,
  }) {
    final generation = ++_generation;
    // "Make another soup?" restarts without leaving the screen, so the soup
    // being replaced is abandoned in exactly the way backing out is.
    _reportAbandonedSoup();
    _audio.interrupt();
    final candidates = bank.wordsFor(sound.id);

    final session = SoupSession(
      sound: sound,
      pantry: SoupService.buildPantry(
        sound: sound,
        candidates: candidates,
        size: settings.pantrySize,
        random: _random,
      ),
      chefSoup: SoupService.buildChefSoup(
        sound: sound,
        candidates: candidates,
        random: _random,
      ),
    );
    _session = session;
    _chefLine = 'My sound today is ${RecitalService.pureSound(sound)}.';
    _isChefBusy = false;
    _isStirring = false;
    _chefItemsShown = 0;
    _startedAt = _now();
    notifyListeners();

    _analytics.logSoupStarted(sound, pantrySize: session.pantry.length);
    _speakSound(generation, sound);
  }

  /// Say the sound again — the child can ask as often as they like.
  Future<void> repeatSound() async {
    final sound = _session?.sound;
    if (sound == null) return;
    _analytics.logSoundRepeated(sound);
    await _say(ChefScript.soundOfTheDay(sound));
  }

  /// The chef makes a soup first, so the child has seen it done.
  Future<void> runChefModelling() async {
    final session = _session;
    if (session == null || _isChefBusy) return;
    final generation = _generation;
    final sound = session.sound;

    _isChefBusy = true;
    _analytics.logChefModelled(sound);
    _update(session.withStage(SoupStage.chefModelling));
    await _say(ChefScript.watchMe);
    if (!_isCurrent(generation)) return;

    for (final word in session.chefSoup) {
      await _pause(const Duration(milliseconds: 700));
      if (!_isCurrent(generation)) return;
      // The item goes in as it is named, so the child sees the pot fill up
      // one thing at a time. Showing all three at once demonstrates nothing.
      _chefItemsShown++;
      notifyListeners();
      await _say(ChefScript.commentateOnItem(word, sound));
      if (!_isCurrent(generation)) return;
      await _stir(generation);
    }

    await _pause(const Duration(milliseconds: 600));
    if (!_isCurrent(generation)) return;
    await _say(ChefScript.reciteList(session.chefSoup, sound));
    if (!_isCurrent(generation)) return;

    await _pause(const Duration(milliseconds: 900));
    if (!_isCurrent(generation)) return;
    // On a whiteboard the adult decides when to hand over, using "My turn!".
    if (adultPaced) {
      _isChefBusy = false;
      notifyListeners();
      return;
    }
    beginChildsTurn();
  }

  /// Hand the pot over. From here nothing the child does is wrong.
  void beginChildsTurn() {
    final session = _session;
    if (session == null) return;
    _isChefBusy = false;
    _analytics.logChildsTurnStarted(session.sound);
    _update(session.withStage(SoupStage.childsTurn));
    _say(ChefScript.nowYou);
  }

  /// The child puts an item in. Always accepted, always celebrated.
  Future<void> addItem(SoupWord word) async {
    final session = _session;
    if (session == null || _isChefBusy) return;
    if (!session.pantry.contains(word)) return;
    final generation = _generation;
    final sound = session.sound;

    // The child's tap takes over from whatever the chef was mid-way through.
    await _audio.interrupt();
    final next = session.addToPot(word);
    _update(next);
    _analytics.logIngredientAdded(
      sound: sound,
      word: word,
      potSize: next.pot.length,
    );
    await _say(ChefScript.commentateOnItem(word, sound));
    if (!_isCurrent(generation)) return;

    await _stir(generation);
    if (!_isCurrent(generation)) return;

    final current = _session;
    if (current == null) return;
    await _say(ChefScript.reciteList(current.pot, sound));
    if (!_isCurrent(generation)) return;

    // Praise every few items rather than after each one, so it stays warm
    // rather than becoming wallpaper.
    if (current.pot.length % 3 == 0) {
      await _pause(const Duration(milliseconds: 500));
      if (!_isCurrent(generation)) return;
      await _praise();
    }
  }

  /// Take an item back out. Not something the core game asks for, but an
  /// adult undoing a mis-tap should not have to start the soup again.
  void removeItem(SoupWord word) {
    final session = _session;
    if (session == null) return;
    if (!session.pot.contains(word)) return;
    final next = session.removeFromPot(word);
    _analytics.logIngredientRemoved(
      sound: session.sound,
      word: word,
      potSize: next.pot.length,
    );
    _update(next);
  }

  /// Give the pot a stir on purpose.
  Future<void> stirOnDemand() {
    final session = _session;
    if (session != null) _analytics.logSoupStirred(session.sound);
    return _stir(_generation);
  }

  /// Finish: silly tasting, then "Make another soup?".
  Future<void> finish() async {
    final session = _session;
    if (session == null) return;
    final generation = _generation;

    _update(session.withStage(SoupStage.tasting));
    _analytics.logSoupFinished(
      sound: session.sound,
      ingredientCount: session.pot.length,
      duration: _elapsed(),
    );
    await _say(ChefScript.reciteFinishedSoup(session.pot, session.sound));
    if (!_isCurrent(generation)) return;

    await _pause(const Duration(milliseconds: 700));
    if (!_isCurrent(generation)) return;
    await _praise();
  }

  /// Leave the kitchen.
  void clear() {
    _reportAbandonedSoup();
    _generation++;
    _session = null;
    _startedAt = null;
    _chefLine = '';
    _isChefBusy = false;
    _isStirring = false;
    _chefItemsShown = 0;
    _audio.stop();
    notifyListeners();
  }

  /// A soup left before the tasting. Reported on the way out, whether that
  /// is backing out of the screen or starting a fresh soup over the top.
  void _reportAbandonedSoup() {
    final session = _session;
    if (session == null || session.stage == SoupStage.tasting) return;
    _analytics.logSoupAbandoned(
      sound: session.sound,
      stage: session.stage,
      ingredientCount: session.pot.length,
      duration: _elapsed(),
    );
  }

  /// Last line of defence for the abandonment signal.
  ///
  /// The screen calls [clear] on the way out, which is where a soup left
  /// half-made is normally reported. This catches the case where the provider
  /// is torn down without that happening; [clear] has already emptied the
  /// session by then, so a soup is never reported twice.
  @override
  void dispose() {
    _reportAbandonedSoup();
    _session = null;
    super.dispose();
  }

  Duration _elapsed() {
    final startedAt = _startedAt;
    return startedAt == null ? Duration.zero : _now().difference(startedAt);
  }

  Future<void> _praise() => _say(ChefScript.praise(_praiseCounter++));

  /// Put a line on screen and say it. The two are the same thing: the words
  /// the chef speaks are the words a watching adult reads out.
  Future<void> _say(ChefLine line) {
    _setChefLine(line.text);
    return _audio.say(line);
  }

  Future<void> _speakSound(int generation, PhonemeSound sound) async {
    await _audio.playSound(sound);
    if (!_isCurrent(generation)) return;
    if (sound.action.isEmpty) return;
    await _pause(const Duration(milliseconds: 500));
    if (!_isCurrent(generation)) return;
    await _say(ChefScript.soundAction(sound));
  }

  Future<void> _stir(int generation) async {
    _isStirring = true;
    notifyListeners();
    await _pause(const Duration(milliseconds: 800));
    if (!_isCurrent(generation)) return;
    _isStirring = false;
    notifyListeners();
  }

  /// A beat between steps.
  ///
  /// Adult-paced sessions keep these: skipping them made whiteboard mode
  /// *faster* than a normal one, which is the opposite of what it is for.
  /// What adult pacing changes is that the chef stops at the end of its turn
  /// and waits to be asked, rather than moving on by itself.
  Future<void> _pause(Duration duration) {
    final scaled = reducedMotion
        ? Duration(milliseconds: (duration.inMilliseconds * 0.4).round())
        : duration;
    return Future<void>.delayed(scaled);
  }

  bool _isCurrent(int generation) =>
      generation == _generation && _session != null;

  void _update(SoupSession session) {
    _session = session;
    notifyListeners();
  }

  void _setChefLine(String line) {
    _chefLine = line;
    notifyListeners();
  }
}
