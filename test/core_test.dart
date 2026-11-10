import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset;
import 'package:certificate_maker/editor_state.dart';
import 'package:certificate_maker/model.dart';
import 'package:certificate_maker/tabular.dart';
import 'package:certificate_maker/util.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  fontTests();
  group('القوالب', () {
    final j = jsonDecode(File('assets/templates/templates.json').readAsStringSync()) as Map<String, dynamic>;
    final tpls = (j['templates'] as List).cast<Map<String, dynamic>>();
    test('30 قالبًا على الأقل في 12 تصنيفًا', () {
      expect(tpls.length, greaterThanOrEqualTo(30));
      expect(tpls.map((t) => t['category']).toSet().length, 12);
    });
    test('كل قالب صالح وقابل للتحرير (عناصر مستقلة)', () {
      for (final t in tpls) {
        expect(Design.validate(t['design']), isNull, reason: t['name'] as String);
        final d = Design.fromJson(Map<String, dynamic>.from(t['design'] as Map));
        expect(d.els.length, greaterThan(8));
        expect(d.variables().contains('recipient_name'), isTrue);
      }
    });
  });

  group('التصميم', () {
    test('حفظ واسترجاع بلا فقد', () {
      final d = Design.blank();
      d.els.add(makeEl(d, 'text', text: 'مرحبا {{recipient_name}}'));
      d.els.add(makeEl(d, 'shape', kind: 'star'));
      final d2 = Design.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
      expect(d2.els.length, 2);
      expect(d2.variables(), {'recipient_name'});
    });
    test('رفض مخطط أحدث أو غير صالح', () {
      expect(Design.validate({'schema': 99, 'w': 10, 'h': 10, 'els': []}), isNotNull);
      expect(Design.validate({'schema': 1, 'w': -1, 'h': 10, 'els': []}), isNotNull);
      expect(Design.validate({'schema': 1, 'w': 10, 'h': 10, 'els': [{'type': 'zzz'}]}), isNotNull);
    });
  });

  group('المحرر', () {
    test('إضافة وحذف وتراجع وإعادة', () {
      final c = EditorController(Design.blank());
      c.add(makeEl(c.design, 'text'));
      expect(c.design.els.length, 1);
      c.deleteSel();
      expect(c.design.els.length, 0);
      c.undo();
      expect(c.design.els.length, 1);
      c.redo();
      expect(c.design.els.length, 0);
    });
    test('السحب المتواصل خطوة تراجع واحدة', () {
      final c = EditorController(Design.blank());
      final e = makeEl(c.design, 'shape', kind: 'rect');
      c.add(e);
      final x0 = e.x;
      final starts = {e.id: Offset(e.x, e.y)};
      c.beginGesture();
      for (var i = 1; i <= 50; i++) {
        c.moveTo(starts, Offset(i.toDouble(), 0));
      }
      c.endGesture();
      expect(c.byId(e.id)!.x, x0 + 50);
      c.undo();
      expect(c.byId(e.id)!.x, x0);
    });
    test('ترتيب الطبقات والمحاذاة والتجميع', () {
      final c = EditorController(Design.blank());
      final a = makeEl(c.design, 'shape', kind: 'rect');
      final b = makeEl(c.design, 'shape', kind: 'circle');
      c.add(a);
      c.add(b);
      c.selectOnly(a.id);
      c.reorder('front');
      expect(c.design.els.last.id, a.id);
      c.reorder('back');
      expect(c.design.els.first.id, a.id);
      c.align('left');
      expect(elBounds(a).left, closeTo(0, 0.001));
      c.selectAll();
      c.group();
      c.clearSel();
      c.selectOnly(a.id);
      expect(c.sel.length, 2); // التحديد يشمل المجموعة
    });
    test('تدوير وتغيير حجم', () {
      final c = EditorController(Design.blank());
      final e = makeEl(c.design, 'shape', kind: 'rect');
      c.add(e);
      c.beginGesture();
      c.rotateTo(e.id, e.center + const Offset(50, 0)); // يمين المركز => 180+... مع الالتقاط
      c.endGesture();
      expect(e.rot, anyOf(90.0, closeTo(90, 3)));
      final e0 = e.copy();
      e.rot = 0;
      c.beginGesture();
      c.resizeFrom(e0..rot = 0, 1, 1, Offset(e0.x + e0.w + 10, e0.y + e0.h + 10));
      c.endGesture();
      expect(c.byId(e.id)!.w, closeTo(e0.w + 10, 0.01));
    });
  });

  group('الاستيراد', () {
    test('CSV بعربي وفواصل وعلامات اقتباس', () {
      final rows = parseCsv('الاسم,الدورة\n"أحمد, علي",إدارة\nسارة,"تسويق ""متقدم"""\n');
      expect(rows.length, 3);
      expect(rows[1][0], 'أحمد, علي');
      expect(rows[2][1], 'تسويق "متقدم"');
    });
    test('فاصل منقوطة وBOM', () {
      final rows = parseCsv('\uFEFFa;b\n1;2');
      expect(rows[0], ['a', 'b']);
    });
    test('crc32', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    });
  });
}

void fontTests() {
  test('الخطوط المدمجة: كل ملف موجود وخطوط القوالب مسجلة', () {
    final man = jsonDecode(File('assets/fonts/fonts.json').readAsStringSync()) as Map<String, dynamic>;
    final fams = <String>{};
    for (final f in (man['fonts'] as List)) {
      expect(File('assets/fonts/${f['file']}').existsSync(), isTrue, reason: '${f['file']}');
      fams.add(f['family'] as String);
    }
    expect(fams.length, 20);
    final j = jsonDecode(File('assets/templates/templates.json').readAsStringSync()) as Map<String, dynamic>;
    for (final t in (j['templates'] as List)) {
      for (final e in (t['design']['els'] as List)) {
        final font = e['p']['font'];
        if (e['type'] == 'text' && font != null && font != 'serif') {
          expect(fams.contains(font), isTrue, reason: 'خط غير مسجل: $font');
        }
      }
    }
  });
}
