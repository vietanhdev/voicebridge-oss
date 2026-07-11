import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../glossary.dart';
import '../i18n.dart';
import '../settings.dart';
import '../languages.dart';
import '../theme.dart';
import 'pronunciation_screen.dart';

class GlossaryScreen extends StatelessWidget {
  const GlossaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<Glossary>();
    final t = context.watch<UiLang>();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(t.s('glossary_title')),
        actions: [
          IconButton(
            tooltip: 'Pronunciation',
            icon: const Icon(Icons.spellcheck_rounded, color: AppColors.accent),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PronunciationScreen()),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.s('glossary_sub'),
                style: const TextStyle(color: AppColors.textLo, fontSize: 12.5),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, g),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(t.s('add_term')),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Card(
          color: AppColors.surface,
          child: ListTile(
            leading: const Icon(Icons.spellcheck_rounded, color: AppColors.accent),
            title: Text(t.s('pron_dict_title')),
            subtitle: Text(t.s('pron_dict_sub'), style: const TextStyle(fontSize: 12, color: AppColors.textLo)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textLo),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PronunciationScreen())),
          ),
        )),
        _DomainRow(),
        Expanded(child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: g.entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final e = g.entries[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: e.safety
                    ? AppColors.amber.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text('${langByCode(e.srcLang).flag} ${e.src}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward, size: 16, color: AppColors.textLo),
                        ),
                        Flexible(
                          child: Text('${langByCode(e.dstLang).flag} ${e.dst}',
                              style: const TextStyle(fontSize: 16, color: AppColors.accent)),
                        ),
                      ]),
                      if (e.safety)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(children: [
                            const Icon(Icons.shield_outlined, size: 13, color: AppColors.amber),
                            const SizedBox(width: 4),
                            Text(t.s('safety'), style: const TextStyle(color: AppColors.amber, fontSize: 12)),
                          ]),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => g.removeAt(i),
                  icon: const Icon(Icons.delete_outline, color: AppColors.textLo),
                ),
              ],
            ),
          );
        },
      )),
      ]),
    );
  }
}

/// Domain selector row — switches the bundled glossary pack.
class _DomainRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final t = context.watch<UiLang>();
    return SizedBox(height: 44, child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      children: [
        for (final d in Domain.values) Padding(padding: const EdgeInsets.only(right: 6), child:
          ChoiceChip(
            label: Text(t.s('dom_${d.name}')),
            selected: s.domain == d,
            onSelected: (_) => s.setDomain(d),
            selectedColor: AppColors.accent.withValues(alpha: 0.2),
          )),
      ],
    ));
  }
}

void _addDialog(BuildContext context, Glossary g) {
  final srcCtrl = TextEditingController();
  final dstCtrl = TextEditingController();
  String srcLang = 'en';
  String dstLang = 'vi';
  bool safety = true;

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Add locked term'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: _langDrop(srcLang, (v) => setState(() => srcLang = v))),
                const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.arrow_forward, size: 18)),
                Expanded(child: _langDrop(dstLang, (v) => setState(() => dstLang = v))),
              ]),
              TextField(controller: srcCtrl, decoration: const InputDecoration(labelText: 'Source term')),
              TextField(controller: dstCtrl, decoration: const InputDecoration(labelText: 'Locked translation')),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: safety,
                activeColor: AppColors.amber,
                title: const Text('Safety term'),
                onChanged: (v) => setState(() => safety = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (srcCtrl.text.trim().isEmpty || dstCtrl.text.trim().isEmpty || srcLang == dstLang) {
                return;
              }
              g.add(GlossaryEntry(
                src: srcCtrl.text.trim(),
                dst: dstCtrl.text.trim(),
                srcLang: srcLang,
                dstLang: dstLang,
                safety: safety,
              ));
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

Widget _langDrop(String value, ValueChanged<String> onChanged) {
  return DropdownButton<String>(
    value: value,
    isExpanded: true,
    dropdownColor: AppColors.surfaceAlt,
    items: [
      for (final l in kLangs)
        DropdownMenuItem(value: l.code, child: Text('${l.flag} ${l.name}')),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}
