import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'store.dart';
import 'util.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// نسخ احتياطي: ZIP يحوي data.json + media/ + manifest.json (يحوي الأحجام وcrc32 ونسخة المخطط).
/// ملفات التصدير والدفعات الناتجة لا تُضمَّن (هي مخرجات يمكن إعادة توليدها من الأرشيف).
class Backup {
  static const mediaToken = '@media/';

  static Future<File> create(Store st) async {
    final tmp = Directory('${st.dir.path}/tmp_backup')..createSync(recursive: true);
    for (final f in tmp.listSync()) {
      f.deleteSync(recursive: true);
    }
    var text = jsonEncode(st.s);
    text = text.replaceAll('${st.mediaDir.path}/', mediaToken);
    final dataBytes = utf8.encode(text);
    final files = <Map<String, dynamic>>[
      {'name': 'data.json', 'size': dataBytes.length, 'crc': crc32(dataBytes)}
    ];
    final dataFile = File('${tmp.path}/data.json')..writeAsBytesSync(dataBytes);
    final media = st.mediaDir.listSync().whereType<File>().toList();
    for (final m in media) {
      final b = await m.readAsBytes();
      files.add({'name': 'media/${m.uri.pathSegments.last}', 'size': b.length, 'crc': crc32(b)});
    }
    final manifest = {
      'app': 'professional_certificate_maker',
      'schema': dataSchema,
      'created': DateTime.now().toIso8601String(),
      'projects': st.projects.length,
      'orgs': st.orgs.length,
      'files': files,
    };
    final mf = File('${tmp.path}/manifest.json')..writeAsStringSync(jsonEncode(manifest));
    final d = DateTime.now();
    final out = File('${st.exportDir.path}/backup_${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}.zip');
    final enc = ZipFileEncoder()..create(out.path);
    enc.addFile(mf, 'manifest.json');
    enc.addFile(dataFile, 'data.json');
    for (final m in media) {
      enc.addFile(m, 'media/${m.uri.pathSegments.last}', ZipFileEncoder.STORE);
    }
    enc.close();
    tmp.deleteSync(recursive: true);
    return out;
  }

  /// يتحقق من سلامة النسخة ويرجع (manifest, archive). يرمي BackupException عند أي مشكلة.
  static Future<({Map<String, dynamic> manifest, Archive archive})> inspect(String path) async {
    Archive ar;
    try {
      ar = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    } catch (_) {
      throw BackupException('الملف ليس نسخة احتياطية صالحة (ZIP تالف)');
    }
    final mf = ar.findFile('manifest.json');
    if (mf == null) throw BackupException('manifest.json مفقود: النسخة غير صالحة');
    Map<String, dynamic> m;
    try {
      m = jsonDecode(utf8.decode(mf.content as List<int>)) as Map<String, dynamic>;
    } catch (_) {
      throw BackupException('manifest.json تالف');
    }
    if (m['app'] != 'professional_certificate_maker') throw BackupException('النسخة لا تخص هذا التطبيق');
    final sc = m['schema'];
    if (sc is! num || sc > dataSchema) throw BackupException('النسخة من إصدار أحدث من التطبيق (مخطط $sc) — حدّث التطبيق');
    for (final f in (m['files'] as List)) {
      final fm = f as Map<String, dynamic>;
      final af = ar.findFile(fm['name'] as String);
      if (af == null) throw BackupException('ملف مفقود في النسخة: ${fm['name']}');
      final b = af.content as List<int>;
      if (b.length != fm['size'] || crc32(b) != fm['crc']) throw BackupException('الملف تالف: ${fm['name']}');
    }
    return (manifest: m, archive: ar);
  }

  /// يستبدل البيانات الحالية. تُحفظ نسخة من البيانات الحالية في pre_restore_data.json أولًا.
  static Future<void> restore(Store st, Archive ar) async {
    final data = ar.findFile('data.json')!;
    final text = utf8.decode(data.content as List<int>).replaceAll(mediaToken, '${st.mediaDir.path}/');
    jsonDecode(text); // تحقق نهائي من صحة JSON قبل الكتابة
    if (await st.file.exists()) await st.file.copy('${st.dir.path}/pre_restore_data.json');
    for (final f in ar.files) {
      if (f.isFile && f.name.startsWith('media/')) {
        final name = f.name.substring(6);
        if (name.contains('/') || name.contains('..')) continue; // حماية من مسارات خبيثة
        File('${st.mediaDir.path}/$name').writeAsBytesSync(f.content as List<int>);
      }
    }
    final tmp = File('${st.dir.path}/certificates_data.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(st.file.path);
    await st.reload();
  }
}
