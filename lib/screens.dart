import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'backup.dart';
import 'bulk.dart';
import 'license.dart';
import 'editor.dart';
import 'editor_panels.dart';
import 'model.dart';
import 'orgs.dart';
import 'painter.dart';
import 'store.dart';
import 'util.dart';

const thumbVars = {
  ...sampleVars,
  'institution_name': 'اسم المؤسسة',
  'signer_name': 'اسم المسؤول',
  'signer_title': 'المسمى الوظيفي',
};

/// صورة مصغرة حية لتصميم (تُرسم بنفس محرك الشهادة).
class DesignThumb extends StatefulWidget {
  const DesignThumb({super.key, required this.json, this.org, this.vars = thumbVars});
  final Map<String, dynamic> json;
  final Map<String, dynamic>? org;
  final Map<String, String> vars;
  @override
  State<DesignThumb> createState() => _DesignThumbState();
}

class _DesignThumbState extends State<DesignThumb> {
  Design? d;
  RenderCtx? ctx;
  @override
  void initState() {
    super.initState();
    try {
      d = Design.fromJson(Map<String, dynamic>.from(widget.json));
      final v = widget.org == null
          ? widget.vars
          : {for (final e in widget.vars.entries) if (!const {'institution_name', 'signer_name', 'signer_title'}.contains(e.key)) e.key: e.value};
      ctx = RenderCtx(vars: v, org: widget.org, keepUnknown: false, placeholders: false);
      ctx!.preload(d!).then((_) {
        if (mounted) setState(() {});
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (d == null) return const Center(child: Icon(Icons.broken_image));
    return AspectRatio(
      aspectRatio: d!.w / d!.h,
      child: Container(
        decoration: BoxDecoration(boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)], border: Border.all(color: Colors.black12)),
        child: RepaintBoundary(child: CustomPaint(painter: DesignPainter(d!, ctx!))),
      ),
    );
  }
}

void openEditor(BuildContext c, Store st, String projectId) {
  Navigator.push(c, MaterialPageRoute(builder: (_) => EditorScreen(store: st, projectId: projectId)));
}

Future<void> startProject(BuildContext c, Store st, String name, Design d, {String category = ''}) async {
  final pr = st.newProject(name, d, category: category);
  await st.save();
  if (c.mounted) openEditor(c, st, pr['id'] as String);
}

Future<void> newBlank(BuildContext c, Store st) async {
  var paper = 'A4L';
  final ok = await showDialog<bool>(
      context: c,
      builder: (_) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
                title: const Text('تصميم من الصفر'),
                content: chips<String>([for (final e in paperNames.entries) MapEntry(e.key, e.value)], paper, (v) => set(() => paper = v)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
                ],
              )));
  if (ok == true && c.mounted) await startProject(c, st, 'شهادة جديدة', Design.blank(paper: paper));
}

// ============ الرئيسية ============
class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.store, required this.go});
  final Store store;
  final void Function(int) go;
  @override
  Widget build(BuildContext context) {
    Widget big(IconData i, String t, VoidCallback on) => Expanded(
        child: Card(
            child: InkWell(
                onTap: on,
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Column(children: [Icon(i, size: 32, color: gold), const SizedBox(height: 6), Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)])))));
    final recentP = store.projects.take(8).toList();
    final recentC = store.certs.reversed.take(5).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: navy, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.workspace_premium, color: gold, size: 30)),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('صانع الشهادات الاحترافي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('Professional Certificate Maker', style: TextStyle(fontSize: 11, color: Colors.black54))])),
      ]),
      if (store.loadError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(store.loadError!, style: const TextStyle(color: Colors.red))),
      const SizedBox(height: 12),
      Row(children: [
        big(Icons.add_card, 'إنشاء شهادة جديدة', () => go(1)),
        big(Icons.brush, 'تصميم من الصفر', () => newBlank(context, store)),
      ]),
      Row(children: [
        big(Icons.groups, 'إصدار شهادات جماعية', () => Navigator.push(context, MaterialPageRoute(builder: (_) => BulkScreen(store: store)))),
        big(Icons.grid_view, 'تصفح القوالب', () => go(1)),
      ]),
      Row(children: [
        _stat('المشاريع المحفوظة', store.projects.length),
        _stat('الشهادات الصادرة', store.certs.length),
        _stat('المؤسسات', store.orgs.length),
      ]),
      const SizedBox(height: 12),
      Row(children: [const Text('آخر المشاريع', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: () => go(2), child: const Text('الكل'))]),
      if (recentP.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد مشاريع بعد. ابدأ من قالب أو من صفحة فارغة.'))
      else
        SizedBox(
            height: 130,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in recentP)
                GestureDetector(
                    onTap: () => openEditor(context, store, p['id'] as String),
                    child: Container(width: 150, margin: const EdgeInsets.only(left: 10), child: Column(children: [Expanded(child: DesignThumb(json: Map<String, dynamic>.from(p['design'] as Map), org: store.org(p['orgId'] as String?))), Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))]))),
            ])),
      const SizedBox(height: 12),
      Row(children: [const Text('الشهادات الصادرة مؤخرًا', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: () => go(3), child: const Text('الكل'))]),
      if (recentC.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لم تصدر شهادات بعد.')),
      for (final c in recentC) ListTile(dense: true, leading: const Icon(Icons.verified_outlined), title: Text('${c['name']}'), subtitle: Text('${c['number']} — ${c['date']}')),
    ]);
  }

  Widget _stat(String t, int n) => Expanded(
      child: Card(
          color: navy,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(children: [Text('$n', style: const TextStyle(color: gold, fontSize: 22, fontWeight: FontWeight.bold)), Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10), textAlign: TextAlign.center)]))));
}

// ============ القوالب ============
class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({super.key, required this.store});
  final Store store;
  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  String cat = 'all';
  Store get st => widget.store;

  @override
  Widget build(BuildContext context) {
    final cats = [
      const MapEntry('all', 'الكل'),
      if (st.userTemplates.isNotEmpty) const MapEntry('mine', 'قوالبي'),
      for (final c in st.categories) MapEntry(c['id'] as String, c['name'] as String),
    ];
    final list = [
      if (cat == 'all' || cat == 'mine') ...st.userTemplates,
      if (cat != 'mine') ...st.templates.where((t) => cat == 'all' || t['category'] == cat),
    ];
    return Column(children: [
      SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final c in cats) Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(c.value), selected: cat == c.key, onSelected: (_) => setState(() => cat = c.key))),
          ])),
      Expanded(
          child: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 240, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.9),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final t = list[i];
          return InkWell(
              onTap: () => _open(t),
              child: Column(children: [Expanded(child: Center(child: DesignThumb(json: Map<String, dynamic>.from(t['design'] as Map), org: st.defaultOrg))), const SizedBox(height: 4), Text(t['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))]));
        },
      )),
    ]);
  }

  void _open(Map<String, dynamic> t) {
    final mine = t['category'] == 'mine';
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (sc) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t['name'] as String, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(sc).size.height * 0.5), child: DesignThumb(json: Map<String, dynamic>.from(t['design'] as Map), org: st.defaultOrg)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(sc);
                          await startProject(context, st, t['name'] as String, Design.fromJson(Map<String, dynamic>.from(t['design'] as Map)).clone(), category: '${t['category']}');
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('استخدام القالب'))),
                if (mine) IconButton(onPressed: () async { Navigator.pop(sc); await st.deleteUserTemplate(t['id'] as String); setState(() {}); }, icon: const Icon(Icons.delete_outline)),
              ]),
            ])));
  }
}

// ============ المشاريع ============
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.store});
  final Store store;
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  String q = '';
  bool trash = false;
  Store get st => widget.store;

  @override
  Widget build(BuildContext context) {
    final src = trash ? st.trash : st.projects;
    final list = src.where((p) => q.isEmpty || (p['name'] as String).contains(q) || (p['category'] as String? ?? '').contains(q)).toList();
    return Column(children: [
      Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث في المشاريع', isDense: true, border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            FilterChip(label: Text('المحذوفات (${st.trash.length})'), selected: trash, onSelected: (v) => setState(() => trash = v)),
          ])),
      if (trash) Text('تُحذف نهائيًا بعد ${st.settings['retentionDays']} يومًا', style: const TextStyle(fontSize: 11, color: Colors.black54)),
      Expanded(
          child: list.isEmpty
              ? Center(child: Text(trash ? 'سلة المحذوفات فارغة' : 'لا توجد مشاريع'))
              : ListView(children: [
                  for (final p in list)
                    ListTile(
                      leading: SizedBox(width: 70, child: DesignThumb(json: Map<String, dynamic>.from(p['design'] as Map), org: st.org(p['orgId'] as String?))),
                      title: Text(p['name'] as String),
                      subtitle: Text('${(p['category'] as String?)?.isNotEmpty == true ? '${p['category']} — ' : ''}${DateTime.fromMillisecondsSinceEpoch(p['updated'] as int).toString().substring(0, 16)}'),
                      onTap: trash ? null : () => openEditor(context, st, p['id'] as String),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => _act(v, p),
                        itemBuilder: (_) => trash
                            ? const [PopupMenuItem(value: 'restore', child: Text('استعادة')), PopupMenuItem(value: 'purge', child: Text('حذف نهائي'))]
                            : const [PopupMenuItem(value: 'dup', child: Text('نسخ')), PopupMenuItem(value: 'ren', child: Text('إعادة تسمية')), PopupMenuItem(value: 'cat', child: Text('تصنيف')), PopupMenuItem(value: 'del', child: Text('حذف'))],
                      ),
                    ),
                ])),
    ]);
  }

  Future<void> _act(String v, Map<String, dynamic> p) async {
    final id = p['id'] as String;
    switch (v) {
      case 'dup':
        await st.duplicateProject(id);
      case 'ren':
        final n = await askText(context, 'اسم المشروع', initial: p['name'] as String);
        if (n != null && n.trim().isNotEmpty) {
          p['name'] = n.trim();
          await st.save();
        }
      case 'cat':
        final n = await askText(context, 'التصنيف', initial: p['category'] as String? ?? '');
        if (n != null) {
          p['category'] = n.trim();
          await st.save();
        }
      case 'del':
        await st.trashProject(id);
        if (mounted) toast(context, 'نُقل إلى المحذوفات');
      case 'restore':
        await st.restoreProject(id);
      case 'purge':
        if (await confirm(context, 'حذف نهائي', 'لا يمكن التراجع عن هذا الإجراء.')) await st.deleteProjectForever(id);
    }
    if (mounted) setState(() {});
  }
}

// ============ الشهادات الصادرة ============
class IssuedScreen extends StatefulWidget {
  const IssuedScreen({super.key, required this.store});
  final Store store;
  @override
  State<IssuedScreen> createState() => _IssuedScreenState();
}

class _IssuedScreenState extends State<IssuedScreen> {
  String q = '';
  Store get st => widget.store;
  @override
  Widget build(BuildContext context) {
    final list = st.certs.reversed.where((c) => q.isEmpty || '${c['name']} ${c['number']} ${c['projectName']}'.contains(q)).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(10), child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو الرقم', isDense: true, border: OutlineInputBorder()))),
      Expanded(
          child: list.isEmpty
              ? const Center(child: Text('لا توجد شهادات صادرة'))
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final exists = File(c['path'] as String).existsSync();
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.verified_outlined),
                      title: Text('${c['name']}'),
                      subtitle: Text('${c['number']} — ${c['orgName'] ?? ''} — ${c['date']} — ${(c['format'] as String).toUpperCase()}${exists ? '' : ' (الملف غير موجود)'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (exists) IconButton(icon: const Icon(Icons.share), onPressed: () => Share.shareXFiles([XFile(c['path'] as String)])),
                        IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(context, 'حذف السجل', 'حذف سجل الشهادة من الأرشيف؟')) {
                                st.certs.removeWhere((x) => x['id'] == c['id']);
                                await st.save();
                                setState(() {});
                              }
                            }),
                      ]),
                    );
                  })),
    ]);
  }
}

// ============ مكتبة العناصر ============
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, required this.store});
  final Store store;
  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  static const cats = {'logo': 'شعارات', 'signature': 'توقيعات', 'stamp': 'أختام', 'background': 'خلفيات', 'ornament': 'زخارف', 'other': 'أخرى'};
  String cat = 'all';
  bool favOnly = false;
  Store get st => widget.store;

  Future<void> _add() async {
    final p = await pickImagePath(st);
    if (p == null || !mounted) return;
    var c = 'other';
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                  title: const Text('تصنيف العنصر'),
                  content: chips<String>([for (final e in cats.entries) MapEntry(e.key, e.value)], c, (v) => set(() => c = v)),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة'))],
                )));
    if (ok == true) {
      await st.addAsset(p, p.split('/').last, c);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = st.assets.where((a) => (cat == 'all' || a['category'] == cat) && (!favOnly || a['fav'] == true)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('مكتبة العناصر')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_photo_alternate), label: const Text('إضافة من الجهاز')),
      body: Column(children: [
        SizedBox(
            height: 50,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(6), children: [
              Padding(padding: const EdgeInsets.all(3), child: FilterChip(avatar: const Icon(Icons.star, size: 16), label: const Text('المفضلة'), selected: favOnly, onSelected: (v) => setState(() => favOnly = v))),
              Padding(padding: const EdgeInsets.all(3), child: ChoiceChip(label: const Text('الكل'), selected: cat == 'all', onSelected: (_) => setState(() => cat = 'all'))),
              for (final e in cats.entries) Padding(padding: const EdgeInsets.all(3), child: ChoiceChip(label: Text(e.value), selected: cat == e.key, onSelected: (_) => setState(() => cat = e.key))),
            ])),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('العناصر المدمجة (الإطارات، الزخارف، الأشكال، الأختام الزخرفية، الخطوط) تُضاف من المحرر ← إضافة. هنا تدير ملفاتك الخاصة.', style: TextStyle(fontSize: 11, color: Colors.black54))),
        Expanded(
            child: list.isEmpty
                ? const Center(child: Text('لا توجد عناصر'))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 150, mainAxisSpacing: 10, crossAxisSpacing: 10),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final a = list[i];
                      return Card(
                          child: Stack(children: [
                        Positioned.fill(child: Padding(padding: const EdgeInsets.all(8), child: Image.file(File(a['path'] as String), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))),
                        Positioned(top: 0, right: 0, child: IconButton(iconSize: 20, icon: Icon(a['fav'] == true ? Icons.star : Icons.star_border, color: gold), onPressed: () async { a['fav'] = a['fav'] != true; await st.save(); setState(() {}); })),
                        Positioned(top: 0, left: 0, child: IconButton(iconSize: 20, icon: const Icon(Icons.delete_outline), onPressed: () async { await st.deleteAsset(a['id'] as String); setState(() {}); })),
                        Positioned(bottom: 2, left: 0, right: 0, child: Text(cats[a['category']] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                      ]));
                    })),
      ]),
    );
  }
}

// ============ المزيد + الإعدادات ============
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.store});
  final Store store;
  @override
  Widget build(BuildContext context) {
    Widget t(IconData i, String s, Widget Function() page) => ListTile(leading: Icon(i), title: Text(s), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page())));
    return ListView(children: [
      t(Icons.groups, 'الإصدار الجماعي', () => BulkScreen(store: store)),
      t(Icons.business, 'المؤسسات', () => OrgsScreen(store: store)),
      t(Icons.photo_library_outlined, 'مكتبة العناصر', () => AssetsScreen(store: store)),
      t(Icons.settings, 'الإعدادات والنسخ الاحتياطي', () => SettingsScreen(store: store)),
    ]);
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final Store store;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Store get st => widget.store;
  bool busy = false;

  Future<void> _backup() async {
    setState(() => busy = true);
    try {
      final f = await Backup.create(st);
      if (!mounted) return;
      final act = await showDialog<String>(
          context: context,
          builder: (_) => SimpleDialog(title: const Text('تم إنشاء النسخة'), children: [
                SimpleDialogOption(onPressed: () => Navigator.pop(context, 'save'), child: const Text('حفظ في مكان تختاره')),
                SimpleDialogOption(onPressed: () => Navigator.pop(context, 'share'), child: const Text('مشاركة')),
                SimpleDialogOption(onPressed: () => Navigator.pop(context, 'x'), child: const Text('إغلاق (محفوظة داخل التطبيق)')),
              ]));
      if (act == 'save') {
        await FilePicker.platform.saveFile(dialogTitle: 'حفظ النسخة', fileName: f.path.split('/').last, bytes: await f.readAsBytes());
      } else if (act == 'share') {
        await Share.shareXFiles([XFile(f.path)]);
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل النسخ الاحتياطي: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() => busy = true);
    try {
      final info = await Backup.inspect(path);
      if (!mounted) return;
      final m = info.manifest;
      final ok = await confirm(context, 'استعادة نسخة احتياطية', 'تاريخ النسخة: ${m['created']}\nمشاريع: ${m['projects']} — مؤسسات: ${m['orgs']}\n\nسيتم استبدال البيانات الحالية. تُحفظ نسخة منها تلقائيًا قبل الاستبدال.', ok: 'استعادة');
      if (ok) {
        await Backup.restore(st, info.archive);
        if (mounted) toast(context, 'تمت الاستعادة بنجاح');
      }
    } on BackupException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'فشلت الاستعادة: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = st.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (busy) const LinearProgressIndicator(),
        const Text('المظهر', style: TextStyle(fontWeight: FontWeight.bold)),
        chips<String>(const [MapEntry('system', 'النظام'), MapEntry('light', 'فاتح'), MapEntry('dark', 'داكن')], s['theme'] as String, (v) async {
          s['theme'] = v;
          await st.save();
          setState(() {});
        }),
        const Divider(height: 24),
        const Text('دقة التصدير الافتراضية (DPI)'),
        chips<int>(const [MapEntry(150, '150'), MapEntry(300, '300'), MapEntry(600, '600')], (s['dpi'] as num).toInt(), (v) async {
          s['dpi'] = v;
          await st.save();
          setState(() {});
        }),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('الحفظ التلقائي في المحرر'), value: s['autosave'] == true, onChanged: (v) async { s['autosave'] = v; await st.save(); setState(() {}); }),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('بادئة رقم الشهادة'),
            subtitle: Text(s['prefix'] as String),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final n = await askText(context, 'بادئة الرقم', initial: s['prefix'] as String);
              if (n != null) { s['prefix'] = n.trim(); await st.save(); setState(() {}); }
            }),
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('مدة الاحتفاظ بالمشاريع المحذوفة (يوم)'),
            subtitle: Text('${s['retentionDays']}'),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final n = await askText(context, 'عدد الأيام', initial: '${s['retentionDays']}');
              final v = int.tryParse(n ?? '');
              if (v != null && v > 0) { s['retentionDays'] = v; await st.save(); setState(() {}); }
            }),
        const Divider(height: 24),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(LicenseManager.I.active ? Icons.verified : Icons.lock_outline, color: LicenseManager.I.active ? Colors.green : Colors.orange),
            title: Text(LicenseManager.I.active ? 'مُفعَّل: PDF والطباعة متاحان' : 'غير مفعَّل: PDF والطباعة مقفلان'),
            subtitle: const Text('للتفعيل تواصل مع المبرمج $devName — $devPhone'),
            onTap: () async {
              await ensureActivated(context);
              if (mounted) setState(() {});
            }),
        const Divider(height: 24),
        const Text('النسخ الاحتياطي', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text('يشمل: المشاريع، المؤسسات، القوالب الخاصة، الأصول والصور، الإعدادات، الأرشيف. لا يشمل ملفات التصدير الناتجة.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          FilledButton.icon(onPressed: busy ? null : _backup, icon: const Icon(Icons.backup), label: const Text('إنشاء نسخة احتياطية')),
          OutlinedButton.icon(onPressed: busy ? null : _restore, icon: const Icon(Icons.restore), label: const Text('استعادة نسخة')),
        ]),
        const Divider(height: 24),
        Text('الخطوط المدمجة: ${st.fontList.length} خطًا (نصوص عربية، زخارف، رموز).', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        const Text('الإصدار 1.0.0 — يعمل دون اتصال بالإنترنت ولا يرسل أي بيانات خارج الجهاز.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]),
    );
  }
}
