import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';
import '../widgets/widgets.dart';

/// "Watch my mouth": a close-up of how the sound is made.
///
/// The optional mirror is a live camera view and nothing else. There is no
/// capture button, no recording, no file, and no network call — see
/// PRIVACY.md. An adult has to turn it on in the adult area before it appears
/// here at all.
class MouthScreen extends StatefulWidget {
  const MouthScreen({super.key, required this.sound});
  final PhonemeSound sound;

  @override
  State<MouthScreen> createState() => _MouthScreenState();
}

class _MouthScreenState extends State<MouthScreen> {
  int _playToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _say());
  }

  void _say() {
    context.read<AppProvider>().audio.playSound(widget.sound);
    setState(() => _playToken++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final scale = SoupMetrics.scale(app.settings.whiteboardMode);
    final reducedMotion = app.prefersReducedMotion(context);
    final screen = MediaQuery.sizeOf(context);
    // The close-up is the point of this screen, but on a phone in landscape
    // a fixed 220 pushed the sound card and the tip off the top and bottom.
    final mouthSize = math
        .min(screen.width * 0.6, screen.height * 0.45)
        .clamp(140.0, 300.0)
        .toDouble();

    return Scaffold(
      backgroundColor: SoupColours.background,
      appBar: AppBar(
        title: const Text('Watch my mouth'),
        backgroundColor: SoupColours.background,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: Breakpoints.getHorizontalPadding(context),
            vertical: 16,
          ),
          child: Column(
            children: [
              SoundCard(
                sound: widget.sound,
                showLetter: app.settings.showLetters,
                scale: scale * 0.8,
                onTap: _say,
              ),
              SizedBox(height: 16 * scale),
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: [
                  MouthView(
                    sound: widget.sound,
                    size: mouthSize * scale,
                    reducedMotion: reducedMotion,
                    playToken: _playToken,
                  ),
                  if (app.settings.mirrorModeEnabled)
                    _MirrorView(size: mouthSize * scale),
                ],
              ),
              SizedBox(height: 16 * scale),
              if (widget.sound.mouthTip.isNotEmpty)
                Text(
                  widget.sound.mouthTip,
                  textAlign: TextAlign.center,
                  style: SoupTypography.chefSpeech(context)
                      .copyWith(fontSize: 20 * scale),
                ),
              SizedBox(height: 20 * scale),
              SoupButton(
                label: 'Say it again',
                icon: Icons.volume_up_rounded,
                scale: scale,
                onPressed: _say,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The front camera as a plain mirror.
///
/// Audio is disabled on the controller, no image is ever captured, and the
/// controller is disposed the moment this view leaves the screen.
class _MirrorView extends StatefulWidget {
  const _MirrorView({required this.size});
  final double size;

  @override
  State<_MirrorView> createState() => _MirrorViewState();
}

class _MirrorViewState extends State<_MirrorView> {
  CameraController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera on this device.');
        return;
      }
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        // Nothing is recorded, so the microphone is never opened.
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = 'The mirror could not start.');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(SoupMetrics.cardRadius),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: _error != null
                ? Container(
                    color: SoupColours.border,
                    alignment: Alignment.center,
                    child: Text(_error!, textAlign: TextAlign.center),
                  )
                : controller == null
                ? Container(
                    color: SoupColours.border,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(),
                  )
                : Transform.flip(
                    flipX: true,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width:
                            controller.value.previewSize?.height ?? widget.size,
                        height:
                            controller.value.previewSize?.width ?? widget.size,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Live view only — nothing is recorded.',
          style: SoupTypography.label(context),
        ),
      ],
    );
  }
}
