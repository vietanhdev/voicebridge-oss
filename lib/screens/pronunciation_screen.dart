import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../languages.dart';
import '../pronunciation.dart';
import '../theme.dart';

/// Manage the pronunciation dictionary (TTS respellings).
class PronunciationScreen extends StatelessWidget {
  const PronunciationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<Pronunciation>();
    final t = context.watch<UiLang>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(t.s('pron_title')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.s('pron_sub'),
                style: const TextStyle(color: AppColors.textLo, fontSize: 12.5),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, p),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(t.s('add')),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: p.entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = p.entries[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Text(langByCode(e.lang).flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(children: [
                    Flexible(child: Text(e.term, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.volume_up_rounded, size: 16, color: AppColors.textLo),
                    ),
                    Flexible(child: Text(e.say, style: const TextStyle(fontSize: 16, color: AppColors.accent))),
                  ]),
                ),
                IconButton(
                  onPressed: () => p.removeAt(i),
                  icon: const Icon(Icons.delete_outline, color: AppColors.textLo),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

void _addDialog(BuildContext context, Pronunciation p) {
  final termCtrl = TextEditingController();
  final sayCtrl = TextEditingController();
  String lang = 'vi';
  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add pronunciation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: lang,
              isExpanded: true,
              dropdownColor: AppColors.surfaceAlt,
              items: [for (final l in kLangs) DropdownMenuItem(value: l.code, child: Text('${l.flag} ${l.name} voice'))],
              onChanged: (v) => setState(() => lang = v ?? 'vi'),
            ),
            TextField(controller: termCtrl, decoration: const InputDecoration(labelText: 'Word / name')),
            TextField(controller: sayCtrl, decoration: const InputDecoration(labelText: 'Say it like…')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (termCtrl.text.trim().isEmpty || sayCtrl.text.trim().isEmpty) return;
              p.add(PronEntry(term: termCtrl.text.trim(), say: sayCtrl.text.trim(), lang: lang));
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
