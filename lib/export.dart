import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'license.dart';
import 'model.dart';
import 'painter.dart';

const double maxPixels = 40e6; // سقف أمان للذاكرة (A4 عند 600 DPI ≈ 35 ميغابكسل)

Uint8List _jpg(Map<String, dynamic> a) {
  final im = img.Image.fromBytes(
      width: a['w'] as int, height: a['h'] as int, bytes: (a['rgba'] as Uint8List).buffer, numChannels: 4);
  return Uint8List.fromList(img.encodeJpg(im, quality: a['q'] as int));
}

class Rendered {
  Rendered(this.image, this.dpi);
  final ui.Image image;
  final double dpi; // الدقة الفعلية بعد تطبيق السقف
}

class Exporter {
  /// يرسم التصميم بنفس محرك المعاينة. DPI يُخفَّض تلقائيًا إذا تجاوز السقف.
  static Future<Rendered> render(Design d, RenderCtx ctx, double dpi, {bool transparent = false}) async {
    await ctx.preload(d);
    var eff = dpi;
    final pxmm = dpi / 25.4;
    final total = (d.w * pxmm) * (d.h * pxmm);
    if (total > maxPixels) eff = dpi * math.sqrt(maxPixels / total);
    final k = eff / 25.4;
    final w = (d.w * k).round(), h = (d.h * k).round();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    Cert.paint(c, d, k, ctx, transparent: transparent);
    final pic = rec.endRecording();
    final im = await pic.toImage(w, h);
    pic.dispose();
    return Rendered(im, eff);
  }

  static Future<Uint8List> png(ui.Image im) async {
    final bd = await im.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  /// JPG عبر Isolate حتى لا يتجمد التطبيق. الخلفية المرسومة معتمة دائمًا.
  static Future<Uint8List> jpg(ui.Image im, int quality) async {
    final bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = Uint8List.fromList(bd!.buffer.asUint8List());
    return compute(_jpg, {'rgba': bytes, 'w': im.width, 'h': im.height, 'q': quality});
  }

  /// PDF: كل صفحة صورة JPEG مرسومة بمحرك التصميم (الخط العربي يظهر كما في المعاينة).
  /// [paperMm] مقاس الورق الناتج (null = مطابق للتصميم)، [marginMm] هامش الطباعة.
  static Future<Uint8List> pdf(List<Uint8List> jpgPages, Design d, {List<double>? paperMm, double marginMm = 0}) async {
    LicenseManager.I.require(); // PDF (ومنه الطباعة) يتطلب التفعيل
    final doc = pw.Document(compress: true);
    var pw_ = paperMm?[0] ?? d.w, ph = paperMm?[1] ?? d.h;
    if (paperMm != null && (d.w > d.h) != (pw_ > ph)) {
      final t = pw_;
      pw_ = ph;
      ph = t;
    }
    final fmt = PdfPageFormat(pw_ * PdfPageFormat.mm, ph * PdfPageFormat.mm, marginAll: marginMm * PdfPageFormat.mm);
    for (final b in jpgPages) {
      final image = pw.MemoryImage(b);
      doc.addPage(pw.Page(
          pageFormat: fmt,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
    }
    return Uint8List.fromList(await doc.save());
  }

  static Future<File> writeFile(Directory dir, String name, Uint8List bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}
