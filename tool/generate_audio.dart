// Generates the recorded clips for Silly Soup with an x.ai voice model,
// through the Agent IAP proxy.
//
//   dart run tool/generate_audio.dart --dry-run    # what would be generated
//   dart run tool/generate_audio.dart              # generate what is missing
//   dart run tool/generate_audio.dart --force      # regenerate everything
//
// Clips already on disk are skipped: generating 88 files on every run would
// be slow, costly, and would churn the repo for no reason. The files are
// committed, so this is a one-off per clip.
//
// Credentials: none here. AGENT_IAM_TOKEN buys nothing except at the proxy,
// which attaches the real x.ai credential on the way out.

import 'dart:convert';
import 'dart:io';

const String bankPath = 'assets/data/sound_bank.json';
const String audioRoot = 'assets/audio';
const String songClip = 'assets/audio/song/silly_soup_song.mp3';

/// The default voice. British, because the children using this are in
/// England and the whole point is modelling the sound they should copy.
const String defaultVoice = 'Eve';
const String defaultModel = 'grok-tts';
const String language = 'en-GB';

class Clip {
  const Clip({
    required this.path,
    required this.kind,
    required this.subject,
    required this.text,
    this.instructions = '',
  });

  final String path;
  final String kind;
  final String subject;

  /// What the voice should say.
  final String text;

  /// How it should be said.
  final String instructions;

  bool get exists => File(path).existsSync();
}

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');
  final voice = _option(args, '--voice') ?? defaultVoice;
  final model = _option(args, '--model') ?? defaultModel;

  final bankFile = File(bankPath);
  if (!bankFile.existsSync()) {
    stderr.writeln('Could not find $bankPath. Run this from the project root.');
    exit(2);
  }

  final clips = _clips(
    json.decode(bankFile.readAsStringSync()) as Map<String, dynamic>,
  );
  final todo = force ? clips : clips.where((clip) => !clip.exists).toList();

  stdout.writeln(
    '${clips.length} clips, ${clips.length - todo.length} already on disk, '
    '${todo.length} to generate.',
  );

  if (dryRun) {
    for (final clip in todo) {
      stdout.writeln('  would generate ${clip.path}  <- "${clip.text}"');
    }
    return;
  }
  if (todo.isEmpty) return;

  final host = Platform.environment['AGENT_IAM_HOST'];
  final token = Platform.environment['AGENT_IAM_TOKEN'];
  if (host == null || token == null) {
    stderr.writeln(
      'AGENT_IAM_HOST and AGENT_IAM_TOKEN must be set. This tool only speaks '
      'to x.ai through the Agent IAP proxy; it never holds an API key.',
    );
    exit(2);
  }

  final client = HttpClient();
  var written = 0;
  var failed = 0;

  for (final clip in todo) {
    try {
      final bytes = await _synthesise(
        client: client,
        host: host,
        token: token,
        model: model,
        voice: voice,
        clip: clip,
      );
      await File(clip.path).parent.create(recursive: true);
      await File(clip.path).writeAsBytes(bytes);
      written++;
      stdout.writeln('  ✓ ${clip.path} (${bytes.length} bytes)');
    } catch (error) {
      failed++;
      stderr.writeln('  ✗ ${clip.path}: $error');
      // A 403 on the first clip means the account is not entitled, and the
      // other 87 will fail the same way. Stop rather than hammer it.
      if (written == 0 && failed >= 3) {
        stderr.writeln(
          '\nGiving up after three failures with nothing written.',
        );
        break;
      }
    }
  }

  client.close();
  stdout.writeln('\n$written written, $failed failed.');
  exit(failed == 0 ? 0 : 1);
}

Future<List<int>> _synthesise({
  required HttpClient client,
  required String host,
  required String token,
  required String model,
  required String voice,
  required Clip clip,
}) async {
  final uri = Uri.parse('http://$host/xai/v1/audio/speech');
  final request = await client.postUrl(uri);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.contentType = ContentType.json;
  request.write(
    json.encode({
      'model': model,
      'voice': voice,
      'input': clip.text,
      'language': language,
      'response_format': 'mp3',
      if (clip.instructions.isNotEmpty) 'instructions': clip.instructions,
    }),
  );

  final response = await request.close();
  if (response.statusCode != 200) {
    final body = await response.transform(utf8.decoder).join();
    throw HttpException('HTTP ${response.statusCode}: ${body.trim()}');
  }

  final bytes = <int>[];
  await for (final chunk in response) {
    bytes.addAll(chunk);
  }
  return bytes;
}

List<Clip> _clips(Map<String, dynamic> bank) {
  final sounds = (bank['sounds'] as List).cast<Map<String, dynamic>>();
  final words = (bank['words'] as List).cast<Map<String, dynamic>>();

  return [
    for (final sound in sounds)
      if ((sound['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${sound['audio']}',
          kind: 'phoneme',
          subject: '/${sound['id']}/',
          text: _pureSound(sound),
          // The single most important instruction in the whole app: a pure
          // sound with an added "uh" teaches children to say "suh" for /s/.
          instructions:
              'Speak in a warm British English accent for a nursery class. '
              'Say only the pure speech sound, with no vowel added on the end '
              '— "sss", never "suh". '
              '${sound['articulation'] == 'stop' ? 'Bounce it crisply three times.' : 'Hold the sound on smoothly.'}',
        ),
    for (final word in words)
      if ((word['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${word['audio']}',
          kind: 'word',
          subject: word['word'] as String,
          text: word['word'] as String,
          instructions:
              'Speak in a warm British English accent for a nursery class. '
              'Say the single word clearly and slowly, with Received '
              'Pronunciation vowels.',
        ),
    Clip(
      path: songClip,
      kind: 'song',
      subject: 'The Silly Soup Song',
      text: _songLyrics(),
      instructions:
          'A warm British English voice singing to the tune of "Pop Goes the '
          'Weasel", at nursery-rhyme pace.',
    ),
  ];
}

String _pureSound(Map<String, dynamic> sound) {
  final pure = sound['pureSound'] as String? ?? sound['id'] as String;
  return sound['articulation'] == 'stop' ? '$pure, $pure, $pure' : pure;
}

/// Kept in step with lib/models/soup_song.dart.
String _songLyrics() =>
    'Stir the pot and stir it round, '
    'Silly soup is bubbling. '
    'In go all the sounds we found — '
    'Whoosh! goes the soup!';

String? _option(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}
