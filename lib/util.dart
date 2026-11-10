import 'dart:math' as math;
import 'package:flutter/material.dart';

const navy = Color(0xFF14243A), gold = Color(0xFFC8A45D), paperGrey = Color(0xFFF3F5F8);
const double ptToMm = 25.4 / 72;

final _rnd = math.Random();
int _uidN = 0;
String uid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_uidN++).toRadixString(36)}${_rnd.nextInt(1296).toRadixString(36)}';

String two(int n) => n.toString().padLeft(2, '0');
String todayStr() {
  final d = DateTime.now();
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

String fileSafe(String s) {
  final r = s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_').trim();
  return r.isEmpty ? 'certificate' : r;
}

final RegExp arabicRe = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
final RegExp varRe = RegExp(r'\{\{\s*(\w+)\s*\}\}');

List<int>? _crcTable;
int crc32(List<int> data) {
  _crcTable ??= List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable![(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

void toast(BuildContext c, String m) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Future<bool> confirm(BuildContext c, String title, String body, {String ok = 'تأكيد'}) async {
  final r = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(title: Text(title), content: Text(body), actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ]));
  return r == true;
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String label = '', int lines = 1}) async {
  final tc = TextEditingController(text: initial);
  final r = await showDialog<String>(
      context: c,
      builder: (_) => AlertDialog(
              title: Text(title),
              content: TextField(controller: tc, autofocus: true, maxLines: lines, minLines: 1, decoration: InputDecoration(labelText: label)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
                FilledButton(onPressed: () => Navigator.pop(c, tc.text), child: const Text('حفظ')),
              ]));
  return r;
}
