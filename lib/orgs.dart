import 'dart:io';
import 'package:flutter/material.dart';
import 'editor_panels.dart';
import 'store.dart';
import 'util.dart';

class OrgsScreen extends StatelessWidget {
  const OrgsScreen({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (ctx, _) => Scaffold(
        appBar: AppBar(title: const Text('المؤسسات')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrgEditScreen(store: store))),
            icon: const Icon(Icons.add),
            label: const Text('مؤسسة جديدة')),
        body: store.orgs.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد مؤسسات بعد. أضف مؤسسة ليُدرج شعارها وتوقيعها وختمها تلقائيًا في الشهادات.', textAlign: TextAlign.center)))
            : ListView(children: [
                for (final o in store.orgs)
                  ListTile(
                    leading: _logo(o['logo'] as String?),
                    title: Text(o['name'] as String),
                    subtitle: Text(o['default'] == true ? 'المؤسسة الافتراضية' : (o['signer'] as String? ?? '')),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrgEditScreen(store: store, org: o))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'def') await store.setDefaultOrg(o['id'] as String);
                        if (v == 'del' && await confirm(context, 'حذف المؤسسة', 'حذف «${o['name']}»؟ لن تتأثر الشهادات الصادرة سابقًا.')) {
                          await store.deleteOrg(o['id'] as String);
                        }
                      },
                      itemBuilder: (_) => const [PopupMenuItem(value: 'def', child: Text('جعلها افتراضية')), PopupMenuItem(value: 'del', child: Text('حذف'))],
                    ),
                  ),
              ]),
      ),
    );
  }

  Widget _logo(String? p) => CircleAvatar(
      backgroundColor: paperGrey,
      backgroundImage: (p != null && File(p).existsSync()) ? FileImage(File(p)) : null,
      child: (p != null && File(p).existsSync()) ? null : const Icon(Icons.business));
}

class OrgEditScreen extends StatefulWidget {
  const OrgEditScreen({super.key, required this.store, this.org});
  final Store store;
  final Map<String, dynamic>? org;
  @override
  State<OrgEditScreen> createState() => _OrgEditScreenState();
}

class _OrgEditScreenState extends State<OrgEditScreen> {
  late Map<String, dynamic> o;
  final Map<String, TextEditingController> tc = {};
  static const fields = {
    'name': 'اسم المؤسسة *',
    'address': 'العنوان',
    'phone': 'الهاتف',
    'email': 'البريد الإلكتروني',
    'signer': 'اسم المسؤول',
    'signerTitle': 'صفة المسؤول',
  };

  @override
  void initState() {
    super.initState();
    o = widget.org != null ? Map<String, dynamic>.from(widget.org!) : {'id': uid(), 'color1': 0xFF14243A, 'color2': 0xFFC8A45D};
    for (final k in fields.keys) {
      tc[k] = TextEditingController(text: (o[k] as String?) ?? '');
    }
  }

  Future<void> _pick(String key) async {
    final p = await pickImagePath(widget.store);
    if (p != null) setState(() => o[key] = p);
  }

  Widget _img(String key, String label) {
    final p = o[key] as String?;
    final ok = p != null && File(p).existsSync();
    return Column(children: [
      Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(8), color: Colors.white),
          child: ok ? Image.file(File(p), fit: BoxFit.contain) : const Icon(Icons.add_photo_alternate_outlined)),
      Text(label, style: const TextStyle(fontSize: 12)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: () => _pick(key), child: const Text('اختيار')),
        if (ok) IconButton(iconSize: 18, onPressed: () => setState(() => o.remove(key)), icon: const Icon(Icons.close)),
      ]),
      if (ok && key != 'logo')
        TextButton(
            onPressed: () async {
              final np = await widget.store.removeWhiteBg(p);
              setState(() => o[key] = np);
            },
            child: const Text('إزالة الخلفية', style: TextStyle(fontSize: 11))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.org == null ? 'مؤسسة جديدة' : 'تعديل المؤسسة'), actions: [
        TextButton(
            onPressed: () async {
              if (tc['name']!.text.trim().isEmpty) {
                toast(context, 'اسم المؤسسة مطلوب');
                return;
              }
              for (final e in tc.entries) {
                o[e.key] = e.value.text.trim();
              }
              await widget.store.saveOrg(o);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white))),
      ]),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        for (final f in fields.entries)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: tc[f.key], decoration: InputDecoration(labelText: f.value, border: const OutlineInputBorder()))),
        ColorRow('اللون الأساسي', o['color1'] as int?, (v) => setState(() => o['color1'] = v ?? 0xFF14243A)),
        ColorRow('اللون الثانوي', o['color2'] as int?, (v) => setState(() => o['color2'] = v ?? 0xFFC8A45D)),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_img('logo', 'الشعار'), _img('signature', 'التوقيع'), _img('stamp', 'الختم')]),
        const SizedBox(height: 10),
        const Text('تُدرج هذه البيانات تلقائيًا في كل شهادة تحتوي على {{institution_name}} و{{signer_name}} وعناصر الشعار/التوقيع/الختم.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
