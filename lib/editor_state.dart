import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'model.dart';
import 'util.dart';

El makeEl(Design d, String type, {String kind = '', String? text, String? src, double ar = 1}) {
  final cx = d.w / 2, cy = d.h / 2;
  El at(double w, double h, {Map<String, dynamic>? p, String name = ''}) =>
      El(type: type, name: name, x: cx - w / 2, y: cy - h / 2, w: w, h: h, p: p);
  switch (type) {
    case 'text':
      return at(math.min(120, d.w * 0.55), 14, name: 'نص', p: {
        'text': text ?? 'نص جديد', 'font': null, 'size': 22, 'color': 0xFF14243A, 'bold': false, 'italic': false,
        'ul': false, 'align': 'center', 'rtl': true, 'ls': 0, 'lh': 1.3, 'shadow': false, 'strokeW': 0,
        'strokeColor': 0xFF000000, 'fit': false, 'va': 'middle',
      });
    case 'image':
      final w = math.min(60.0, d.w * 0.3);
      return at(w, w / (ar <= 0 ? 1 : ar), name: 'صورة', p: {
        'src': src ?? '', 'fit': 'contain', 'lock': true, 'cl': 0, 'ct': 0, 'cr': 0, 'cb': 0, 'mask': 'none',
      });
    case 'shape':
      final sp = <String, dynamic>{'kind': kind, 'fill': 0xFFC8A45D, 'fill2': null, 'stroke': null, 'sw': 0, 'radius': 0, 'sides': 5, 'shadow': false, 'dash': false};
      switch (kind) {
        case 'square':
          sp['kind'] = 'rect';
          return at(40, 40, p: sp, name: 'مربع');
        case 'circle':
          sp['kind'] = 'ellipse';
          return at(40, 40, p: sp, name: 'دائرة');
        case 'line':
          sp
            ..['fill'] = null
            ..['stroke'] = 0xFF14243A
            ..['sw'] = 0.8;
          return at(90, 2, p: sp, name: 'خط');
        case 'triangle':
          return at(44, 38, p: sp, name: 'مثلث');
        case 'poly':
          sp['sides'] = 6;
          return at(42, 42, p: sp, name: 'مضلع');
        case 'star':
          sp['sides'] = 5;
          return at(44, 44, p: sp, name: 'نجمة');
        default:
          sp['kind'] = 'rect';
          return at(70, 38, p: sp, name: 'مستطيل');
      }
    case 'ornament':
      final op = <String, dynamic>{'kind': kind, 'color': 0xFFC8A45D, 'color2': 0xFF14243A, 'sw': 1.2};
      switch (kind) {
        case 'frame1':
        case 'frame2':
        case 'frame3':
        case 'frameIslamic':
        case 'corners':
        case 'cornersIslamic':
        case 'sideBars':
          return El(type: type, name: 'إطار/زخرفة', x: 8, y: 8, w: d.w - 16, h: d.h - 16, p: op);
        case 'starPattern':
          op['gap'] = 14;
          op['sw'] = 0.25;
          return El(type: type, name: 'نمط نجمي', x: 8, y: 8, w: d.w - 16, h: d.h - 16, opacity: 0.2, p: op);
        case 'rosette':
          return at(34, 34, p: op, name: 'ختم زخرفي');
        case 'ribbon':
          return at(110, 18, p: op, name: 'شريط');
        default:
          op['sw'] = 0.5;
          return at(100, 8, p: op, name: 'فاصل');
      }
    case 'qr':
      return at(28, 28, name: 'رمز QR', p: {'data': text ?? '{{certificate_number}}', 'color': 0xFF000000, 'bg': 0xFFFFFFFF});
  }
  return at(40, 20);
}

class SnapResult {
  SnapResult(this.dx, this.dy, this.gx, this.gy);
  final double dx, dy;
  final List<double> gx, gy;
}

/// متحكم المحرر: الحالة + التراجع/الإعادة + كل عمليات العناصر. منفصل عن الواجهة.
class EditorController extends ChangeNotifier {
  EditorController(this.design);
  Design design;
  final Set<String> sel = {};
  final List<String> _undo = [], _redo = [];
  bool dirty = false;
  int rev = 0;
  bool inGesture = false;
  String? _lastTag;
  DateTime _lastTime = DateTime(2000);
  List<double> guidesX = [], guidesY = [];
  static List<String> clip = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  List<El> get selected => design.els.where((e) => sel.contains(e.id)).toList();
  El? get single => sel.length == 1 ? byId(sel.first) : null;
  El? byId(String id) {
    for (final e in design.els) {
      if (e.id == id) return e;
    }
    return null;
  }

  void _push() {
    _undo.add(jsonEncode(design.toJson()));
    if (_undo.length > 80) _undo.removeAt(0);
    _redo.clear();
  }

  /// عملية قابلة للتراجع. [tag] يدمج التعديلات المتتالية المتشابهة (كالكتابة) في خطوة واحدة.
  void edit(void Function() fn, {String? tag}) {
    if (!inGesture) {
      final now = DateTime.now();
      final same = tag != null && tag == _lastTag && now.difference(_lastTime).inMilliseconds < 900;
      if (!same) _push();
      _lastTag = tag;
      _lastTime = now;
    }
    fn();
    dirty = true;
    rev++;
    notifyListeners();
  }

  /// السحب المتواصل: خطوة تراجع واحدة لكل إيماءة.
  void beginGesture() {
    if (!inGesture) {
      _push();
      inGesture = true;
      _lastTag = null;
    }
  }

  void endGesture() {
    inGesture = false;
    guidesX = [];
    guidesY = [];
    notifyListeners();
  }

  void _restore(String json) {
    design = Design.fromJson(jsonDecode(json) as Map<String, dynamic>);
    sel.removeWhere((id) => byId(id) == null);
    dirty = true;
    rev++;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(jsonEncode(design.toJson()));
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(jsonEncode(design.toJson()));
    _restore(_redo.removeLast());
  }

  // ---------- التحديد ----------
  void _expandGroups() {
    final gs = {for (final e in design.els) if (sel.contains(e.id) && e.group != null) e.group};
    if (gs.isEmpty) return;
    for (final e in design.els) {
      if (gs.contains(e.group)) sel.add(e.id);
    }
  }

  void selectOnly(String id) {
    sel
      ..clear()
      ..add(id);
    _expandGroups();
    notifyListeners();
  }

  void toggle(String id) {
    final e = byId(id);
    if (e == null) return;
    final ids = e.group == null ? [id] : design.els.where((x) => x.group == e.group).map((x) => x.id).toList();
    if (sel.contains(id)) {
      sel.removeAll(ids);
    } else {
      sel.addAll(ids);
    }
    notifyListeners();
  }

  void clearSel() {
    if (sel.isEmpty) return;
    sel.clear();
    notifyListeners();
  }

  void selectAll() {
    sel
      ..clear()
      ..addAll(design.els.where((e) => e.visible).map((e) => e.id));
    notifyListeners();
  }

  // ---------- إضافة/حذف/نسخ ----------
  void add(El e) => edit(() {
        design.els.add(e);
        sel
          ..clear()
          ..add(e.id);
      });

  void deleteSel() {
    final ids = selected.where((e) => !e.locked).map((e) => e.id).toSet();
    if (ids.isEmpty) return;
    edit(() {
      design.els.removeWhere((e) => ids.contains(e.id));
      sel.removeAll(ids);
    });
  }

  void deleteIds(Set<String> ids) => edit(() {
        design.els.removeWhere((e) => ids.contains(e.id));
        sel.removeAll(ids);
      });

  List<El> _cloneAll(Iterable<El> src, double off) {
    final gmap = <String, String>{};
    final out = <El>[];
    for (final e in src) {
      final c = e.copy(newId: true);
      c.x += off;
      c.y += off;
      if (c.group != null) c.group = gmap.putIfAbsent(c.group!, uid);
      c.locked = false;
      out.add(c);
    }
    return out;
  }

  void duplicate() {
    if (sel.isEmpty) return;
    final copies = _cloneAll(selected, 5);
    edit(() {
      design.els.addAll(copies);
      sel
        ..clear()
        ..addAll(copies.map((e) => e.id));
    });
  }

  void copy() {
    clip = selected.map((e) => jsonEncode(e.toJson())).toList();
  }

  bool get canPaste => clip.isNotEmpty;
  void paste() {
    if (clip.isEmpty) return;
    final src = clip.map((s) => El.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
    final copies = _cloneAll(src, 6);
    edit(() {
      design.els.addAll(copies);
      sel
        ..clear()
        ..addAll(copies.map((e) => e.id));
    });
  }

  // ---------- الترتيب ----------
  void reorder(String mode) {
    if (sel.isEmpty) return;
    edit(() {
      final l = design.els;
      switch (mode) {
        case 'front':
          final m = l.where((e) => sel.contains(e.id)).toList();
          l.removeWhere((e) => sel.contains(e.id));
          l.addAll(m);
          break;
        case 'back':
          final m = l.where((e) => sel.contains(e.id)).toList();
          l.removeWhere((e) => sel.contains(e.id));
          l.insertAll(0, m);
          break;
        case 'forward':
          for (var i = l.length - 2; i >= 0; i--) {
            if (sel.contains(l[i].id) && !sel.contains(l[i + 1].id)) {
              final t = l[i];
              l[i] = l[i + 1];
              l[i + 1] = t;
            }
          }
          break;
        case 'backward':
          for (var i = 1; i < l.length; i++) {
            if (sel.contains(l[i].id) && !sel.contains(l[i - 1].id)) {
              final t = l[i];
              l[i] = l[i - 1];
              l[i - 1] = t;
            }
          }
          break;
      }
    });
  }

  /// إعادة ترتيب من لوحة الطبقات (القائمة معروضة من الأعلى للأسفل = عكس المصفوفة).
  void reorderLayer(int oldIdx, int newIdx) {
    final n = design.els.length;
    if (newIdx > oldIdx) newIdx -= 1;
    final from = n - 1 - oldIdx, to = n - 1 - newIdx;
    if (from == to) return;
    edit(() {
      final e = design.els.removeAt(from);
      design.els.insert(to, e);
    });
  }

  void toggleVisible(String id) => edit(() {
        final e = byId(id);
        if (e != null) e.visible = !e.visible;
      });
  void toggleLock(String id) => edit(() {
        final e = byId(id);
        if (e != null) e.locked = !e.locked;
      });
  void lockSel() {
    final all = selected.every((e) => e.locked);
    edit(() {
      for (final e in selected) {
        e.locked = !all;
      }
    });
  }

  void rename(String id, String name) => edit(() {
        final e = byId(id);
        if (e != null) e.name = name;
      });

  // ---------- مجموعات ----------
  void group() {
    if (sel.length < 2) return;
    final g = uid();
    edit(() {
      for (final e in selected) {
        e.group = g;
      }
    });
  }

  void ungroup() => edit(() {
        for (final e in selected) {
          e.group = null;
        }
      });

  // ---------- المحاذاة والتوزيع ----------
  void align(String k) {
    final els = selected.where((e) => !e.locked).toList();
    if (els.isEmpty) return;
    Rect box;
    if (els.length == 1) {
      box = Rect.fromLTWH(0, 0, design.w, design.h);
    } else {
      box = els.map(elBounds).reduce((a, b) => a.expandToInclude(b));
    }
    edit(() {
      for (final e in els) {
        final b = elBounds(e);
        double dx = 0, dy = 0;
        switch (k) {
          case 'left':
            dx = box.left - b.left;
            break;
          case 'center':
            dx = box.center.dx - b.center.dx;
            break;
          case 'right':
            dx = box.right - b.right;
            break;
          case 'top':
            dy = box.top - b.top;
            break;
          case 'middle':
            dy = box.center.dy - b.center.dy;
            break;
          case 'bottom':
            dy = box.bottom - b.bottom;
            break;
        }
        e.x += dx;
        e.y += dy;
      }
    });
  }

  void distribute(bool horizontal) {
    final els = selected.where((e) => !e.locked).toList();
    if (els.length < 3) return;
    els.sort((a, b) => horizontal ? elBounds(a).center.dx.compareTo(elBounds(b).center.dx) : elBounds(a).center.dy.compareTo(elBounds(b).center.dy));
    final first = elBounds(els.first), last = elBounds(els.last);
    final span = horizontal ? last.right - first.left : last.bottom - first.top;
    final sum = els.fold<double>(0, (a, e) => a + (horizontal ? elBounds(e).width : elBounds(e).height));
    final gap = (span - sum) / (els.length - 1);
    edit(() {
      var pos = horizontal ? first.left : first.top;
      for (final e in els) {
        final b = elBounds(e);
        if (horizontal) {
          e.x += pos - b.left;
          pos += b.width + gap;
        } else {
          e.y += pos - b.top;
          pos += b.height + gap;
        }
      }
    });
  }

  void refresh() => notifyListeners();

  // ---------- أثناء الإيماءات (بعد beginGesture) ----------
  void _touch() {
    dirty = true;
    rev++;
    notifyListeners();
  }

  void moveTo(Map<String, Offset> starts, Offset d) {
    for (final e in design.els) {
      final s = starts[e.id];
      if (s != null) {
        e.x = s.dx + d.dx;
        e.y = s.dy + d.dy;
      }
    }
    _touch();
  }

  /// مقبض (sx,sy) ∈ {-1,0,1}. [e0] نسخة العنصر عند بدء السحب.
  void resizeFrom(El e0, int sx, int sy, Offset p, {bool keepAspect = false}) {
    final e = byId(e0.id);
    if (e == null) return;
    final opp = Offset(-sx * e0.w / 2, -sy * e0.h / 2);
    final anchor = e0.center + rotOff(opp, e0.rot);
    final v = rotOff(p - anchor, -e0.rot);
    double nw = sx == 0 ? e0.w : math.max(2, sx * v.dx);
    double nh = sy == 0 ? e0.h : math.max(2, sy * v.dy);
    if (keepAspect && sx != 0 && sy != 0) {
      final k = math.max(nw / e0.w, nh / e0.h);
      nw = e0.w * k;
      nh = e0.h * k;
    }
    final nc = anchor + rotOff(Offset(sx * nw / 2, sy * nh / 2), e0.rot);
    e.w = nw;
    e.h = nh;
    e.x = nc.dx - nw / 2;
    e.y = nc.dy - nh / 2;
    _touch();
  }

  void rotateTo(String id, Offset p) {
    final e = byId(id);
    if (e == null) return;
    final c = e.center;
    var a = math.atan2(p.dy - c.dy, p.dx - c.dx) * 180 / math.pi + 90;
    while (a > 180) {
      a -= 360;
    }
    while (a <= -180) {
      a += 360;
    }
    for (final t in [-180.0, -135.0, -90.0, -45.0, 0.0, 45.0, 90.0, 135.0, 180.0]) {
      if ((a - t).abs() < 3) a = t;
    }
    e.rot = a;
    _touch();
  }

  /// خطوط محاذاة ذكية: المنتصف/الحواف للورقة وللعناصر الأخرى.
  SnapResult snap(Rect r, double thr, Set<String> exclude) {
    final xs = <double>[0, design.w / 2, design.w], ys = <double>[0, design.h / 2, design.h];
    for (final e in design.els) {
      if (exclude.contains(e.id) || !e.visible) continue;
      final b = elBounds(e);
      xs.addAll([b.left, b.center.dx, b.right]);
      ys.addAll([b.top, b.center.dy, b.bottom]);
    }
    double best(List<double> cands, List<double> mine, List<double> guides) {
      var bd = thr, off = 0.0;
      for (final m in mine) {
        for (final c in cands) {
          final d = c - m;
          if (d.abs() < bd) {
            bd = d.abs();
            off = d;
          }
        }
      }
      if (bd < thr) {
        for (final m in mine) {
          for (final c in cands) {
            if ((c - (m + off)).abs() < 0.01) guides.add(c);
          }
        }
      }
      return bd < thr ? off : 0;
    }

    final gx = <double>[], gy = <double>[];
    final dx = best(xs, [r.left, r.center.dx, r.right], gx);
    final dy = best(ys, [r.top, r.center.dy, r.bottom], gy);
    return SnapResult(dx, dy, gx, gy);
  }

  // ---------- خصائص الصفحة ----------
  void setPaper(String key, {double? w, double? h}) => edit(() {
        final s = papers[key] ?? papers['custom']!;
        design.paper = key;
        design.w = w ?? s[0];
        design.h = h ?? s[1];
      });
}
