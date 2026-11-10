import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:qr_flutter/qr_flutter.dart';
import 'model.dart';
import 'util.dart';

/// ذاكرة مؤقتة للصور المفكوكة (تُحدّ بعرض 3000px لتوفير الذاكرة).
class Imgs {
  final Map<String, ui.Image> _m = {};
  ui.Image? get(String? k) => k == null ? null : _m[k];
  bool has(String k) => _m.containsKey(k);

  Future<void> ensure(String k) async {
    if (_m.containsKey(k)) return;
    try {
      Uint8List bytes;
      if (k.startsWith('asset:')) {
        bytes = (await rootBundle.load(k.substring(6))).buffer.asUint8List();
      } else {
        final f = File(k);
        if (!await f.exists()) return;
        bytes = await f.readAsBytes();
      }
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final tw = desc.width > 3000 ? 3000 : desc.width;
      final codec = await desc.instantiateCodec(targetWidth: tw);
      final fr = await codec.getNextFrame();
      _m[k] = fr.image;
      codec.dispose();
      desc.dispose();
      buf.dispose();
    } catch (_) {}
  }

  void evict(String k) {
    _m.remove(k)?.dispose();
  }
}

final imgs = Imgs();

/// سياق الرسم: قيم المتغيرات + بيانات المؤسسة.
class RenderCtx {
  RenderCtx({this.vars = const {}, this.org, this.keepUnknown = true, this.placeholders = true});
  final Map<String, String> vars;
  final Map<String, dynamic>? org;
  final bool keepUnknown; // إبقاء {{x}} كما هي عند غياب القيمة (المحرر)
  final bool placeholders; // رسم مربعات بديلة للصور الناقصة (المحرر فقط)

  String? orgVar(String k) {
    final o = org;
    if (o == null) return null;
    switch (k) {
      case 'institution_name':
        return o['name'] as String?;
      case 'institution_address':
        return o['address'] as String?;
      case 'institution_phone':
        return o['phone'] as String?;
      case 'institution_email':
        return o['email'] as String?;
      case 'signer_name':
        return o['signer'] as String?;
      case 'signer_title':
        return o['signerTitle'] as String?;
    }
    return null;
  }

  String sub(String s) => s.replaceAllMapped(varRe, (m) {
        final k = m[1]!;
        final v = vars[k] ?? orgVar(k);
        if (v != null && v.isNotEmpty) return v;
        if (vars.containsKey(k)) return '';
        return keepUnknown ? m[0]! : '';
      });

  String? src(String s) {
    switch (s) {
      case '@org_logo':
        return org?['logo'] as String?;
      case '@org_signature':
        return org?['signature'] as String?;
      case '@org_stamp':
        return org?['stamp'] as String?;
    }
    return s.isEmpty ? null : s;
  }

  /// كل مسارات الصور التي يحتاجها التصميم.
  Set<String> imagePaths(Design d) {
    final r = <String>{};
    if (d.bgImage != null) r.add(d.bgImage!);
    for (final e in d.els) {
      if (e.type == 'image' && e.visible) {
        final s = src(e.ns('src', ''));
        if (s != null) r.add(s);
      }
    }
    return r;
  }

  Future<void> preload(Design d) async {
    for (final p in imagePaths(d)) {
      await imgs.ensure(p);
    }
  }
}

/// محرك الرسم الوحيد: يُستخدم في المعاينة وPDF وPNG وJPG.
class Cert {
  /// [s] = عدد البكسلات لكل مليمتر.
  static void paint(Canvas c, Design d, double s, RenderCtx ctx, {bool transparent = false}) {
    final r = Rect.fromLTWH(0, 0, d.w * s, d.h * s);
    c.save();
    c.clipRect(r);
    if (!transparent) {
      final p = Paint();
      if (d.bg2 != null) {
        p.shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [Color(d.bg), Color(d.bg2!)]);
      } else {
        p.color = Color(d.bg);
      }
      c.drawRect(r, p);
      final bi = imgs.get(d.bgImage);
      if (bi != null) _drawImg(c, bi, r, 'cover', 0, 0, 0, 0);
    }
    for (final e in d.els) {
      if (e.visible) paintEl(c, e, s, ctx);
    }
    c.restore();
  }

  static void paintEl(Canvas c, El e, double s, RenderCtx ctx) {
    final w = e.w * s, h = e.h * s;
    c.save();
    c.translate((e.x + e.w / 2) * s, (e.y + e.h / 2) * s);
    if (e.rot != 0) c.rotate(e.rot * math.pi / 180);
    c.translate(-w / 2, -h / 2);
    final layer = e.opacity < 0.999;
    if (layer) {
      c.saveLayer(Rect.fromLTWH(-6 * s, -6 * s, w + 12 * s, h + 12 * s),
          Paint()..color = Color.fromARGB((e.opacity * 255).round().clamp(0, 255), 0, 0, 0));
    }
    switch (e.type) {
      case 'text':
        _text(c, e, s, ctx, w, h);
        break;
      case 'shape':
        _shape(c, e, s, w, h);
        break;
      case 'ornament':
        _ornament(c, e, s, w, h);
        break;
      case 'image':
        _image(c, e, s, ctx, w, h);
        break;
      case 'qr':
        _qr(c, e, ctx, w, h);
        break;
      case 'draw':
        _draw(c, e, s, w, h);
        break;
    }
    if (layer) c.restore();
    c.restore();
  }

  // ---------------- النص ----------------
  static bool _hasArabic(String s) => arabicRe.hasMatch(s);

  static void _text(Canvas c, El e, double s, RenderCtx ctx, double w, double h) {
    final str = ctx.sub(e.ns('text', ''));
    if (str.isEmpty) return;
    final rtl = e.nb('rtl', true);
    final al = switch (e.ns('align', 'center')) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.center,
    };
    final strokeW = e.nd('strokeW', 0);
    final arabic = _hasArabic(str);

    TextPainter build(double m, bool strokePass) {
      final fs = math.max(0.5, e.nd('size', 18) * ptToMm * s * m);
      final family = e.p['font'] is String ? e.p['font'] as String : null;
      final base = TextStyle(
        fontSize: fs,
        fontFamily: family,
        fontWeight: e.nb('bold', false) ? FontWeight.w700 : FontWeight.w400,
        fontStyle: e.nb('italic', false) ? FontStyle.italic : FontStyle.normal,
        height: e.nd('lh', 1.3),
        // تباعد الحروف يفصل الحروف العربية المتصلة، لذلك لا يُطبَّق على العربية
        letterSpacing: arabic ? 0 : e.nd('ls', 0) * ptToMm * s,
        decoration: (!strokePass && e.nb('ul', false)) ? TextDecoration.underline : TextDecoration.none,
        decorationColor: e.col('color', Colors.black),
      );
      TextStyle st;
      if (strokePass) {
        st = base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeW * s
              ..strokeJoin = StrokeJoin.round
              ..color = e.col('strokeColor', Colors.black));
      } else {
        st = base.copyWith(
          color: e.col('color', Colors.black),
          shadows: e.nb('shadow', false)
              ? [Shadow(color: const Color(0x66000000), blurRadius: 0.8 * s, offset: Offset(0.4 * s, 0.4 * s))]
              : null,
        );
      }
      final ml = e.ni('maxLines', 0);
      return TextPainter(
        text: TextSpan(text: str, style: st),
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        textAlign: al,
        maxLines: ml > 0 ? ml : null,
      )..layout(minWidth: w, maxWidth: w);
    }

    var mul = 1.0;
    var tp = build(mul, false);
    if (e.nb('fit', false)) {
      var i = 0;
      while ((tp.height > h + 0.5 || tp.didExceedMaxLines) && i < 30 && mul > 0.2) {
        mul *= 0.94;
        tp = build(mul, false);
        i++;
      }
    }
    final va = e.ns('va', 'middle');
    final dy = va == 'top' ? 0.0 : (va == 'bottom' ? h - tp.height : (h - tp.height) / 2);
    if (strokeW > 0) build(mul, true).paint(c, Offset(0, dy));
    tp.paint(c, Offset(0, dy));
  }

  // ---------------- الأشكال ----------------
  static Path _poly(Rect r, int n) {
    final p = Path();
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      final pt = Offset(r.center.dx + r.width / 2 * math.cos(a), r.center.dy + r.height / 2 * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  static Path starPath(Offset c, double ro, double ri, int n, {double rot = -math.pi / 2, double sx = 1, double sy = 1}) {
    final p = Path();
    for (var i = 0; i < n * 2; i++) {
      final a = rot + math.pi * i / n;
      final r = i.isEven ? ro : ri;
      final pt = Offset(c.dx + sx * r * math.cos(a), c.dy + sy * r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  static Path shapePath(String kind, Rect r, double radius, int sides) {
    switch (kind) {
      case 'ellipse':
        return Path()..addOval(r);
      case 'triangle':
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case 'poly':
        return _poly(r, sides.clamp(3, 12));
      case 'star':
        final n = sides.clamp(3, 16);
        return starPath(r.center, 0.5, 0.22, n, sx: r.width, sy: r.height); // نصف القطر نسبي للعرض/الارتفاع
      default:
        return radius > 0
            ? (Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius))))
            : (Path()..addRect(r));
    }
  }

  static void _shape(Canvas c, El e, double s, double w, double h) {
    final kind = e.ns('kind', 'rect');
    final sw = e.nd('sw', 0) * s;
    final fill = e.colN('fill'), fill2 = e.colN('fill2'), stroke = e.colN('stroke');
    if (kind == 'line') {
      final col = stroke ?? fill ?? Colors.black;
      final p = Paint()
        ..color = col
        ..strokeWidth = math.max(sw, 0.3 * s)
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final a = Offset(0, h / 2), b = Offset(w, h / 2);
      if (e.nb('dash', false)) {
        final d = 3 * s;
        for (var x = 0.0; x < w; x += d * 2) {
          c.drawLine(Offset(x, h / 2), Offset(math.min(x + d, w), h / 2), p);
        }
      } else {
        c.drawLine(a, b, p);
      }
      return;
    }
    final r = Rect.fromLTWH(0, 0, w, h).deflate(sw / 2);
    if (r.width <= 0 || r.height <= 0) return;
    final path = shapePath(kind, r, e.nd('radius', 0) * s, e.ni('sides', 5));
    if (e.nb('shadow', false)) {
      c.drawPath(
          path.shift(Offset(0.8 * s, 0.8 * s)),
          Paint()
            ..color = const Color(0x55000000)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.9 * s));
    }
    if (fill != null) {
      final p = Paint()..style = PaintingStyle.fill;
      if (fill2 != null) {
        p.shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [fill, fill2]);
      } else {
        p.color = fill;
      }
      c.drawPath(path, p);
    }
    if (stroke != null && sw > 0) {
      c.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = stroke
            ..strokeWidth = sw
            ..strokeJoin = StrokeJoin.round);
    }
  }

  // ---------------- الزخارف والإطارات ----------------
  static void _bracket(Canvas c, double len, double sw, Color col, Color col2, bool islamic) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..color = col
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;
    c.drawPath(
        Path()
          ..moveTo(0, len)
          ..lineTo(0, 0)
          ..lineTo(len, 0),
        p);
    final g = sw * 2.4;
    c.drawPath(
        Path()
          ..moveTo(g, len * 0.7)
          ..lineTo(g, g)
          ..lineTo(len * 0.7, g),
        p..strokeWidth = sw * 0.45..color = col2);
    if (islamic) {
      c.drawPath(starPath(Offset(g * 2.2, g * 2.2), sw * 5, sw * 2.6, 8), Paint()..color = col);
      c.drawCircle(Offset(g * 2.2, g * 2.2), sw * 1.1, Paint()..color = col2);
    } else {
      c.drawCircle(Offset(g * 2.2, g * 2.2), sw * 1.5, Paint()..color = col);
    }
  }

  static void _ornament(Canvas c, El e, double s, double w, double h) {
    final kind = e.ns('kind', 'frame1');
    final col = e.col('color', gold), col2 = e.col('color2', navy);
    final sw = math.max(0.1, e.nd('sw', 1.2)) * s;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = col
      ..strokeWidth = sw;
    final full = Rect.fromLTWH(0, 0, w, h);
    switch (kind) {
      case 'frame1':
        c.drawRect(full.deflate(sw / 2), line);
        break;
      case 'frame2':
        c.drawRect(full.deflate(sw / 2), line);
        c.drawRect(full.deflate(sw * 3.4), Paint()
          ..style = PaintingStyle.stroke
          ..color = col2
          ..strokeWidth = sw * 0.4);
        break;
      case 'frame3':
      case 'frameIslamic':
        c.drawRect(full.deflate(sw * 0.8), line..strokeWidth = sw * 1.6);
        final inner = full.deflate(sw * 4.2);
        c.drawRect(inner, Paint()
          ..style = PaintingStyle.stroke
          ..color = col2
          ..strokeWidth = sw * 0.45);
        final fillP = Paint()..color = col;
        if (kind == 'frame3') {
          final q = sw * 1.4;
          for (final o in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
            c.drawRect(Rect.fromCenter(center: o, width: q * 2, height: q * 2), fillP);
          }
        } else {
          for (final o in [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight]) {
            c.drawPath(starPath(o, sw * 4.5, sw * 2.3, 8), fillP);
          }
          final gap = math.max(sw * 14, 1.0);
          final nx = (inner.width / gap).floor(), ny = (inner.height / gap).floor();
          for (var i = 1; i < nx; i++) {
            final x = inner.left + inner.width * i / nx;
            c.drawPath(starPath(Offset(x, inner.top), sw * 2, sw * 1, 8), fillP);
            c.drawPath(starPath(Offset(x, inner.bottom), sw * 2, sw * 1, 8), fillP);
          }
          for (var i = 1; i < ny; i++) {
            final y = inner.top + inner.height * i / ny;
            c.drawPath(starPath(Offset(inner.left, y), sw * 2, sw * 1, 8), fillP);
            c.drawPath(starPath(Offset(inner.right, y), sw * 2, sw * 1, 8), fillP);
          }
        }
        break;
      case 'corners':
      case 'cornersIslamic':
        final len = e.nd('len', 22) * s;
        for (final k in [
          [0.0, 0.0, 1.0, 1.0],
          [w, 0.0, -1.0, 1.0],
          [0.0, h, 1.0, -1.0],
          [w, h, -1.0, -1.0]
        ]) {
          c.save();
          c.translate(k[0], k[1]);
          c.scale(k[2], k[3]);
          _bracket(c, len, sw, col, col2, kind == 'cornersIslamic');
          c.restore();
        }
        break;
      case 'sideBars':
        final bw = sw * 2.2;
        final fp = Paint()..color = col;
        final tp = Paint()
          ..style = PaintingStyle.stroke
          ..color = col2
          ..strokeWidth = sw * 0.35;
        c.drawRect(Rect.fromLTWH(0, 0, bw, h), fp);
        c.drawRect(Rect.fromLTWH(w - bw, 0, bw, h), fp);
        c.drawLine(Offset(bw * 1.6, 0), Offset(bw * 1.6, h), tp);
        c.drawLine(Offset(w - bw * 1.6, 0), Offset(w - bw * 1.6, h), tp);
        break;
      case 'divider':
      case 'dividerStar':
        final cy = h / 2;
        final d = math.min(h / 2, sw * 3.2);
        final thin = Paint()
          ..style = PaintingStyle.stroke
          ..color = col
          ..strokeWidth = math.max(sw * 0.5, 0.5);
        c.drawLine(Offset(0, cy), Offset(w / 2 - d * 3.4, cy), thin);
        c.drawLine(Offset(w / 2 + d * 3.4, cy), Offset(w, cy), thin);
        final fp = Paint()..color = col2;
        if (kind == 'dividerStar') {
          c.drawPath(starPath(Offset(w / 2, cy), d * 1.2, d * 0.62, 8), Paint()..color = col);
        } else {
          Path dia(double cx, double r) => Path()
            ..moveTo(cx, cy - r)
            ..lineTo(cx + r, cy)
            ..lineTo(cx, cy + r)
            ..lineTo(cx - r, cy)
            ..close();
          c.drawPath(dia(w / 2, d), Paint()..color = col);
          c.drawPath(dia(w / 2 - d * 2.2, d * 0.5), fp);
          c.drawPath(dia(w / 2 + d * 2.2, d * 0.5), fp);
        }
        break;
      case 'rosette':
        final cc = Offset(w / 2, h / 2);
        final R = math.min(w, h) / 2;
        c.drawPath(starPath(cc, R, R * 0.9, 28),
            Paint()..shader = ui.Gradient.radial(cc, R, [col, Color.lerp(col, col2, 0.55)!]));
        c.drawCircle(cc, R * 0.74, Paint()
          ..style = PaintingStyle.stroke
          ..color = col2
          ..strokeWidth = math.max(R * 0.04, 0.5));
        c.drawPath(starPath(cc, R * 0.5, R * 0.22, 5), Paint()..color = col2);
        break;
      case 'starPattern':
        final gap = math.max(6.0, e.nd('gap', 14)) * s;
        final sp = Paint()
          ..style = PaintingStyle.stroke
          ..color = col
          ..strokeWidth = math.max(sw, 0.4);
        c.save();
        c.clipRect(full);
        for (var y = gap / 2; y < h + gap / 2; y += gap) {
          for (var x = gap / 2; x < w + gap / 2; x += gap) {
            c.drawPath(starPath(Offset(x, y), gap * 0.44, gap * 0.28, 8), sp);
          }
        }
        c.restore();
        break;
      case 'ribbon':
        final dx = math.min(w * 0.08, h * 0.9);
        final main = Paint()..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, h), [col, Color.lerp(col, col2, 0.4)!]);
        final tail = Paint()..color = col2;
        c.drawPath(
            Path()
              ..moveTo(0, h * 0.2)
              ..lineTo(dx * 1.2, h * 0.2)
              ..lineTo(dx * 1.2, h)
              ..lineTo(0, h)
              ..lineTo(dx * 0.4, h * 0.6)
              ..close(),
            tail);
        c.drawPath(
            Path()
              ..moveTo(w, h * 0.2)
              ..lineTo(w - dx * 1.2, h * 0.2)
              ..lineTo(w - dx * 1.2, h)
              ..lineTo(w, h)
              ..lineTo(w - dx * 0.4, h * 0.6)
              ..close(),
            tail);
        c.drawRect(Rect.fromLTWH(dx, 0, w - 2 * dx, h * 0.8), main);
        break;
    }
  }

  // ---------------- الصور ----------------
  static void _drawImg(Canvas c, ui.Image im, Rect dst, String fit, double cl, double ct, double cr, double cb) {
    final iw = im.width.toDouble(), ih = im.height.toDouble();
    final src = Rect.fromLTRB(iw * cl, ih * ct, iw * (1 - cr), ih * (1 - cb));
    if (src.width <= 1 || src.height <= 1) return;
    Rect d = dst;
    Rect sr = src;
    if (fit == 'contain') {
      final k = math.min(dst.width / src.width, dst.height / src.height);
      d = Rect.fromCenter(center: dst.center, width: src.width * k, height: src.height * k);
    } else if (fit == 'cover') {
      final k = math.max(dst.width / src.width, dst.height / src.height);
      final vw = dst.width / k, vh = dst.height / k;
      sr = Rect.fromCenter(center: src.center, width: vw, height: vh);
    }
    c.drawImageRect(im, sr, d, Paint()..filterQuality = FilterQuality.high..isAntiAlias = true);
  }

  static void _image(Canvas c, El e, double s, RenderCtx ctx, double w, double h) {
    final path = ctx.src(e.ns('src', ''));
    final im = imgs.get(path);
    final r = Rect.fromLTWH(0, 0, w, h);
    if (im == null) {
      if (ctx.placeholders) {
        final p = Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF9AA5B1)
          ..strokeWidth = math.max(0.4 * s, 1);
        c.drawRect(r.deflate(0.5), p);
        c.drawLine(r.topLeft, r.bottomRight, p);
        c.drawLine(r.topRight, r.bottomLeft, p);
      }
      return;
    }
    c.save();
    final mask = e.ns('mask', 'none');
    if (mask == 'circle') {
      c.clipPath(Path()..addOval(r));
    } else if (mask == 'round') {
      c.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(w, h) * 0.12)));
    } else {
      c.clipRect(r);
    }
    _drawImg(c, im, r, e.ns('fit', 'contain'), e.nd('cl', 0), e.nd('ct', 0), e.nd('cr', 0), e.nd('cb', 0));
    c.restore();
  }

  // ---------------- QR والتوقيع المرسوم ----------------
  static void _qr(Canvas c, El e, RenderCtx ctx, double w, double h) {
    final data = ctx.sub(e.ns('data', ''));
    if (data.trim().isEmpty) return;
    final side = math.min(w, h);
    final o = Offset((w - side) / 2, (h - side) / 2);
    final fg = e.col('color', Colors.black);
    c.save();
    c.translate(o.dx, o.dy);
    c.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = e.col('bg', Colors.white));
    try {
      final pad = side * 0.05;
      c.translate(pad, pad);
      QrPainter(
        data: data,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: fg),
        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: fg),
      ).paint(c, Size(side - 2 * pad, side - 2 * pad));
    } catch (_) {}
    c.restore();
  }

  static void _draw(Canvas c, El e, double s, double w, double h) {
    final strokes = e.p['strokes'];
    if (strokes is! List) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = e.col('color', navy)
      ..strokeWidth = math.max(0.2, e.nd('sw', 0.8)) * s;
    for (final st in strokes) {
      if (st is! List || st.length < 2) continue;
      final path = Path();
      for (var i = 0; i + 1 < st.length; i += 2) {
        final x = (st[i] as num).toDouble() * w, y = (st[i + 1] as num).toDouble() * h;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      if (st.length == 2) {
        c.drawCircle(Offset((st[0] as num).toDouble() * w, (st[1] as num).toDouble() * h), p.strokeWidth / 2, Paint()..color = p.color);
      } else {
        c.drawPath(path, p);
      }
    }
  }
}

/// رسّام ودجت جاهز لعرض تصميم (للبطاقات والمعاينات).
class DesignPainter extends CustomPainter {
  DesignPainter(this.design, this.ctx);
  final Design design;
  final RenderCtx ctx;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / design.w;
    Cert.paint(canvas, design, s, ctx);
  }

  @override
  bool shouldRepaint(covariant DesignPainter old) => true;
}
