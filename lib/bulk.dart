import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'editor_panels.dart' show chips;
import 'export.dart';
import 'license.dart';
import 'model.dart';
import 'painter.dart';
import 'store.dart';
import 'tabular.dart';
import 'util.dart';

/// منفذ الإصدار الجماعي: تتابعي، يحفظ التقدم، قابل للإيقاف والاستكمال.
class BatchRunner {
  BatchRunner(this.store, this.b, this.design, this.org, this.rows);
  final Store store;
  final Map<String, dynamic> b;
  final Design design;
  final Map<String, dynamic>? org;
  final List<Map<String, String>> rows;
  bool stop = false;

  Directory get out => Directory('${store.batchDir.path}/${b['id']}');
  Map<String, dynamic> get o => b['opts'] as Map<String, dynamic>;

  Future<void> run(void Function() onProgress) async {
    final dpi = (o['dpi'] as num).toDouble();
    final wantPng = o['png'] == true || o['zip'] == true;
    final wantPdf = o['pdf'] == true;
    final png = Directory('${out.path}/png')..createSync(recursive: true);
    final jpg = Directory('${out.path}/jpg')..createSync(recursive: true);
    b['status'] = 'running';
    await store.save();
    final total = rows.length;
    while ((b['done'] as int) < total) {
      if (stop) {
        b['status'] = 'paused';
        await store.save();
        onProgress();
        return;
      }
      final i = b['done'] as int;
      final vars = rows[i];
      final number = vars['certificate_number']!;
      try {
        final ctx = RenderCtx(vars: vars, org: org, keepUnknown: false, placeholders: false);
        final r = await Exporter.render(design, ctx, dpi);
        if (wantPng) await File('${png.path}/${fileSafe(number)}.png').writeAsBytes(await Exporter.png(r.image));
        if (wantPdf) await File('${jpg.path}/${i.toString().padLeft(6, '0')}.jpg').writeAsBytes(await Exporter.jpg(r.image, 90));
        r.image.dispose();
        store.certs.removeWhere((c) => c['batchId'] == b['id'] && c['number'] == number);
        store.certs.add({
          'id': uid(),
          'number': number,
          'name': vars['recipient_name'] ?? '',
          'orgId': org?['id'],
          'orgName': org?['name'],
          'date': vars['date'] ?? todayStr(),
          'projectName': b['name'],
          'batchId': b['id'],
          'format': o['pdf'] == true ? 'pdf' : 'png',
          'path': '${png.path}/${fileSafe(number)}.png',
          'vars': vars,
          'issuedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (e) {
        b['errors'] = (b['errors'] as int) + 1;
      }
      b['done'] = i + 1;
      if ((i + 1) % 10 == 0) await store.save();
      onProgress();
      await Future<void>.delayed(Duration.zero); // أعد التحكم للواجهة
    }
    await _finalize(png, jpg);
    b['status'] = 'done';
    await store.save();
    onProgress();
  }

  Future<void> _finalize(Directory png, Directory jpg) async {
    final name = fileSafe(b['name'] as String);
    final results = <String>[];
    if (o['pdf'] == true) {
      final files = jpg.listSync().whereType<File>().toList()..sort((a, c) => a.path.compareTo(c.path));
      final chunk = (o['dpi'] as num) <= 150 ? 100 : 50; // حد الذاكرة عند دمج PDF
      final parts = (files.length / chunk).ceil();
      for (var k = 0; k < parts; k++) {
        final slice = files.skip(k * chunk).take(chunk);
        final pages = [for (final f in slice) await f.readAsBytes()];
        final bytes = await Exporter.pdf(pages, design);
        final fn = parts == 1 ? '$name.pdf' : '${name}_part${(k + 1).toString().padLeft(2, '0')}.pdf';
        final f = File('${out.path}/$fn');
        await f.writeAsBytes(bytes, flush: true);
        results.add(f.path);
      }
      if (jpg.existsSync()) jpg.deleteSync(recursive: true);
    }
    if (o['zip'] == true) {
      final zp = '${out.path}/$name.zip';
      final enc = ZipFileEncoder()..create(zp);
      for (final f in png.listSync().whereType<File>()) {
        enc.addFile(f, 'png/${f.uri.pathSegments.last}', ZipFileEncoder.STORE);
      }
      for (final r in results) {
        enc.addFile(File(r), r.split('/').last, ZipFileEncoder.STORE);
      }
      enc.close();
      results.add(zp);
    }
    if (o['png'] != true && png.existsSync()) png.deleteSync(recursive: true);
    b['results'] = results;
    if (o['png'] == true) b['pngDir'] = png.path;
  }
}

String numberFor(String prefix, int start, int digits, int i) => '$prefix${(start + i).toString().padLeft(digits, '0')}';

class BulkScreen extends StatefulWidget {
  const BulkScreen({super.key, required this.store});
  final Store store;
  @override
  State<BulkScreen> createState() => _BulkScreenState();
}

class _BulkScreenState extends State<BulkScreen> {
  Store get st => widget.store;
  Design? design;
  String designName = '';
  Map<String, dynamic>? org;
  DataSheet? sheet;
  String sheetName = '';
  final Map<String, String> colMap = {};
  final Map<String, TextEditingController> fixed = {};
  final prefix = TextEditingController();
  final startC = TextEditingController(text: '1');
  int digits = 6, dpi = 300, prev = 0;
  bool outPng = true, outPdf = false, outZip = false, skipDup = true;
  BatchRunner? runner;
  bool running = false;
  Map<String, dynamic>? curBatch;
  RenderCtx? prevCtx;

  @override
  void initState() {
    super.initState();
    prefix.text = st.settings['prefix'] as String;
    dpi = (st.settings['dpi'] as num).toInt() > 300 ? 300 : (st.settings['dpi'] as num).toInt();
    org = st.defaultOrg;
  }

  List<String> get vars => design == null ? [] : (design!.variables().toList()..remove('certificate_number'));

  Future<void> _chooseDesign() async {
    final items = <MapEntry<String, Map<String, dynamic>>>[
      for (final p in st.projects) MapEntry('مشروع: ${p['name']}', {'design': p['design'], 'name': p['name'], 'orgId': p['orgId']}),
      for (final t in st.userTemplates) MapEntry('قالبي: ${t['name']}', {'design': t['design'], 'name': t['name']}),
      for (final t in st.templates) MapEntry('قالب: ${t['name']}', {'design': t['design'], 'name': t['name']}),
    ];
    final r = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (_) => ListView(children: [for (final i in items) ListTile(title: Text(i.key), onTap: () => Navigator.pop(context, i.value))]));
    if (r == null) return;
    try {
      design = Design.fromJson(Map<String, dynamic>.from(r['design'] as Map));
    } catch (e) {
      if (mounted) toast(context, 'تصميم غير صالح: $e');
      return;
    }
    designName = r['name'] as String;
    if (r['orgId'] != null) org = st.org(r['orgId'] as String?) ?? org;
    fixed.clear();
    for (final v in vars) {
      fixed[v] = TextEditingController(text: v == 'date' ? todayStr() : '');
    }
    _autoMap();
    await _refreshPreviewCtx();
    setState(() {});
  }

  Future<void> _refreshPreviewCtx() async {
    if (design == null) return;
    final c = RenderCtx(org: org, keepUnknown: false, placeholders: false);
    await c.preload(design!);
    prevCtx = c;
  }

  void _autoMap() {
    colMap.clear();
    final s = sheet;
    if (s == null) return;
    const alias = {
      'recipient_name': ['recipient_name', 'name', 'الاسم', 'اسم', 'اسم المستفيد', 'اسم الطالب', 'اسم المتدرب'],
      'course_name': ['course_name', 'course', 'الدورة', 'اسم الدورة', 'المادة', 'البرنامج'],
      'grade': ['grade', 'التقدير', 'الدرجة', 'النتيجة'],
      'duration': ['duration', 'المدة', 'عدد الساعات'],
      'date': ['date', 'التاريخ'],
      'instructor_name': ['instructor_name', 'المدرب', 'اسم المدرب'],
      'institution_name': ['institution_name', 'المؤسسة', 'الجهة'],
    };
    for (final v in vars) {
      for (final h in s.headers) {
        final hl = h.trim().toLowerCase();
        if ((alias[v] ?? [v]).any((a) => a.toLowerCase() == hl) || varLabels[v] == h.trim()) {
          colMap[v] = h;
          break;
        }
      }
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'xlsx', 'xls', 'txt']);
    final path = r?.files.single.path;
    if (path == null) return;
    try {
      final s = await readTable(path);
      setState(() {
        sheet = s;
        sheetName = r!.files.single.name;
        prev = 0;
        _autoMap();
      });
      if (mounted) toast(context, 'تم استيراد ${s.rows.length} سجل');
    } on TabException catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'تعذر قراءة الملف: $e');
    }
  }

  Future<void> _manual() async {
    final t = await askText(context, 'أدخل الأسماء (اسم في كل سطر)', lines: 12);
    if (t == null) return;
    final names = t.split('\n').map((e) => e.trim()).toList();
    setState(() {
      sheet = DataSheet(['الاسم'], [for (final n in names) if (n.isNotEmpty) [n]]);
      sheetName = 'إدخال يدوي';
      _autoMap();
      prev = 0;
    });
  }

  /// يبني السجلات المربوطة ويصنفها: ok / empty / dup
  List<({Map<String, String> vars, String status})> _records() {
    final s = sheet;
    if (s == null || design == null) return [];
    final seen = <String>{};
    final out = <({Map<String, String> vars, String status})>[];
    for (final row in s.rows) {
      final m = <String, String>{};
      for (final v in vars) {
        final col = colMap[v];
        if (col != null && col.isNotEmpty) {
          final idx = s.headers.indexOf(col);
          m[v] = idx >= 0 && idx < row.length ? row[idx] : '';
        } else {
          m[v] = fixed[v]?.text.trim() ?? '';
        }
      }
      var status = 'ok';
      if (vars.contains('recipient_name')) {
        final n = (m['recipient_name'] ?? '').trim();
        if (n.isEmpty) {
          status = 'empty';
        } else if (!seen.add(n.toLowerCase())) {
          status = 'dup';
        }
      }
      out.add((vars: m, status: status));
    }
    return out;
  }

  Future<void> _start() async {
    final d = design;
    if (d == null || sheet == null) return;
    final recs = _records();
    final valid = [for (final r in recs) if (r.status == 'ok' || (r.status == 'dup' && !skipDup)) r.vars];
    if (valid.isEmpty) {
      toast(context, 'لا توجد سجلات صالحة للإصدار');
      return;
    }
    if (outPdf && !await ensureActivated(context)) return;
    if (!outPng && !outPdf && !outZip) {
      toast(context, 'اختر صيغة إخراج واحدة على الأقل');
      return;
    }
    final startN = int.tryParse(startC.text) ?? 1;
    final rows = <Map<String, String>>[];
    for (var i = 0; i < valid.length; i++) {
      rows.add({...valid[i], 'certificate_number': numberFor(prefix.text, startN, digits, i)});
    }
    final id = uid();
    final b = <String, dynamic>{
      'id': id,
      'name': designName,
      'total': rows.length,
      'done': 0,
      'errors': 0,
      'status': 'running',
      'design': d.toJson(),
      'orgId': org?['id'],
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'opts': {'dpi': dpi, 'png': outPng, 'pdf': outPdf, 'zip': outZip},
    };
    Directory('${st.batchDir.path}/$id').createSync(recursive: true);
    await File('${st.batchDir.path}/$id/rows.json').writeAsString(jsonEncode(rows));
    st.batches.add(b);
    await st.save();
    await _runBatch(b, d, rows);
  }

  Future<void> _resume(Map<String, dynamic> b) async {
    try {
      final d = Design.fromJson(Map<String, dynamic>.from(b['design'] as Map));
      final raw = jsonDecode(await File('${st.batchDir.path}/${b['id']}/rows.json').readAsString()) as List;
      final rows = [for (final r in raw) Map<String, String>.from(r as Map)];
      await _runBatch(b, d, rows);
    } catch (e) {
      if (mounted) toast(context, 'تعذر استكمال الدفعة: $e');
    }
  }

  Future<void> _runBatch(Map<String, dynamic> b, Design d, List<Map<String, String>> rows) async {
    final o = st.org(b['orgId'] as String?);
    final r = BatchRunner(st, b, d, o, rows);
    setState(() {
      runner = r;
      running = true;
      curBatch = b;
    });
    try {
      await r.run(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      b['status'] = 'paused';
      await st.save();
      if (mounted) toast(context, 'توقفت الدفعة: $e');
    }
    if (mounted) setState(() => running = false);
    if (b['status'] == 'done' && mounted) toast(context, 'اكتمل الإصدار: ${b['done']} شهادة');
  }

  Future<void> _share(Map<String, dynamic> b) async {
    final res = ((b['results'] as List?) ?? []).cast<String>();
    if (res.isEmpty) {
      toast(context, 'لا توجد ملفات مجمعة (PDF/ZIP). ملفات PNG في: ${b['pngDir'] ?? '-'}');
      return;
    }
    await Share.shareXFiles([for (final p in res) XFile(p)]);
  }

  @override
  Widget build(BuildContext context) {
    final recs = _records();
    final nOk = recs.where((r) => r.status == 'ok').length;
    final nEmpty = recs.where((r) => r.status == 'empty').length;
    final nDup = recs.where((r) => r.status == 'dup').length;
    return Scaffold(
      appBar: AppBar(title: const Text('الإصدار الجماعي')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (running && curBatch != null) _progressCard(),
        _card('1) القالب', [
          Text(design == null ? 'لم يتم اختيار قالب' : 'القالب: $designName'),
          const SizedBox(height: 6),
          FilledButton.icon(onPressed: running ? null : _chooseDesign, icon: const Icon(Icons.dashboard_customize), label: const Text('اختيار قالب / مشروع')),
          if (st.orgs.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: org?['id'] as String?,
              hint: const Text('المؤسسة'),
              items: [for (final o in st.orgs) DropdownMenuItem(value: o['id'] as String, child: Text(o['name'] as String))],
              onChanged: (v) async {
                org = st.org(v);
                await _refreshPreviewCtx();
                setState(() {});
              },
            ),
        ]),
        _card('2) مصدر البيانات', [
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: running ? null : _import, icon: const Icon(Icons.upload_file), label: const Text('CSV / Excel')),
            OutlinedButton.icon(onPressed: running ? null : _manual, icon: const Icon(Icons.edit_note), label: const Text('إدخال يدوي')),
          ]),
          if (sheet != null) ...[
            const SizedBox(height: 6),
            Text('$sheetName — ${sheet!.rows.length} سجل، ${sheet!.headers.length} عمود'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowHeight: 32,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 32,
                columns: [for (final h in sheet!.headers) DataColumn(label: Text(h, style: const TextStyle(fontSize: 12)))],
                rows: [
                  for (final r in sheet!.rows.take(5)) DataRow(cells: [for (final c in r) DataCell(Text(c, style: const TextStyle(fontSize: 12)))])
                ],
              ),
            ),
          ] else
            const Text('نموذج: assets/sample_data/sample_names.csv داخل المشروع', style: TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
        if (design != null && sheet != null) ...[
          _card('3) ربط الأعمدة بالمتغيرات', [
            for (final v in vars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 110, child: Text(varLabels[v] ?? v, style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: DropdownButton<String>(
                    isExpanded: true,
                    value: (colMap[v] ?? '').isEmpty || !sheet!.headers.contains(colMap[v]) ? '' : colMap[v],
                    items: [
                      const DropdownMenuItem(value: '', child: Text('— قيمة ثابتة —')),
                      for (final h in sheet!.headers) DropdownMenuItem(value: h, child: Text(h)),
                    ],
                    onChanged: (x) => setState(() => colMap[v] = x ?? ''),
                  )),
                  if ((colMap[v] ?? '').isEmpty) SizedBox(width: 110, child: TextField(controller: fixed[v], onChanged: (_) => setState(() {}), decoration: const InputDecoration(isDense: true, hintText: 'القيمة'))),
                ]),
              ),
          ]),
          _card('4) التحقق من البيانات', [
            Text('صالح: $nOk   |   أسماء فارغة: $nEmpty   |   مكرر: $nDup'),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('تخطي الأسماء المكررة'), value: skipDup, onChanged: (v) => setState(() => skipDup = v)),
            if (nEmpty > 0) const Text('السجلات ذات الاسم الفارغ تُستبعد دائمًا.', style: TextStyle(color: Colors.red, fontSize: 12)),
          ]),
          _card('5) معاينة سجل', [
            if (recs.isEmpty) const Text('لا توجد سجلات') else _previewBox(recs),
          ]),
          _card('6) الترقيم والإخراج', [
            Row(children: [
              Expanded(child: TextField(controller: prefix, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'بادئة الرقم'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: startC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'يبدأ من'))),
            ]),
            const SizedBox(height: 6),
            const Text('الدقة'),
            chips<int>(const [MapEntry(150, '150 DPI'), MapEntry(300, '300 DPI')], dpi, (v) => setState(() => dpi = v)),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('ملفات PNG منفصلة'), value: outPng, onChanged: (v) => setState(() => outPng = v ?? false)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('PDF مدمج${LicenseManager.I.active ? '' : ' 🔒 (يتطلب التفعيل)'} — يُقسَّم كل 50–100 صفحة'),
                value: outPdf,
                onChanged: (v) async {
                  if (v == true && !await ensureActivated(context)) return;
                  if (mounted) setState(() => outPdf = v ?? false);
                }),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('ملف ZIP للنتائج'), value: outZip, onChanged: (v) => setState(() => outZip = v ?? false)),
            const SizedBox(height: 8),
            FilledButton.icon(
                onPressed: running || (nOk + (skipDup ? 0 : nDup)) == 0 ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: Text('بدء الإصدار (${nOk + (skipDup ? 0 : nDup)} شهادة)')),
          ]),
        ],
        _prevBatches(),
      ]),
    );
  }

  Widget _card(String title, List<Widget> kids) => Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), ...kids])));

  Widget _progressCard() {
    final b = curBatch!;
    final total = b['total'] as int, done = b['done'] as int;
    return Card(
        color: gold.withOpacity(0.15),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Text('جارٍ الإصدار: $done / $total', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? 0 : done / total),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () => runner?.stop = true, icon: const Icon(Icons.pause), label: const Text('إيقاف (يمكن الاستكمال لاحقًا)')),
            ])));
  }

  Widget _previewBox(List<({Map<String, String> vars, String status})> recs) {
    if (prev >= recs.length) prev = 0;
    final r = recs[prev];
    final vars = {...r.vars, 'certificate_number': numberFor(prefix.text, int.tryParse(startC.text) ?? 1, digits, prev)};
    final ctx = RenderCtx(vars: vars, org: org, keepUnknown: false, placeholders: false);
    final d = design!;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: prev > 0 ? () => setState(() => prev--) : null, icon: const Icon(Icons.chevron_right)),
        Text('${prev + 1} / ${recs.length}  (${r.status == 'ok' ? 'صالح' : r.status == 'empty' ? 'اسم فارغ' : 'مكرر'})'),
        IconButton(onPressed: prev < recs.length - 1 ? () => setState(() => prev++) : null, icon: const Icon(Icons.chevron_left)),
      ]),
      AspectRatio(aspectRatio: d.w / d.h, child: Container(decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)]), child: CustomPaint(painter: DesignPainter(d, ctx)))),
    ]);
  }

  Widget _prevBatches() {
    final list = st.batches.reversed.toList();
    if (list.isEmpty) return const SizedBox();
    return _card('الدفعات السابقة', [
      for (final b in list)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(b['name'] as String),
          subtitle: Text('${b['done']} / ${b['total']} — ${b['status'] == 'done' ? 'مكتملة' : 'غير مكتملة (قابلة للاستكمال)'}${(b['errors'] as int) > 0 ? ' — أخطاء: ${b['errors']}' : ''}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (b['status'] != 'done') IconButton(tooltip: 'استكمال', icon: const Icon(Icons.play_circle_outline), onPressed: running ? null : () => _resume(b)),
            if (b['status'] == 'done') IconButton(tooltip: 'مشاركة النتائج', icon: const Icon(Icons.share), onPressed: () => _share(b)),
            IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline),
                onPressed: running
                    ? null
                    : () async {
                        if (!await confirm(context, 'حذف الدفعة', 'سيتم حذف ملفاتها من الجهاز. تبقى سجلات الأرشيف.')) return;
                        final dir = Directory('${st.batchDir.path}/${b['id']}');
                        if (dir.existsSync()) dir.deleteSync(recursive: true);
                        st.batches.removeWhere((x) => x['id'] == b['id']);
                        await st.save();
                        setState(() {});
                      }),
          ]),
        ),
    ]);
  }
}
