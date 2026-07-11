import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../controller.dart';
import '../docx_builder.dart';
import '../i18n.dart';
import '../theme.dart';

/// Live camera translator: point at a sign/label and see the translation
/// overlaid in real time. Tap shutter to freeze the result + export DOCX.
class LensScreen extends StatefulWidget {
  const LensScreen({super.key});
  @override
  State<LensScreen> createState() => _LensScreenState();
}

class _LensScreenState extends State<LensScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  bool _streaming = false;
  late bool _liveMode; // live overlay vs battery-saving capture-only (default from settings)
  bool _busy = false;
  bool _camReady = false;
  List<({String src, String dst, double l, double t, double r, double b})> _live = const [];
  Size _imgSize = Size.zero;
  List<({String src, String dst})> _frozen = const [];
  String? _frozenPath;

  @override
  void initState() {
    super.initState();
    _liveMode = context.read<InterpreterController>().settings.ocrLiveDefault;
    WidgetsBinding.instance.addObserver(this);
    _initCam();
  }

  Future<void> _initCam() async {
    try {
      await Permission.camera.request();
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(back, ResolutionPreset.high, enableAudio: false,
          imageFormatGroup: ImageFormatGroup.nv21);
      await cam.initialize();
      if (!mounted) return;
      _cam = cam;
      _camReady = true;
      _startStream();
      setState(() {});
    } catch (_) {/* fall back to gallery only */ if (mounted) setState(() {}); }
  }

  void _startStream() {
    final cam = _cam;
    if (cam == null || _streaming || !_liveMode) return; // off = capture-only
    _streaming = true;
    cam.startImageStream(_onFrame);
  }

  void _toggleLive() {
    setState(() { _liveMode = !_liveMode; if (!_liveMode) _live = const []; });
    if (_liveMode) _startStream(); else _stopStream();
  }

  Future<void> _stopStream() async {
    if (_cam != null && _streaming) { _streaming = false; await _cam!.stopImageStream(); }
  }

  Future<void> _onFrame(CameraImage f) async {
    if (_busy || _frozen.isNotEmpty) return;
    _busy = true;
    try {
      final img = _toInput(f);
      if (img != null) {
        final r = await context.read<InterpreterController>().liveOcr(img);
        if (mounted) setState(() { _live = r; _imgSize = Size(f.width.toDouble(), f.height.toDouble()); });
      }
    } catch (_) {} finally { _busy = false; }
  }

  static const _orient = {DeviceOrientation.portraitUp: 0, DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180, DeviceOrientation.landscapeRight: 270};

  // Canonical flutter-ml conversion: nv21, single plane, sensor±device rotation.
  InputImage? _toInput(CameraImage f) {
    final cam = _cam; if (cam == null || f.planes.length != 1) return null;
    final sensor = cam.description.sensorOrientation;
    final dev = _orient[cam.value.deviceOrientation] ?? 0;
    final comp = cam.description.lensDirection == CameraLensDirection.front
        ? (sensor + dev) % 360 : (sensor - dev + 360) % 360;
    final rot = InputImageRotationValue.fromRawValue(comp) ?? InputImageRotation.rotation0deg;
    final p = f.planes.first;
    return InputImage.fromBytes(bytes: p.bytes, metadata: InputImageMetadata(
      size: Size(f.width.toDouble(), f.height.toDouble()), rotation: rot,
      format: InputImageFormat.nv21, bytesPerRow: p.bytesPerRow));
  }

  Future<void> _capture() async {
    final c = context.read<InterpreterController>(); final cam = _cam;
    if (cam == null) { return _gallery(); }
    setState(() => _busy = true);
    await _stopStream();
    final shot = await cam.takePicture();
    final res = await c.ocrTranslate(shot.path);
    if (!mounted) return;
    setState(() { _frozen = res; _frozenPath = shot.path; _busy = false; });
  }

  Future<void> _gallery() async {
    final c = context.read<InterpreterController>();
    final p = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 1920);
    if (p == null) return;
    setState(() => _busy = true);
    final res = await c.ocrTranslate(p.path);
    if (!mounted) return;
    setState(() { _frozen = res; _frozenPath = p.path; _busy = false; });
  }

  void _resume() { setState(() { _frozen = const []; _frozenPath = null; }); _startStream(); }

  Future<void> _docx() async {
    final c = context.read<InterpreterController>();
    // Layout-preserving grid if we have block boxes; else simple 2-col table.
    final bytes = c.lastBoxes.isNotEmpty
        ? buildStructuredDocx(title: 'VoiceBridge OCR — ${c.bottom.name}', cells: c.lastBoxes)
        : buildOcrDocx(title: 'VoiceBridge OCR — ${c.top.name} → ${c.bottom.name}',
            srcLabel: c.top.name, dstLabel: c.bottom.name, rows: _frozen);
    final dir = await getApplicationDocumentsDirectory();
    final fp = File('${dir.path}/voicebridge_ocr_${DateTime.now().millisecondsSinceEpoch}.docx');
    await fp.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(fp.path)], text: 'VoiceBridge OCR'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) _stopStream();
    if (s == AppLifecycleState.resumed && _frozen.isEmpty) _startStream();
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); _cam?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    final t = context.watch<UiLang>();
    return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Column(children: [
      _langBar(c, t),
      Expanded(child: _frozen.isNotEmpty ? _result(t) : _camera(t)),
    ])));
  }

  Widget _langBar(InterpreterController c, UiLang t) => GestureDetector(
    // dev: long-press runs the on-device OCR bench (ML Kit CER)
    onLongPress: () async { await c.ocrBenchmark(); },
    child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(children: [
      _pill('${c.top.flag} ${c.top.name}'),
      IconButton(onPressed: c.swap, icon: const Icon(Icons.swap_horiz, color: AppColors.accent)),
      _pill('${c.bottom.flag} ${c.bottom.name}'),
      const SizedBox(width: 4),
      Text(t.s('live'), style: TextStyle(color: _liveMode ? AppColors.amber : AppColors.textLo, fontSize: 10)),
      Transform.scale(scale: 0.8, child: Switch(value: _liveMode, onChanged: (_) => _toggleLive(),
        activeColor: AppColors.accent, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
      IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero,
        onPressed: _gallery, icon: const Icon(Icons.photo_library_outlined, color: AppColors.textHi)),
    ]),
  ));
  Widget _pill(String s) => Flexible(child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
    child: Text(s, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textHi, fontSize: 13))));

  Widget _camera(UiLang t) {
    if (!_camReady || _cam == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.center_focus_strong, color: AppColors.accent, size: 56),
        const SizedBox(height: 12), Text(t.s('cam_init'), style: const TextStyle(color: AppColors.textLo)),
      ]));
    }
    return Stack(fit: StackFit.expand, children: [
      CameraPreview(_cam!),
      CustomPaint(painter: _Overlay(_live, _imgSize, _cam!.description.sensorOrientation)),
      Positioned(top: 8, left: 12, child: Row(children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle)),
        const SizedBox(width: 6), Text(t.s('live'), style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      ])),
      Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 28),
        child: FloatingActionButton.large(onPressed: _busy ? null : _capture, backgroundColor: AppColors.accent,
          child: _busy ? const CircularProgressIndicator(color: Colors.black) : const Icon(Icons.camera, color: Colors.black, size: 36)))),
    ]);
  }

  Widget _result(UiLang t) => Column(children: [
    Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [
      if (_frozenPath != null) ClipRRect(borderRadius: BorderRadius.circular(12),
        child: Image.file(File(_frozenPath!), height: 150, width: double.infinity, fit: BoxFit.cover)),
      const SizedBox(height: 12),
      ..._frozen.map((r) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.src, style: const TextStyle(color: AppColors.textLo, fontSize: 13)),
          const SizedBox(height: 4), Text(r.dst, style: const TextStyle(color: AppColors.textHi, fontSize: 17, fontWeight: FontWeight.w700)),
        ]))),
    ])),
    Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: _resume, icon: const Icon(Icons.videocam), label: Text(t.s('resume_live')))),
      const SizedBox(width: 10),
      Expanded(child: FilledButton.icon(onPressed: _frozen.isEmpty ? null : _docx, icon: const Icon(Icons.description), label: Text(t.s('export_docx')))),
    ])),
  ]);
}

class _Overlay extends CustomPainter {
  final List<({String src, String dst, double l, double t, double r, double b})> boxes;
  final Size img; final int rot;
  _Overlay(this.boxes, this.img, this.rot);
  @override
  void paint(Canvas cv, Size s) {
    if (img == Size.zero) return;
    final iw = (rot == 90 || rot == 270) ? img.height : img.width;
    final ih = (rot == 90 || rot == 270) ? img.width : img.height;
    final sx = s.width / iw, sy = s.height / ih;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final box in boxes) {
      final rect = Rect.fromLTRB(box.l * sx, box.t * sy, box.r * sx, box.b * sy);
      cv.drawRRect(RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(4)),
          Paint()..color = Colors.black.withValues(alpha: 0.7));
      tp.text = TextSpan(text: box.dst, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700));
      tp.layout(maxWidth: rect.width + 80); tp.paint(cv, rect.topLeft);
    }
  }
  @override
  bool shouldRepaint(_Overlay o) => o.boxes != boxes;
}
