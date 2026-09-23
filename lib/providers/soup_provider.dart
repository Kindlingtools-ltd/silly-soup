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
  SoupProvider({required AudioService audio, Random? random})
    // The lint wants `this._audio`, but Dart does not allow a private name as
    // a named parameter, so the field is assigned the long way round.
    // ignore: prefer_initializing_formals
    : _audio = audio,
      _random = random ?? Random();

  final AudioService _audio;
  final Random _random;

  SoupSession? _session;
  String _chefLine = '';
  bool _isStirring = false;
  bool _isChefBusy = false;
  int _generation = 0;
  int _praiseCounter = 0;

  SoupSession? get session => _session;

  /// What the chef is saying right now, shown in the speech bubble.
  String get chefLine => _chefLine;

  bool get isStirring => _isStirring;

  /// True while the chef is modelling, so the shelf stays out of reach.
  bool get isChefBusy => _isChefBusy;

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
    final candidates = bank.wordsFor(sound.id);

    _session = SoupSession(
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
    _chefLine = 'My sound today is ${RecitalService.pureSound(sound)}.';
    _isChefBusy = false;
    _isStirring = false;
    notifyListeners();

    _speakSound(generation, sound);
  }

  /// Say the sound again — the child can ask as often as they like.
  Future<void> repeatSound() async {
    final sound = _session?.sound;
    if (sound == null) return;
    _setChefLine('My sound today is ${RecitalService.pureSound(sound)}.');
    await _audio.playSound(sound);
  }

  /// The chef makes a soup first, so the child has seen it done.
  Future<void> runChefModelling() async {
    final session = _session;
    if (session == null || _isChefBusy) return;
    final generation = _generation;
    final sound = session.sound;

    _isChefBusy = true;
    _update(session.withStage(SoupStage.chefModelling));
    _setChefLine('Watch me make my silly soup!');
    await _audio.speak('Watch me make my silly soup!');
    if (!_isCurrent(generation)) return;

    for (final word in session.chefSoup) {
      await _pause(const Duration(milliseconds: 900));
      if (!_isCurrent(generation)) return;
      _setChefLine(RecitalService.commentateOnItem(word, sound));
      await _audio.playEmphasisedWord(word, sound);
      if (!_isCurrent(generation)) return;
      await _stir(generation);
    }

    await _pause(const Duration(milliseconds: 600));
    if (!_isCurrent(generation)) return;
    final recital = RecitalService.reciteList(session.chefSoup, sound);
    _setChefLine(recital);
    await _audio.speak(recital);
    if (!_isCurrent(generation)) return;

    await _pause(const Duration(milliseconds: 900));
    if (!_isCurrent(generation)) return;
    beginChildsTurn();
  }

  /// Hand the pot over. From here nothing the child does is wrong.
  void beginChildsTurn() {
    final session = _session;
    if (session == null) return;
    _isChefBusy = false;
    _update(session.withStage(SoupStage.childsTurn));
    _setChefLine('Now you make a silly soup!');
    _audio.speak('Now you make a silly soup!');
  }

  /// The child puts an item in. Always accepted, always celebrated.
  Future<void> addItem(SoupWord word) async {
    final session = _session;
    if (session == null || _isChefBusy) return;
    if (!session.pantry.contains(word)) return;
    final generation = _generation;
    final sound = session.sound;

    final next = session.addToPot(word);
    _update(next);
    _setChefLine(RecitalService.commentateOnItem(word, sound));
    await _audio.playEmphasisedWord(word, sound);
    if (!_isCurrent(generation)) return;

    await _stir(generation);
    if (!_isCurrent(generation)) return;

    final current = _session;
    if (current == null) return;
    final recital = RecitalService.reciteList(current.pot, sound);
    _setChefLine(recital);
    await _audio.speak(recital);
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
    _update(session.removeFromPot(word));
  }

  /// Give the pot a stir on purpose.
  Future<void> stirOnDemand() => _stir(_generation);

  /// Finish: silly tasting, then "Make another soup?".
  Future<void> finish() async {
    final session = _session;
    if (session == null) return;
    final generation = _generation;

    _update(session.withStage(SoupStage.tasting));
    final recital = RecitalService.reciteFinishedSoup(
      session.pot,
      session.sound,
    );
    _setChefLine(recital);
    await _audio.speak(recital);
    if (!_isCurrent(generation)) return;

    await _pause(const Duration(milliseconds: 700));
    if (!_isCurrent(generation)) return;
    await _praise();
  }

  /// Leave the kitchen.
  void clear() {
    _generation++;
    _session = null;
    _chefLine = '';
    _isChefBusy = false;
    _isStirring = false;
    _audio.stop();
    notifyListeners();
  }

  Future<void> _praise() async {
    final line = RecitalService.praise(_praiseCounter++);
    _setChefLine(line);
    await _audio.speak(line);
  }

  Future<void> _speakSound(int generation, PhonemeSound sound) async {
    await _audio.playSound(sound);
    if (!_isCurrent(generation)) return;
    if (sound.action.isEmpty) return;
    await _pause(const Duration(milliseconds: 500));
    if (!_isCurrent(generation)) return;
    _setChefLine(sound.action);
    await _audio.speak(sound.action);
  }

  Future<void> _stir(int generation) async {
    _isStirring = true;
    notifyListeners();
    await _pause(const Duration(milliseconds: 800));
    if (!_isCurrent(generation)) return;
    _isStirring = false;
    notifyListeners();
  }

  /// Wait, unless the adult is driving the session by hand.
  Future<void> _pause(Duration duration) {
    if (adultPaced) return Future<void>.value();
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
