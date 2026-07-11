import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../downloader.dart';
import '../i18n.dart';
import '../model_catalog.dart';
import '../settings.dart';
import '../theme.dart';
import '../whisper_stt.dart';

/// User settings — quality tier + custom prefs (TTS rate, VAD sensitivity,
/// hands-free + live OCR defaults, glossary). Persisted via shared_preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<UiLang>();
    final s = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: Text(t.s('settings'))),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 64),
        children: [
          _section(t.s('ui_language')),
          Card(color: AppColors.surface, child: Column(children: [
            for (final l in UiLang.offered) RadioListTile<String>(
              value: l[0], groupValue: t.code, onChanged: (v) { if (v != null) t.setCode(v); },
              title: Text('${l[1]}  ${l[2]}'), activeColor: AppColors.accent,
            ),
          ])),
          const SizedBox(height: 20),
          Text(t.s('tier_hdr'), style: const TextStyle(color: AppColors.textLo)),
          const SizedBox(height: 12),
          for (final tier in Tier.values) _tierCard(s, t, tier),
          const SizedBox(height: 12),
          _ModelChooser(),
          const SizedBox(height: 20),
          _section(t.s('voice_prefs')),
          _slider(t.s('tts_rate'), '${(s.ttsRate * 100).round()}%', s.ttsRate, 0.3, 0.8, s.setRate),
          _slider(t.s('vad_sens'), '${s.vadHangoverMs}ms', s.vadHangoverMs / 1000, 0.8, 2.5,
              (v) => s.setVad((v * 1000).round())),
          _slider(t.s('mic_sens'), '${(s.micSensitivity * 100).round()}%', s.micSensitivity, 0.0, 1.0,
              s.setMicSensitivity),
          const SizedBox(height: 16),
          _section(t.s('defaults_hdr')),
          _switch(t.s('continuous'), s.continuousDefault, s.setContinuous),
          _switch(t.s('live_ocr_default'), s.ocrLiveDefault, s.setOcrLive),
          _switch(t.s('auto_glossary'), s.autoApplyGlossary, s.setGlossary),
          const SizedBox(height: 16),
          _section(t.s('ondevice_stt')),
          _switch(t.s('use_ondevice_stt'), s.useOnDeviceStt, s.setOnDeviceStt),
          _WhisperModel(),
          const SizedBox(height: 16),
          _section(t.s('downloader_hdr')),
          _DownloaderDemo(),
          const SizedBox(height: 24),
          const Center(child: Text('VoiceBridge · v1.0 · offline',
              style: TextStyle(color: AppColors.textLo, fontSize: 11))),
          const Center(child: Text('Viet-Anh Nguyen · Neural Research Lab',
              style: TextStyle(color: AppColors.textLo, fontSize: 11))),
        ],
      )),
    );
  }

  Widget _tierCard(AppSettings s, UiLang t, Tier tier) {
    final sel = s.tier == tier;
    final p = tierPresets[tier]!;
    String nm(Stage st) {
      final base = specById(p[st]!)?.name ?? p[st]!;
      // ASR is language-routed: VN auto-upgrades to PhoWhisper-small.
      return st == Stage.asr ? '$base (VN→PhoWhisper)' : base;
    }
    return Card(
      color: sel ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: sel ? AppColors.accent : Colors.white10, width: sel ? 2 : 1),
      ),
      child: ListTile(
        onTap: () => s.setTier(tier),
        title: Text(t.s('tier_${tier.name}'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('MT ${nm(Stage.mt)} · ASR ${nm(Stage.asr)} · OCR ${nm(Stage.ocr)} · TTS ${nm(Stage.tts)}',
            style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
        trailing: sel ? const Icon(Icons.check_circle, color: AppColors.accent) : null,
      ),
    );
  }

  Widget _section(String s) => Padding(padding: const EdgeInsets.only(bottom: 6),
      child: Text(s, style: const TextStyle(color: AppColors.textLo)));

  Widget _slider(String lbl, String val, double v, double min, double max, ValueChanged<double> on) =>
      Card(color: AppColors.surface, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text(lbl)), Text(val, style: const TextStyle(color: AppColors.textLo))]),
            Slider(value: v, min: min, max: max, onChanged: on, activeColor: AppColors.accent),
          ])));

  Widget _switch(String lbl, bool v, ValueChanged<bool> on) =>
      Card(color: AppColors.surface, child: SwitchListTile(title: Text(lbl), value: v, onChanged: on, activeColor: AppColors.accent));
}

/// Per-stage model chooser — lets the user compose a custom set on top of the
/// tier, showing each candidate's measured profile (languages · quality ·
/// latency · license). Choices persist via AppSettings.setModel.
class _ModelChooser extends StatefulWidget {
  @override
  State<_ModelChooser> createState() => _ModelChooserState();
}

class _ModelChooserState extends State<_ModelChooser> {
  bool _open = false;
  static final _stageLabel = {
    Stage.asr: 'Speech (ASR)', Stage.mt: 'Translate (MT)',
    Stage.ocr: 'Camera (OCR)', Stage.tts: 'Voice (TTS)',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return Card(color: AppColors.surface, child: Column(children: [
      ListTile(
        onTap: () => setState(() => _open = !_open),
        leading: const Icon(Icons.tune, color: AppColors.accent),
        title: const Text('Customize models', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(s.isCustom ? 'Custom set (overrides tier)' : 'Using tier defaults',
            style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
        trailing: Icon(_open ? Icons.expand_less : Icons.expand_more, color: AppColors.textLo),
      ),
      if (_open)
        for (final stage in Stage.values) _stageBlock(s, stage),
    ]));
  }

  Widget _stageBlock(AppSettings s, Stage stage) {
    final chosen = s.modelId(stage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(_stageLabel[stage]!, style: const TextStyle(color: AppColors.textLo, fontSize: 12))),
        for (final m in catalog[stage]!)
          InkWell(
            onTap: () => s.setModel(stage, m.id),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: m.id == chosen ? AppColors.accent.withValues(alpha: 0.14) : Colors.white10,
                border: Border.all(color: m.id == chosen ? AppColors.accent : Colors.transparent),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 6),
                    if (!m.measured) const _Chip('planned', AppColors.amber),
                  ]),
                  const SizedBox(height: 2),
                  Text('${m.langs} · ${m.license}', style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
                  Text('${m.quality}  ·  ${m.latency}', style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
                ])),
                if (m.id == chosen) const Icon(Icons.check_circle, color: AppColors.accent, size: 18),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

/// On-device Whisper model manager — shows whether the ~375 MB multilingual
/// Whisper-small (KO/ZH/EN) is downloaded, and downloads it with real progress.
/// Once present, the controller routes KO/ZH/EN speech to it (no cloud).
class _WhisperModel extends StatefulWidget {
  @override
  State<_WhisperModel> createState() => _WhisperModelState();
}

class _WhisperModelState extends State<_WhisperModel> {
  @override
  Widget build(BuildContext context) {
    final t = context.watch<UiLang>();
    final c = context.read<InterpreterController>();
    final dl = c.whisper.download;
    // Long-press the tile (when the model is on disk) to run the on-device
    // Whisper latency benchmark; results land in the docs dir. Dev/measurement
    // affordance, mirrors the other long-press benches (OCR / FLORES / self-test).
    return GestureDetector(
      onLongPress: c.whisperReady ? c.whisperLatencyBenchmark : null,
      child: Card(color: AppColors.surface, child: Padding(padding: const EdgeInsets.all(14),
      child: AnimatedBuilder(animation: dl, builder: (_, __) {
        final p = dl.progress;
        final mbps = (p.bytesPerSec / 1024 / 1024).toStringAsFixed(2);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Whisper-small (KO·ZH·EN)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(c.whisperReady ? t.s('whisper_ready') : '~${WhisperStt.totalMb} MB · ${t.s('whisper_offline_note')}',
                  style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
            ])),
            if (c.whisperReady)
              const Icon(Icons.check_circle, color: AppColors.accent)
            else
              FilledButton.tonal(onPressed: dl.downloading ? null : _download, child: Text(t.s('download'))),
          ]),
          if (dl.downloading || (p.received > 0 && !c.whisperReady)) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: p.fraction == 0 ? null : p.fraction, color: AppColors.accent),
            const SizedBox(height: 6),
            Text('${ModelDownload.fmtBytes(p.received)} / ${p.total > 0 ? ModelDownload.fmtBytes(p.total) : "?"}'
                ' · $mbps MB/s · ETA ${p.etaRemaining.inSeconds}s',
                style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
          ],
          if (dl.error != null) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(dl.error!, style: const TextStyle(color: AppColors.amber, fontSize: 11))),
        ]);
      }))));
  }

  Future<void> _download() async {
    final c = context.read<InterpreterController>();
    final ok = await c.whisper.ensureDownloaded();
    await c.refreshWhisper();
    if (mounted) setState(() {});
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download failed — check connection and retry')));
    }
  }
}

/// Live demo of the bundled-model downloader with real %/speed/ETA, hitting
/// a small public test file. Tap to start; updates 5×/sec.
class _DownloaderDemo extends StatefulWidget {
  @override
  State<_DownloaderDemo> createState() => _DownloaderDemoState();
}

class _DownloaderDemoState extends State<_DownloaderDemo> {
  final _dl = ModelDownload();
  @override
  Widget build(BuildContext context) {
    final t = context.watch<UiLang>();
    return Card(color: AppColors.surface, child: Padding(padding: const EdgeInsets.all(14),
      child: AnimatedBuilder(animation: _dl, builder: (_, __) {
        final p = _dl.progress;
        final mbps = (p.bytesPerSec / 1024 / 1024).toStringAsFixed(2);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(t.s('downloader_demo'))),
            FilledButton.tonal(onPressed: _dl.downloading ? null : _start, child: Text(t.s('start'))),
          ]),
          if (_dl.downloading || p.received > 0) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: p.fraction == 0 ? null : p.fraction, color: AppColors.accent),
            const SizedBox(height: 6),
            Text('${ModelDownload.fmtBytes(p.received)} / ${p.total > 0 ? ModelDownload.fmtBytes(p.total) : "?"}'
                ' · $mbps MB/s · ETA ${p.etaRemaining.inSeconds}s',
                style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
          ],
          if (_dl.error != null) Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(_dl.error!, style: const TextStyle(color: AppColors.amber, fontSize: 11))),
        ]);
      })));
  }
  Future<void> _start() async {
    final dir = await getTemporaryDirectory();
    // 1 MB public test file. Replace with bundled E2B/PhoWhisper URL on ship.
    await _dl.fetch(Uri.parse('https://speed.hetzner.de/1MB.bin'),
        File('${dir.path}/dl_test_${DateTime.now().millisecondsSinceEpoch}.bin'));
  }
}
