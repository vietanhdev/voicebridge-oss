import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controller.dart';
import '../glossary.dart';
import '../i18n.dart';
import '../theme.dart';

/// Cold-path learning: turns the worker's own conversations into a review deck.
/// Wires spaced-repetition next; this pass shows the design + real recent terms.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<InterpreterController>();
    final g = context.watch<Glossary>();
    final t = context.watch<UiLang>();
    final recent = c.turns.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(t.s('learn_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _StreakCard(termCount: g.entries.length + recent.length),
          const SizedBox(height: 20),
          _SectionTitle(t.s('review_deck')),
          const SizedBox(height: 10),
          _ReviewCard(
            front: g.entries.isNotEmpty ? g.entries.first.src : 'emergency stop',
            back: g.entries.isNotEmpty ? g.entries.first.dst : 'dừng khẩn cấp',
          ),
          const SizedBox(height: 24),
          _SectionTitle(t.s('from_conversations')),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            _EmptyHint()
          else
            ...recent.map((t) => _TermRow(
                  original: t.original,
                  translated: t.translated.replaceAll('⚑', '').trim(),
                  from: t.from.flag,
                  to: t.to.flag,
                )),
          const SizedBox(height: 24),
          _SectionTitle(t.s('saved_glossary')),
          const SizedBox(height: 10),
          ...g.entries.take(6).map((e) => _TermRow(
                original: e.src,
                translated: e.dst,
                from: _flag(e.srcLang),
                to: _flag(e.dstLang),
                safety: e.safety,
              )),
        ],
      ),
    );
  }

  static String _flag(String code) => switch (code) {
        'vi' => '🇻🇳',
        'en' => '🇺🇸',
        'ko' => '🇰🇷',
        'zh' => '🇨🇳',
        _ => '🏳️',
      };
}

class _StreakCard extends StatelessWidget {
  final int termCount;
  const _StreakCard({required this.termCount});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF134E48), Color(0xFF0E2A3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$termCount', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.accent)),
              const Text('terms to review', style: TextStyle(color: AppColors.textLo)),
            ],
          ),
          const Spacer(),
          Column(
            children: const [
              Icon(Icons.local_fire_department_rounded, color: AppColors.amber, size: 36),
              SizedBox(height: 4),
              Text('Day 1', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final String front, back;
  const _ReviewCard({required this.front, required this.back});
  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool revealed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => revealed = !revealed),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(revealed ? widget.back : widget.front,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(revealed ? 'tap to flip back' : 'tap to reveal',
                style: const TextStyle(color: AppColors.textLo, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  final String original, translated, from, to;
  final bool safety;
  const _TermRow({
    required this.original,
    required this.translated,
    required this.from,
    required this.to,
    this.safety = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: safety ? AppColors.amber.withValues(alpha: 0.35) : Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$from $original', style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text('$to $translated', style: const TextStyle(color: AppColors.accent, fontSize: 15)),
              ],
            ),
          ),
          Icon(safety ? Icons.shield_outlined : Icons.bookmark_border,
              size: 18, color: safety ? AppColors.amber : AppColors.textLo),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
}

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(children: [
        Icon(Icons.history_edu, color: AppColors.textLo),
        SizedBox(width: 12),
        Expanded(child: Text('Have a conversation — new words will appear here to review.',
            style: TextStyle(color: AppColors.textLo))),
      ]),
    );
  }
}
