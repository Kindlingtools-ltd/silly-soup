import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/providers.dart';
import 'screens/screens.dart';
import 'services/services.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Poppins is bundled under assets/google_fonts. Runtime fetching is off so
  // the app never calls out to fonts.gstatic.com — no network calls at all is
  // a hard requirement here, not a nicety. See PRIVACY.md.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Landscape suits a shared tablet on a table between an adult and a child,
  // but a phone is held upright and locking it to landscape left a child
  // looking at a sideways app they could not use. Every screen lays itself
  // out for the space it is given instead.
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  // Which recordings this build has. Read once, here, because a line made of
  // several clips has to be known to be complete before it starts playing.
  final clips = await ClipLibrary.load();

  // One service, shared by the provider that reports what happens in the
  // kitchen and the observer that reports which screen is up.
  runApp(SillySoupApp(analytics: AnalyticsService(), clips: clips));
}

class SillySoupApp extends StatelessWidget {
  SillySoupApp({super.key, required this.analytics, ClipLibrary? clips})
    : clips = clips ?? const ClipLibrary.empty(),
      _routeObserver = AnalyticsRouteObserver(analytics);

  final AnalyticsService analytics;
  final ClipLibrary clips;
  final AnalyticsRouteObserver _routeObserver;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(analytics: analytics),
      child: MaterialApp(
        title: 'Silly Soup',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorObservers: [_routeObserver],
        home: const _UnlockAudioOnFirstTouch(child: AppLoader()),
      ),
    );
  }
}

/// Spends the very first touch on making sound possible.
///
/// Mobile browsers will not speak or play a clip until the page has been
/// touched, and they refuse without saying so. Listening here — above every
/// screen, at the pointer-down that starts the child's first tap — is what
/// makes the chef audible on a phone at all.
class _UnlockAudioOnFirstTouch extends StatelessWidget {
  const _UnlockAudioOnFirstTouch({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Behind everything, so it never takes a tap away from a button.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => context.read<AppProvider>().audio.unlock(),
      child: child,
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        if (!app.isInitialised) {
          return Scaffold(
            backgroundColor: SoupColours.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/kindling_logo.svg',
                    width: 80,
                    height: 80,
                  ),
                  const SizedBox(height: 24),
                  Text('Silly Soup', style: SoupTypography.heading(context)),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        SoupColours.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const HomeScreen();
      },
    );
  }
}
