import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'util.dart';

const int schemaVersion = 1;
const elTypes = {'text', 'image', 'shape', 'ornament', 'qr', 'draw'};

/// مقاسات الورق بالمليمتر (عرض، ارتفاع)
const Map<String, List<double>> papers = {
  'A4L': [297, 210],
  'A4P': [210, 297],
  'A5L': [210, 148],
  'A5P': [148, 210],
  'LetterL': [279.4, 215.9],
  'LetterP': [215.9, 279.4],
  'custom': [250, 180],
};
const Map<String, String> paperNames = {
  'A4L': 'A4 أفقي',
  'A4P': 'A4 عمودي',
  'A5L': 'A5 أفقي',
  'A5P': 'A5 عمودي',
  'LetterL': 'Letter أفقي',
  'LetterP': 'Letter عمودي',
  'custom': 'مقاس مخصص',
};

/// عنصر تصميم. كل الأبعاد بالمليمتر وبإحداثيات الورقة (مستقلة عن الشاشة).
class El {
  El({
    String? id,
    required this.type,
    this.name = '',
    this.x = 0,
    this.y = 0,
    this.w = 40,
    this.h = 20,
    this.rot = 0,
    this.opacity = 1,
    this.locked = false,
    this.visible = true,
    this.group,
    Map<String, dynamic>? p,
  })  : id = id ?? uid(),
        p = p ?? {};

  String id, type, name;
  double x, y, w, h, rot, opacity;
  bool locked, visible;
  String? group;
  Map<String, dynamic> p;

  double nd(String k, double def) => (p[k] is num) ? (p[k] as num).toDouble() : def;
  int ni(String k, int def) => (p[k] is num) ? (p[k] as num).toInt() : def;
  String ns(String k, String def) => (p[k] is String) ? p[k] as String : def;
  bool nb(String k, bool def) => (p[k] is bool) ? p[k] as bool : def;
  Color col(String k, Color def) => (p[k] is num) ? Color((p[k] as num).toInt()) : def;
  Color? colN(String k) => (p[k] is num) ? Color((p[k] as num).toInt()) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'rot': rot,
        'op': opacity,
        'locked': locked,
        'visible': visible,
        if (group != null) 'group': group,
        'p': p,
      };

  factory El.fromJson(Map<String, dynamic> j) {
    final t = j['type'];
    if (t is! String || !elTypes.contains(t)) throw FormatException('نوع عنصر غير معروف: $t');
    double n(String k, double d) => (j[k] is num) ? (j[k] as num).toDouble() : d;
    final w = n('w', 40), h = n('h', 20);
    if (w <= 0 || h <= 0) throw const FormatException('أبعاد عنصر غير صالحة');
    return El(
      id: j['id'] is String ? j['id'] as String : null,
      type: t,
      name: j['name'] is String ? j['name'] as String : '',
      x: n('x', 0),
      y: n('y', 0),
      w: w,
      h: h,
      rot: n('rot', 0),
      opacity: n('op', 1).clamp(0.0, 1.0),
      locked: j['locked'] == true,
      visible: j['visible'] != false,
      group: j['group'] is String ? j['group'] as String : null,
      p: j['p'] is Map ? Map<String, dynamic>.from(j['p'] as Map) : {},
    );
  }

  El copy({bool newId = false}) {
    final c = El.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
    if (newId) c.id = uid();
    return c;
  }

  Offset get center => Offset(x + w / 2, y + h / 2);
}

class Design {
  Design({
    this.paper = 'A4L',
    this.w = 297,
    this.h = 210,
    this.bg = 0xFFFFFFFF,
    this.bg2,
    this.bgImage,
    List<El>? els,
  }) : els = els ?? [];

  String paper;
  double w, h;
  int bg;
  int? bg2;
  String? bgImage;
  List<El> els; // الفهرس 0 = الطبقة السفلى

  factory Design.blank({String paper = 'A4L'}) {
    final s = papers[paper] ?? papers['A4L']!;
    return Design(paper: paper, w: s[0], h: s[1]);
  }

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'paper': paper,
        'w': w,
        'h': h,
        'bg': bg,
        'bg2': bg2,
        'bgImage': bgImage,
        'els': els.map((e) => e.toJson()).toList(),
      };

  /// يرجع نص الخطأ أو null إذا كان المخطط صالحًا.
  static String? validate(dynamic j) {
    if (j is! Map) return 'التصميم ليس كائن JSON';
    final sc = j['schema'];
    if (sc is! num) return 'نسخة المخطط مفقودة';
    if (sc > schemaVersion) return 'نسخة مخطط أحدث من التطبيق (${sc.toInt()})';
    final w = j['w'], h = j['h'];
    if (w is! num || h is! num || w <= 0 || h <= 0 || w > 2000 || h > 2000) return 'أبعاد الورقة غير صالحة';
    if (j['els'] is! List) return 'قائمة العناصر مفقودة';
    final ids = <String>{};
    for (final e in j['els'] as List) {
      if (e is! Map) return 'عنصر غير صالح';
      if (e['type'] is! String || !elTypes.contains(e['type'])) return 'نوع عنصر غير معروف';
      final id = e['id'];
      if (id is String && !ids.add(id)) return 'معرّف عنصر مكرر: $id';
    }
    return null;
  }

  factory Design.fromJson(Map<String, dynamic> j) {
    final err = validate(j);
    if (err != null) throw FormatException(err);
    return Design(
      paper: j['paper'] is String ? j['paper'] as String : 'custom',
      w: (j['w'] as num).toDouble(),
      h: (j['h'] as num).toDouble(),
      bg: j['bg'] is num ? (j['bg'] as num).toInt() : 0xFFFFFFFF,
      bg2: j['bg2'] is num ? (j['bg2'] as num).toInt() : null,
      bgImage: j['bgImage'] is String ? j['bgImage'] as String : null,
      els: (j['els'] as List).map((e) => El.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
    );
  }

  Design clone() => Design.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);

  /// أسماء المتغيرات {{...}} المستخدمة في النصوص ورمز QR.
  Set<String> variables() {
    final s = <String>{};
    for (final e in els) {
      final t = e.type == 'text' ? e.ns('text', '') : (e.type == 'qr' ? e.ns('data', '') : '');
      for (final m in varRe.allMatches(t)) {
        s.add(m[1]!);
      }
    }
    return s;
  }
}

const Map<String, String> varLabels = {
  'recipient_name': 'اسم المستفيد',
  'course_name': 'اسم الدورة / المجال',
  'institution_name': 'اسم المؤسسة',
  'date': 'التاريخ',
  'grade': 'التقدير / الدرجة',
  'certificate_number': 'رقم الشهادة',
  'instructor_name': 'اسم المدرب',
  'duration': 'المدة',
  'signer_name': 'اسم المسؤول',
  'signer_title': 'صفة المسؤول',
};

const Map<String, String> sampleVars = {
  'recipient_name': 'محمد أحمد العلي',
  'course_name': 'الإدارة الحديثة',
  'date': '2026/11/10',
  'grade': 'ممتاز',
  'certificate_number': 'CERT-000001',
  'instructor_name': 'د. خالد المنصور',
  'duration': '20 ساعة',
};

/// حدود المستطيل المحيط بالعنصر بعد التدوير.
Rect elBounds(El e) {
  final cs = elCorners(e);
  var minX = cs[0].dx, maxX = cs[0].dx, minY = cs[0].dy, maxY = cs[0].dy;
  for (final c in cs) {
    minX = math.min(minX, c.dx);
    maxX = math.max(maxX, c.dx);
    minY = math.min(minY, c.dy);
    maxY = math.max(maxY, c.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

Offset rotOff(Offset v, double deg) {
  final a = deg * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

List<Offset> elCorners(El e) {
  final c = e.center;
  return [
    for (final v in [Offset(-e.w / 2, -e.h / 2), Offset(e.w / 2, -e.h / 2), Offset(e.w / 2, e.h / 2), Offset(-e.w / 2, e.h / 2)])
      c + rotOff(v, e.rot)
  ];
}

bool elHit(El e, Offset p, {double minSize = 4}) {
  final l = rotOff(p - e.center, -e.rot);
  final hw = math.max(e.w, minSize) / 2, hh = math.max(e.h, minSize) / 2;
  return l.dx.abs() <= hw && l.dy.abs() <= hh;
}
