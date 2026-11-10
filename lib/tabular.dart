import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

/// جدول مستورد: عناوين + صفوف نصية.
class DataSheet {
  DataSheet(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

class TabException implements Exception {
  TabException(this.message);
  final String message;
  @override
  String toString() => message;
}

List<List<String>> parseCsv(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  // اكتشاف الفاصل من السطر الأول
  final firstLine = text.split('\n').first;
  final counts = {',': 0, ';': 0, '\t': 0};
  var inQ = false;
  for (final ch in firstLine.split('')) {
    if (ch == '"') inQ = !inQ;
    if (!inQ && counts.containsKey(ch)) counts[ch] = counts[ch]! + 1;
  }
  var delim = ',';
  var best = -1;
  counts.forEach((k, v) {
    if (v > best) {
      best = v;
      delim = k;
    }
  });
  final rows = <List<String>>[];
  var row = <String>[];
  final sb = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (q) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          q = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      q = true;
    } else if (ch == delim) {
      row.add(sb.toString());
      sb.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(sb.toString());
      sb.clear();
      rows.add(row);
      row = <String>[];
    } else {
      sb.write(ch);
    }
  }
  if (sb.isNotEmpty || row.isNotEmpty) {
    row.add(sb.toString());
    rows.add(row);
  }
  return rows;
}

String _cell(CellValue? v) {
  if (v == null) return '';
  if (v is IntCellValue) return v.value.toString();
  if (v is DoubleCellValue) {
    final d = v.value;
    return d == d.roundToDouble() ? d.round().toString() : d.toString();
  }
  if (v is DateCellValue) return '${v.year}/${v.month.toString().padLeft(2, '0')}/${v.day.toString().padLeft(2, '0')}';
  return v.toString();
}

DataSheet _build(List<List<String>> raw) {
  final rows = raw.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
  if (rows.isEmpty) throw TabException('الملف فارغ');
  var width = 0;
  for (final r in rows) {
    if (r.length > width) width = r.length;
  }
  final heads = <String>[];
  for (var i = 0; i < width; i++) {
    var h = i < rows.first.length ? rows.first[i].trim() : '';
    if (h.isEmpty) h = 'عمود ${i + 1}';
    while (heads.contains(h)) {
      h = '$h*';
    }
    heads.add(h);
  }
  final data = [
    for (final r in rows.skip(1)) [for (var i = 0; i < width; i++) i < r.length ? r[i].trim() : '']
  ];
  return DataSheet(heads, data);
}

/// يقرأ CSV أو XLSX. يرمي TabException برسالة عربية عند الملف التالف.
Future<DataSheet> readTable(String path) async {
  final ext = p.extension(path).toLowerCase();
  final bytes = await File(path).readAsBytes();
  if (bytes.isEmpty) throw TabException('الملف فارغ');
  if (ext == '.xlsx') {
    try {
      final ex = Excel.decodeBytes(Uint8List.fromList(bytes));
      for (final name in ex.tables.keys) {
        final sh = ex.tables[name]!;
        if (sh.rows.isEmpty) continue;
        final raw = [
          for (final r in sh.rows) [for (final c in r) _cell(c?.value)]
        ];
        return _build(raw);
      }
      throw TabException('لا توجد بيانات في ملف Excel');
    } on TabException {
      rethrow;
    } catch (_) {
      throw TabException('ملف Excel تالف أو غير مدعوم (استخدم xlsx)');
    }
  }
  if (ext == '.xls') throw TabException('صيغة xls القديمة غير مدعومة. احفظ الملف بصيغة xlsx أو csv.');
  final text = utf8.decode(bytes, allowMalformed: true);
  if (text.contains('\uFFFD')) {
    throw TabException('ترميز الملف غير UTF-8. احفظ ملف CSV بترميز UTF-8 ثم أعد المحاولة.');
  }
  return _build(parseCsv(text));
}
