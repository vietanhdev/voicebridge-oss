import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../history.dart';
import '../i18n.dart';
import '../theme.dart';

/// Conversation history — every translated turn, reverse chronological.
/// Tap to copy/share; clear all with confirmation.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.watch<UiLang>();
    final h = context.watch<History>();
    return Scaffold(
      appBar: AppBar(title: Text(t.s('history')), actions: [
        IconButton(tooltip: t.s('export'), onPressed: h.turns.isEmpty ? null : () =>
          SharePlus.instance.share(ShareParams(text: h.exportText())), icon: const Icon(Icons.share)),
        IconButton(tooltip: t.s('clear'), onPressed: h.turns.isEmpty ? null : () => _confirm(context, h, t),
          icon: const Icon(Icons.delete_outline)),
      ]),
      body: h.turns.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.forum_outlined, size: 64, color: AppColors.accent.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(t.s('no_history'), textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textHi, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(t.s('no_history_hint'), textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textLo, fontSize: 13)),
            ])))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: h.turns.length,
              itemBuilder: (_, i) {
                final tn = h.turns[i];
                // Session header: gap of >5 min between this turn and the
                // previous (newer) one starts a new conversation.
                Widget? header;
                final newer = i == 0 ? null : h.turns[i - 1];
                final isFirst = i == h.turns.length - 1;
                final gap = newer == null ? Duration.zero
                  : DateTime.parse(newer['ts'] as String).difference(DateTime.parse(tn['ts'] as String));
                if (isFirst || gap.inMinutes > 5) {
                  header = Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Row(children: [
                      const Icon(Icons.forum_outlined, color: AppColors.textLo, size: 14),
                      const SizedBox(width: 6),
                      Text('${t.s('session')} · ${(tn['ts'] as String).substring(0, 10)}',
                        style: const TextStyle(color: AppColors.textLo, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]));
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (header != null) header,
                  Card(color: AppColors.surface, child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${tn['from']} → ${tn['to']}', style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
                      const Spacer(),
                      if (tn['glossary'] == true) const Icon(Icons.shield, color: AppColors.amber, size: 14),
                      Text('  ${(tn['ts'] as String).substring(5, 16)}', style: const TextStyle(color: AppColors.textLo, fontSize: 11)),
                    ]),
                    const SizedBox(height: 6),
                    Text(tn['src'] as String, style: const TextStyle(color: AppColors.textLo)),
                    const SizedBox(height: 4),
                    Text(tn['dst'] as String, style: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w700)),
                  ]),
                )),
                ]);
              }),
    );
  }

  void _confirm(BuildContext c, History h, UiLang t) => showDialog(context: c, builder: (_) => AlertDialog(
    title: Text(t.s('clear_q')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: Text(t.s('cancel'))),
      TextButton(onPressed: () { h.clear(); Navigator.pop(c); }, child: Text(t.s('clear'))),
    ]));
}
