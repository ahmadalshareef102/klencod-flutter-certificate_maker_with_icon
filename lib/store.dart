import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FontLoader, AssetManifest;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'model.dart';
import 'util.dart';

const int dataSchema = 1;

Uint8List _removeWhite(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  if (im == null) return bytes;
  final out = im.convert(numChannels: 4);
  for (final px in out) {
    final mn = [px.r, px.g, px.b].reduce((a, b) => a < b ? a : b);
    if (mn > 238) {
      px.a = 0;
    } else if (mn > 205) {
      px.a = (255 * (238 - mn) / 33).round();
    }
  }
  return Uint8List.fromList(img.encodePng(out));
}

/// التخزين المحلي: ملف JSON واحد بكتابة ذرّية + نسخة سابقة (نفس أسلوب مشروع قعشان).
class Store extends ChangeNotifier {
  Map<String, dynamic> s = {};
  late Directory dir, mediaDir, exportDir, batchDir;
  late File file;
  String? loadError;
  List<Map<String, dynamic>> templates = [];
  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> fontList = [];
  Map<String, List<int>> glyphs = {};

  Future<void> init() async {
    dir = await getApplicationDocumentsDirectory();
    mediaDir = Directory('${dir.path}/media')..createSync(recursive: true);
    exportDir = Directory('${dir.path}/exports')..createSync(recursive: true);
    batchDir = Directory('${dir.path}/batches')..createSync(recursive: true);
    file = File('${dir.path}/certificates_data.json');
    await _load();
    await _loadTemplates();
    await _loadFonts();
    purgeTrash();
  }

  Future<void> _load() async {
    Map<String, dynamic>? read(File f) {
      try {
        if (!f.existsSync()) return null;
        final j = jsonDecode(f.readAsStringSync());
        return j is Map<String, dynamic> ? j : null;
      } catch (_) {
        return null;
      }
    }

    var d = read(file) ?? read(File('${dir.path}/certificates_data_prev.json'));
    d ??= {};
    final sc = d['schema'];
    if (sc is num && sc > dataSchema) {
      loadError = 'بيانات محفوظة بنسخة أحدث من التطبيق. حدّث التطبيق.';
      d = {};
    }
    d['schema'] = dataSchema;
    for (final k in ['orgs', 'projects', 'assets', 'certificates', 'batches', 'history', 'userTemplates']) {
      d[k] ??= <dynamic>[];
    }
    d['settings'] ??= <String, dynamic>{};
    d['counter'] ??= 0;
    s = d;
    final st = settings;
    st['theme'] ??= 'system';
    st['dpi'] ??= 300;
    st['prefix'] ??= 'CERT-';
    st['retentionDays'] ??= 30;
    st['autosave'] ??= true;
  }

  Future<void> reload() async {
    await _load();
    notifyListeners();
  }

  Future<void> _loadTemplates() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/templates/templates.json')) as Map<String, dynamic>;
      categories = (j['categories'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      templates = [];
      for (final t in (j['templates'] as List)) {
        final m = Map<String, dynamic>.from(t as Map);
        if (Design.validate(m['design']) == null) templates.add(m); // قالب غير صالح لا يُعرض
      }
    } catch (e) {
      loadError ??= 'تعذر تحميل القوالب: $e';
    }
  }

  /// تحميل الخطوط المدمجة من assets/fonts/fonts.json (كل خط بعائلة مستقلة).
  /// أي ملف TTF/OTF إضافي غير مذكور في fonts.json يُحمَّل أيضًا باسم الملف.
  Future<void> _loadFonts() async {
    try {
      final listed = <String>{};
      try {
        final j = jsonDecode(await rootBundle.loadString('assets/fonts/fonts.json')) as Map<String, dynamic>;
        for (final f in (j['fonts'] as List)) {
          final m = Map<String, dynamic>.from(f as Map);
          try {
            final fl = FontLoader(m['family'] as String)..addFont(rootBundle.load('assets/fonts/${m['file']}'));
            await fl.load();
            fontList.add(m);
            listed.add('assets/fonts/${m['file']}');
          } catch (_) {}
        }
        final g = jsonDecode(await rootBundle.loadString('assets/fonts/glyphs.json')) as Map<String, dynamic>;
        g.forEach((k, v) => glyphs[k] = (v as List).map((e) => (e as num).toInt()).toList());
      } catch (_) {}
      final man = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final a in man.listAssets()) {
        final low = a.toLowerCase();
        if (!a.startsWith('assets/fonts/') || listed.contains(a) || !(low.endsWith('.ttf') || low.endsWith('.otf'))) continue;
        final fam = p.basenameWithoutExtension(a).split(RegExp(r'[-\[_ ]')).first;
        final fl = FontLoader(fam)..addFont(rootBundle.load(a));
        await fl.load();
        fontList.add({'family': fam, 'label': fam, 'kind': 'text'});
      }
    } catch (_) {}
  }

  // ---------- حفظ ----------
  Timer? _debounce;
  Future<void> save() async {
    try {
      if (await file.exists()) await file.copy('${dir.path}/certificates_data_prev.json');
      final tmp = File('${dir.path}/certificates_data.tmp');
      await tmp.writeAsString(jsonEncode(s), flush: true);
      await tmp.rename(file.path);
    } catch (_) {}
    notifyListeners();
  }

  // ---------- الإعدادات ----------
  Map<String, dynamic> get settings => s['settings'] as Map<String, dynamic>;
  ThemeMode get themeMode => switch (settings['theme']) { 'dark' => ThemeMode.dark, 'light' => ThemeMode.light, _ => ThemeMode.system };

  // ---------- المؤسسات ----------
  List<Map<String, dynamic>> get orgs => (s['orgs'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic>? org(String? id) {
    for (final o in orgs) {
      if (o['id'] == id) return o;
    }
    return null;
  }

  Map<String, dynamic>? get defaultOrg {
    for (final o in orgs) {
      if (o['default'] == true) return o;
    }
    return orgs.isEmpty ? null : orgs.first;
  }

  Future<void> saveOrg(Map<String, dynamic> o) async {
    final i = orgs.indexWhere((x) => x['id'] == o['id']);
    if (i >= 0) {
      orgs[i] = o;
    } else {
      orgs.add(o);
    }
    if (orgs.length == 1) o['default'] = true;
    await save();
  }

  Future<void> deleteOrg(String id) async {
    final wasDef = org(id)?['default'] == true;
    orgs.removeWhere((o) => o['id'] == id);
    if (wasDef && orgs.isNotEmpty) orgs.first['default'] = true;
    await save();
  }

  Future<void> setDefaultOrg(String id) async {
    for (final o in orgs) {
      o['default'] = o['id'] == id;
    }
    await save();
  }

  // ---------- المشاريع ----------
  List<Map<String, dynamic>> get allProjects => (s['projects'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get projects => allProjects.where((x) => x['deletedAt'] == null).toList()
    ..sort((a, b) => (b['updated'] as int).compareTo(a['updated'] as int));
  List<Map<String, dynamic>> get trash => allProjects.where((x) => x['deletedAt'] != null).toList();
  Map<String, dynamic>? project(String id) {
    for (final x in allProjects) {
      if (x['id'] == id) return x;
    }
    return null;
  }

  Map<String, dynamic> newProject(String name, Design d, {String category = '', String? orgId}) {
    final pr = <String, dynamic>{
      'id': uid(),
      'name': name,
      'category': category,
      'orgId': orgId ?? defaultOrg?['id'],
      'created': DateTime.now().millisecondsSinceEpoch,
      'updated': DateTime.now().millisecondsSinceEpoch,
      'vars': <String, dynamic>{},
      'design': d.toJson(),
    };
    allProjects.add(pr);
    return pr;
  }

  Future<void> saveProject(Map<String, dynamic> pr, Design d) async {
    pr['design'] = d.toJson();
    pr['updated'] = DateTime.now().millisecondsSinceEpoch;
    await save();
  }

  Future<void> duplicateProject(String id) async {
    final src = project(id);
    if (src == null) return;
    final c = jsonDecode(jsonEncode(src)) as Map<String, dynamic>;
    c['id'] = uid();
    c['name'] = '${src['name']} (نسخة)';
    c['created'] = c['updated'] = DateTime.now().millisecondsSinceEpoch;
    allProjects.add(c);
    await save();
  }

  Future<void> trashProject(String id) async {
    project(id)?['deletedAt'] = DateTime.now().millisecondsSinceEpoch;
    await save();
  }

  Future<void> restoreProject(String id) async {
    project(id)?.remove('deletedAt');
    await save();
  }

  Future<void> deleteProjectForever(String id) async {
    allProjects.removeWhere((x) => x['id'] == id);
    await save();
  }

  void purgeTrash() {
    final days = (settings['retentionDays'] as num).toInt();
    final lim = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final before = allProjects.length;
    allProjects.removeWhere((x) => x['deletedAt'] is int && (x['deletedAt'] as int) < lim);
    if (allProjects.length != before) save();
  }

  // ---------- القوالب الخاصة ----------
  List<Map<String, dynamic>> get userTemplates => (s['userTemplates'] as List).cast<Map<String, dynamic>>();
  Future<void> saveAsTemplate(String name, Design d) async {
    userTemplates.add({'id': uid(), 'name': name, 'category': 'mine', 'style': 'custom', 'design': d.toJson()});
    await save();
  }

  Future<void> deleteUserTemplate(String id) async {
    userTemplates.removeWhere((t) => t['id'] == id);
    await save();
  }

  // ---------- الأصول ----------
  List<Map<String, dynamic>> get assets => (s['assets'] as List).cast<Map<String, dynamic>>();
  Future<String> importMedia(String src) async {
    final ext = p.extension(src).toLowerCase();
    final dst = '${mediaDir.path}/${uid()}${ext.isEmpty ? '.png' : ext}';
    await File(src).copy(dst);
    return dst;
  }

  Future<String> removeWhiteBg(String path) async {
    final bytes = await File(path).readAsBytes();
    final out = await compute(_removeWhite, bytes);
    final dst = '${mediaDir.path}/${uid()}.png';
    await File(dst).writeAsBytes(out);
    return dst;
  }

  Future<void> addAsset(String path, String name, String category) async {
    assets.add({'id': uid(), 'path': path, 'name': name, 'category': category, 'fav': false});
    await save();
  }

  Future<void> deleteAsset(String id) async {
    assets.removeWhere((a) => a['id'] == id);
    await save();
  }

  // ---------- الشهادات الصادرة ----------
  List<Map<String, dynamic>> get certs => (s['certificates'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get batches => (s['batches'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get history => (s['history'] as List).cast<Map<String, dynamic>>();

  String nextNumber({String? prefix}) {
    final n = (s['counter'] as num).toInt() + 1;
    s['counter'] = n;
    return '${prefix ?? settings['prefix']}${n.toString().padLeft(6, '0')}';
  }

  void addHistory(Map<String, dynamic> h) {
    history.add(h);
    if (history.length > 500) history.removeRange(0, history.length - 500);
  }
}
