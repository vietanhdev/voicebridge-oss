import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../i18n.dart';
import '../languages.dart';
import '../theme.dart';
import 'glossary_screen.dart';
import 'learn_screen.dart';
import 'history_screen.dart';
import 'lens_screen.dart';
import 'settings_screen.dart';

class InterpreterScreen extends StatefulWidget {
  const InterpreterScreen({super.key});

  @override
  State<InterpreterScreen> createState() => _InterpreterScreenState();
}

class _InterpreterScreenState extends State<InterpreterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(
            children: [
              const _TopBar(),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 2,
                  child: _Panel(side: Side.top, accent: AppColors.accent2, pulse: _pulse),
                ),
              ),
              const _ControlStrip(),
              Expanded(
                child: _Panel(side: Side.bottom, accent: AppColors.accent, pulse: _pulse),
              ),
            ],
          ),
          if (c.status == PipeStatus.downloading)
            _DownloadOverlay(msg: c.statusMsg.isEmpty ? '${context.read<UiLang>().s('downloading')} ${context.read<UiLang>().s('models')}' : c.statusMsg),
        ]),
      ),
    );
  }
}

/// Download popup. ML Kit gives no %/speed, so we show size estimate + elapsed
/// (no fabricated ETA). Bundled-model HTTP downloads will show real %/speed.
class _DownloadOverlay extends StatefulWidget {
  final String msg;
  const _DownloadOverlay({required this.msg});
  @override
  State<_DownloadOverlay> createState() => _DownloadOverlayState();
}

class _DownloadOverlayState extends State<_DownloadOverlay> {
  late final Stopwatch _sw = Stopwatch()..start();
  late final t = Stream.periodic(const Duration(seconds: 1)).listen((_) => mounted ? setState(() {}) : null);
  @override
  void dispose() { t.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext c) => Positioned.fill(child: Container(color: Colors.black54, child: Center(
    child: Container(width: 260, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: AppColors.accent),
        const SizedBox(height: 16),
        Text(widget.msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textHi)),
        const SizedBox(height: 10),
        const LinearProgressIndicator(color: AppColors.accent, backgroundColor: Colors.white12),
        const SizedBox(height: 6),
        Text('~30 MB · ${_sw.elapsed.inSeconds}s', style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
      ])))));
}

/// One participant's half of the screen (the top one is rotated 180°).
class _Panel extends StatelessWidget {
  final Side side;
  final Color accent;
  final Animation<double> pulse;
  const _Panel({required this.side, required this.accent, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    final lang = c.langOf(side);
    final isActive = c.activeSide == side && c.status == PipeStatus.listening;
    final content = c.panelContent(side);

    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surfaceAlt, AppColors.surface],
        ),
        border: Border.all(
          color: isActive ? accent : Colors.white.withValues(alpha: 0.06),
          width: isActive ? 2 : 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LangChip(side: side, lang: lang, accent: accent),
              Expanded(child: _PanelBody(side: side, content: content, isActive: isActive, accent: accent)),
              const SizedBox(height: 8),
              Center(child: _MicButton(side: side, accent: accent, pulse: pulse, isActive: isActive)),
            ],
          );
          // Roomy panel → flex layout with the mic pinned to the bottom. On a
          // very short panel (split-screen / tiny multi-window) the fixed chip +
          // mic can't fit the squeezed Expanded and would overflow, so give the
          // column a comfortable fixed height and let the panel scroll instead.
          const minComfortable = 190.0;
          if (constraints.maxHeight >= minComfortable) return column;
          return SingleChildScrollView(
            child: SizedBox(height: minComfortable, child: column),
          );
        },
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final Side side;
  final Lang lang;
  final Color accent;
  const _LangChip({required this.side, required this.lang, required this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.read<InterpreterController>();
    return Row(
      children: [
        // Flexible + ellipsis so the chip shrinks instead of overflowing the
        // panel on extremely narrow widths.
        Flexible(
          child: GestureDetector(
            onTap: () => _pickLanguage(context, c, side),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(lang.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(lang.nativeName,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: accent),
              ]),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _PanelBody extends StatelessWidget {
  final Side side;
  final ({String text, String caption, bool enforced})? content;
  final bool isActive;
  final Color accent;
  const _PanelBody({required this.side, required this.content, required this.isActive, required this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    final t = context.watch<UiLang>();
    final lang = c.langOf(side);

    Widget child;
    if (isActive) {
      child = Column(
        key: const ValueKey('listening'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(t.s('listening'), style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(
            c.partial.isEmpty ? '…' : c.partial,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, height: 1.3, color: AppColors.textHi),
          ),
        ],
      );
    } else if (content != null) {
      child = Column(
        key: ValueKey(content!.text),
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (content!.enforced)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(child: _LockedChip()),
            ),
          Text(
            content!.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.textHi),
          ),
          const SizedBox(height: 12),
          Text(
            content!.caption,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.textLo, fontStyle: FontStyle.italic),
          ),
        ],
      );
    } else {
      child = Column(
        key: const ValueKey('hint'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.graphic_eq, color: accent.withValues(alpha: 0.5), size: 40),
          const SizedBox(height: 12),
          Text(t.f('speak_hint', lang.nativeName),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textLo, fontSize: 16)),
        ],
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Center(child: SingleChildScrollView(child: child)),
    );
  }
}

class _LockedChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.shield_outlined, size: 14, color: AppColors.amber),
        const SizedBox(width: 5),
        Text(context.watch<UiLang>().s('safety_locked'),
            style: const TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MicButton extends StatelessWidget {
  final Side side;
  final Color accent;
  final Animation<double> pulse;
  final bool isActive;
  const _MicButton({required this.side, required this.accent, required this.pulse, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final c = context.read<InterpreterController>();
    final t = context.watch<UiLang>();
    return GestureDetector(
      onTap: () => c.listen(side),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final glow = isActive ? (0.35 + 0.5 * pulse.value) : 0.2;
              final size = isActive ? 78.0 + 8 * pulse.value : 72.0;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isActive
                        ? [accent, accent.withValues(alpha: 0.7)]
                        : [AppColors.surfaceAlt, AppColors.surface],
                  ),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: glow),
                      blurRadius: isActive ? 26 : 14,
                      spreadRadius: isActive ? 4 : 1,
                    ),
                  ],
                ),
                child: Icon(
                  isActive ? Icons.stop_rounded : Icons.mic_rounded,
                  color: isActive ? Colors.black : accent,
                  size: 34,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            isActive ? t.s('tap_stop') : t.s('tap_speak'),
            style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final t = context.watch<UiLang>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 2),
      child: Row(
        children: [
          Flexible(
            child: GestureDetector(
              onLongPress: () => context.read<InterpreterController>().floresBenchmark(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset('assets/branding/icon_full.png', width: 28, height: 28),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Scale the icon cluster down on very narrow widths so it can never
          // overflow the row horizontally (small phones / split-screen).
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _navIcon(context, Icons.center_focus_strong_rounded, t.s('nav_lens'), const LensScreen()),
                _navIcon(context, Icons.school_rounded, t.s('nav_learn'), const LearnScreen()),
                _navIcon(context, Icons.menu_book_rounded, t.s('nav_glossary'), const GlossaryScreen(), color: AppColors.amber),
                _navIcon(context, Icons.history_rounded, t.s('history'), const HistoryScreen()),
                _navIcon(context, Icons.tune_rounded, t.s('settings'), const SettingsScreen()),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(BuildContext context, IconData icon, String tip, Widget screen, {Color? color}) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      iconSize: 22,
      icon: Icon(icon, color: color ?? AppColors.textLo),
      onPressed: () => Navigator.of(context).push(_fadeRoute(screen)),
    );
  }
}

/// Subtle fade page transition — feels smoother than the default platform slide.
PageRoute<T> _fadeRoute<T>(Widget child) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (_, anim, __, c) => FadeTransition(opacity: anim, child: c),
    );

class _ControlStrip extends StatelessWidget {
  const _ControlStrip();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    final t = context.watch<UiLang>();
    final downloading = c.status == PipeStatus.downloading;
    final isError = c.status == PipeStatus.error;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: c.toggleContinuous,
                visualDensity: VisualDensity.compact,
                tooltip: t.s('continuous'),
                icon: Icon(
                  Icons.all_inclusive_rounded,
                  color: c.continuous ? AppColors.accent : AppColors.textLo.withValues(alpha: 0.5),
                ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${c.top.flag} ${c.top.code.toUpperCase()}',
                          style: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w700, fontSize: 15)),
                      IconButton(
                        onPressed: c.swap,
                        iconSize: 26,
                        icon: const Icon(Icons.swap_vert_rounded, color: AppColors.accent),
                        tooltip: t.s('swap'),
                      ),
                      Text('${c.bottom.flag} ${c.bottom.code.toUpperCase()}',
                          style: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                ),
              ),
              if (downloading)
                Row(children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(t.s('models'), style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
                ])
              else
                const SizedBox(width: 40),
            ],
          ),
          if (c.statusMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                c.statusMsg,
                textAlign: TextAlign.center,
                style: TextStyle(color: isError ? AppColors.amber : AppColors.textLo, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }
}

void _pickLanguage(BuildContext context, InterpreterController c, Side side) {
  final other = c.otherOf(side);
  final t = context.read<UiLang>();
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t.s('choose_lang'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final l in kLangs)
            ListTile(
              leading: Text(l.flag, style: const TextStyle(fontSize: 24)),
              title: Text(l.nativeName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(l.name, style: const TextStyle(color: AppColors.textLo)),
              enabled: l.code != other.code,
              trailing: l.code == c.langOf(side).code
                  ? const Icon(Icons.check_circle, color: AppColors.accent)
                  : null,
              onTap: () {
                c.setLang(side, l);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

