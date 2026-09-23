import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/providers.dart';
import 'screens/screens.dart';
import 'services/services.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Poppins is declared as a font family in pubspec.yaml, so the engine loads
  // it from the bundle and never calls out to fonts.gstatic.com — no network
  // calls at all is a hard requirement here, not a nicety. See PRIVACY.md.
  // The google_fonts package used to register this licence for us.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Poppins',
    ], await rootBundle.loadString('assets/google_fonts/OFL.txt'));
  });

  // Landscape suits a shared tablet on a table between an adult and a child.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const SillySoupApp());
}

class SillySoupApp extends StatelessWidget {
  const SillySoupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'Silly Soup',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const AppLoader(),
      ),
    );
  }
}

/// Loads the sound bank and the adult's settings before the chef appears.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key});

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> {
  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final app = context.read<AppProvider>();
    await app.initialise();
    if (!mounted) return;
    final error = app.error;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: SoupColours.primary),
      );
    }
  }

  /// Takes the page's splash away once the home screen has actually painted.
  ///
  /// A frame later than `isInitialised`, deliberately: hiding the splash the
  /// moment the future completes uncovers a scaffold that has not been drawn
  /// yet, which reads as a flicker.
  void _handOverFromSplash() {
    if (_splashDismissed) return;
    _splashDismissed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
  }

  bool _splashDismissed = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        if (!app.isInitialised) {
          // The page's own splash is still on top of this, so drawing a
          // second logo and spinner here only ever showed as a flash between
          // the two. Match the splash's background and let it keep the stage.
          return const ColoredBox(color: SoupColours.background);
        }

        _handOverFromSplash();
        return const HomeScreen();
      },
    );
  }
}
