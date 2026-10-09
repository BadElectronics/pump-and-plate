import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/store.dart';
import '../services/photo_files.dart';
import '../state/app_state.dart';

/// Guided progress photos: front, side, back.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        builder: (_) => const CameraScreen(),
        fullscreenDialog: true,
      );

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  static const _ink = Color(0xFFEDE7DD);
  static const _soft = Color(0xFFA39A8C);
  static const _panel = Color(0xFF221F1B);
  static const _moss = Color(0xFF9DB383);

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  bool _front = true;
  bool _ghost = true;
  int _timer = 10;
  int? _countdown;
  bool _busy = false;
  int _pose = 0;
  XFile? _shot;
  String? _error;
  final DateTime _today = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    final shot = _shot;
    if (shot != null) PhotoFiles.discard(shot.path);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.inactive) {
      setState(() => _controller = null);
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _open();
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
      await _open();
    } catch (e) {
      if (mounted) setState(() => _error = 'The camera couldn\'t start ($e).');
    }
  }

  CameraDescription? _pick() {
    final want = _front ? CameraLensDirection.front : CameraLensDirection.back;
    for (final c in _cameras) {
      if (c.lensDirection == want) return c;
    }
    return _cameras.isEmpty ? null : _cameras.first;
  }

  Future<void> _open() async {
    final desc = _pick();
    if (desc == null) {
      setState(() => _error = 'No camera was found on this phone.');
      return;
    }
    final old = _controller;
    setState(() => _controller = null);
    await old?.dispose();
    final c = CameraController(desc, ResolutionPreset.high, enableAudio: false);
    try {
      await c.initialize();
    } on CameraException catch (e) {
      await c.dispose();
      if (!mounted) return;
      setState(() {
        _error = e.code.contains('AccessDenied')
            ? 'Camera access is off. Allow it in your phone\'s Settings > Apps > '
                'Pump and Plate > Permissions, then come back.'
            : 'The camera couldn\'t start (${e.description ?? e.code}).';
      });
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    try {
      // Photos are always portrait, so the camera never asks the phone to
      // rotate.
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
    setState(() {
      _controller = c;
      _error = null;
    });
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (_busy || c == null || !c.value.isInitialized) return;
    _busy = true;
    try {
      for (var i = _timer; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdown = i);
        HapticFeedback.selectionClick();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() => _countdown = null);
      final x = await c.takePicture();
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _shot = x);
    } catch (e) {
      if (mounted) {
        setState(() => _countdown = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isStorageFull(e) ? _fullText : 'Couldn\'t take the photo: $e')),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _keep(AppState s) async {
    final x = _shot;
    final dir = s.photosDir;
    if (x == null) return;
    if (dir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The photos folder isn\'t available.')),
      );
      return;
    }
    final pose = PhotoPose.values[_pose];
    final name =
        '${dayKey(_today)}_${pose.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await PhotoFiles.keep(x.path, dir, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isStorageFull(e) ? _fullText : 'Couldn\'t save the photo: $e')),
        );
      }
      return;
    }
    s.savePhoto(PhotoCheckin(
      date: _today,
      pose: pose,
      fileName: name,
      weightKg: s.weighInOn(_today)?.weightKg ?? s.currentWeightKg,
    ));
    if (mounted) {
      setState(() {
        _shot = null;
        _pose += 1;
      });
    }
  }

  void _retake() {
    final x = _shot;
    if (x != null) PhotoFiles.discard(x.path);
    setState(() => _shot = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final done = _pose >= PhotoPose.values.length;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF12100E),
        body: SafeArea(
          child: done ? _doneView(context) : _cameraView(context, s),
        ),
      ),
    );
  }

  Widget _cameraView(BuildContext context, AppState s) {
    final pose = PhotoPose.values[_pose];
    final ghost = s.previousPhoto(pose, _today);
    final ghostPath = ghost == null ? null : s.pathFor(ghost);
    final c = _controller;
    final reviewing = _shot != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: _ink),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${pose.label} · ${_pose + 1} of 3',
                      style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Container(
                            width: 18,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i < _pose ? _moss : (i == _pose ? _ink : const Color(0xFF34302A)),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _Chip(
                label: _timer == 0 ? 'No timer' : '$_timer s',
                semantic: 'Timer, ${_timer == 0 ? 'off' : '$_timer seconds'}. Tap to change.',
                onTap: () => setState(() => _timer = _timer == 10 ? 0 : (_timer == 0 ? 5 : 10)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _ink, fontSize: 15, height: 1.5),
                      ),
                    )
                  : (c == null || !c.value.isInitialized)
                      ? const CircularProgressIndicator(color: _moss)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: AspectRatio(
                            aspectRatio: 1 / c.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (reviewing)
                                  Image.file(File(_shot!.path), fit: BoxFit.cover)
                                else
                                  CameraPreview(c),
                                if (!reviewing && _ghost && ghostPath != null)
                                  IgnorePointer(
                                    child: Opacity(
                                      opacity: 0.35,
                                      child: Transform.flip(
                                        flipX: _front,
                                        child: Image.file(
                                          File(ghostPath),
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!reviewing && ghostPath == null)
                                  const IgnorePointer(
                                    child: CustomPaint(painter: _OutlinePainter()),
                                  ),
                                if (_countdown != null)
                                  Center(
                                    child: Text(
                                      '$_countdown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 96,
                                        fontWeight: FontWeight.w300,
                                        shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 10,
                                  top: 10,
                                  child: _Badge(
                                    reviewing
                                        ? 'Check the photo'
                                        : (ghostPath != null
                                            ? 'Line up with last time'
                                            : 'Chest height, about 7 ft away'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Text(
            pose.tip,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFCFC6B6), fontSize: 14, height: 1.45),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: reviewing
              ? Row(
                  children: [
                    Expanded(child: _Button(label: 'Retake', onTap: _retake, quiet: true)),
                    const SizedBox(width: 10),
                    Expanded(child: _Button(label: 'Keep', onTap: () => _keep(s))),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Chip(
                          label: _front ? 'Front cam' : 'Back cam',
                          semantic: 'Switch camera',
                          onTap: () {
                            setState(() => _front = !_front);
                            _open();
                          },
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Take photo',
                      child: GestureDetector(
                        onTap: _shoot,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _ink, width: 3),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _countdown == null ? _ink : _moss,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ghostPath == null
                            ? const SizedBox.shrink()
                            : _Chip(
                                label: _ghost ? 'Ghost on' : 'Ghost off',
                                semantic: 'Show last photo as a guide',
                                onTap: () => setState(() => _ghost = !_ghost),
                              ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _doneView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: _moss, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 34, color: Color(0xFF12100E)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Check-in saved',
              style: TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Same spot, same light, same time next time.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _soft, fontSize: 15),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: _Button(label: 'Done', onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.semantic, required this.onTap});

  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantic,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _CameraScreenState._panel,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: const TextStyle(color: _CameraScreenState._ink, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC221F1B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _CameraScreenState._ink, fontSize: 12),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap, this.quiet = false});

  final String label;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: quiet ? _CameraScreenState._panel : _CameraScreenState._moss,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: quiet ? _CameraScreenState._ink : const Color(0xFF12100E),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed body outline shown before there's a previous photo to line up with.
class _OutlinePainter extends CustomPainter {
  const _OutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Figure drawn in a 100 x 200 box, scaled to 70% of the frame height.
    final h = size.height * 0.78;
    final scale = h / 200;
    final dx = (size.width - 100 * scale) / 2;
    final dy = (size.height - h) / 2;
    Offset pt(double x, double y) => Offset(dx + x * scale, dy + y * scale);

    final body = Path()
      ..moveTo(pt(50, 36).dx, pt(50, 36).dy)
      ..cubicTo(pt(40, 36).dx, pt(40, 36).dy, pt(32, 40).dx, pt(32, 40).dy, pt(30, 48).dx, pt(30, 48).dy)
      ..lineTo(pt(24, 96).dx, pt(24, 96).dy)
      ..lineTo(pt(30, 98).dx, pt(30, 98).dy)
      ..lineTo(pt(35, 60).dx, pt(35, 60).dy)
      ..lineTo(pt(36, 110).dx, pt(36, 110).dy)
      ..lineTo(pt(40, 190).dx, pt(40, 190).dy)
      ..lineTo(pt(48, 190).dx, pt(48, 190).dy)
      ..lineTo(pt(50, 120).dx, pt(50, 120).dy)
      ..lineTo(pt(52, 190).dx, pt(52, 190).dy)
      ..lineTo(pt(60, 190).dx, pt(60, 190).dy)
      ..lineTo(pt(64, 110).dx, pt(64, 110).dy)
      ..lineTo(pt(65, 60).dx, pt(65, 60).dy)
      ..lineTo(pt(70, 98).dx, pt(70, 98).dy)
      ..lineTo(pt(76, 96).dx, pt(76, 96).dy)
      ..lineTo(pt(70, 48).dx, pt(70, 48).dy)
      ..cubicTo(pt(68, 40).dx, pt(68, 40).dy, pt(60, 36).dx, pt(60, 36).dy, pt(50, 36).dx, pt(50, 36).dy)
      ..close();
    body.addOval(Rect.fromCircle(center: pt(50, 22), radius: 12 * scale));

    final paint = Paint()
      ..color = const Color(0xAA9DB383)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Dashed stroke.
    for (final metric in body.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) => false;
}

const _fullText = 'Your phone is full, so the photo couldn\'t be saved. Delete things you don\'t need, '
    'like old photos, videos or apps, then try again.';
