import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'editor_panels.dart';
import 'editor_state.dart';
import 'package:printing/printing.dart';
import 'export.dart';
import 'license.dart';
import 'model.dart';
import 'painter.dart';
import 'store.dart';
import 'util.dart';

enum _M { none, move, resize, rotate }

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.store, required this.projectId});
  final Store store;
  final String projectId;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WidgetsBindingObserver {
  late Map<String, dynamic> pr;
  late EditorController c;
  double zoom = 1;
  String panel = 'none';
  bool multi = false, _dragging = false, _saving = false;
  Timer? _auto;
  final Set<String> _tried = {};

  // حالة الإيماءة
  _M _mode = _M.none;
  int _ptrs = 0;
  Offset _start = Offset.zero;
  Map<String, Offset> _starts = {};
  Rect _startRect = Rect.zero;
  El? _e0;
  int _hx = 0, _hy = 0;
  bool _pending = false;
  double _scale = 1;
  static const double pad = 28;

  Store get store => widget.store;
  Map<String, dynamic>? get org => store.org(pr['orgId'] as String?) ?? store.defaultOrg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pr = store.project(widget.projectId)!;
    Design d;
    try {
      d = Design.fromJson(Map<String, dynamic>.from(pr['design'] as Map));
    } catch (_) {
      d = Design.blank();
    }
    c = EditorController(d)..addListener(_onChange);
    _ensureImgs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auto?.cancel();
    if (c.dirty) store.saveProject(pr, c.design);
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if ((s == AppLifecycleState.paused || s == AppLifecycleState.inactive) && c.dirty) _save();
  }

  void _onChange() {
    if (store.settings['autosave'] == true && c.dirty) {
      _auto?.cancel();
      _auto = Timer(const Duration(seconds: 2), _save);
    }
    _ensureImgs();
  }

  Future<void> _ensureImgs() async {
    final ctx = RenderCtx(org: org);
    var loaded = false;
    for (final p in ctx.imagePaths(c.design)) {
      if (!imgs.has(p) && _tried.add(p)) {
        await imgs.ensure(p);
        loaded = true;
      }
    }
    if (loaded && mounted) c.refresh();
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    await store.saveProject(pr, c.design);
    c.dirty = false;
    _saving = false;
    if (mounted) setState(() {});
  }

  // ---------------- الإيماءات ----------------
  Offset _mm(Offset local) => (local - const Offset(pad, pad)) / _scale;

  ({int sx, int sy, bool rot})? _handleAt(El e, Offset p, double thr) {
    final rp = e.center + rotOff(Offset(0, -e.h / 2 - 34 / _scale), e.rot);
    if ((p - rp).distance < thr) return (sx: 0, sy: 0, rot: true);
    const order = [
      [-1, -1], [1, -1], [1, 1], [-1, 1], [0, -1], [1, 0], [0, 1], [-1, 0]
    ];
    for (final o in order) {
      final pos = e.center + rotOff(Offset(o[0] * e.w / 2, o[1] * e.h / 2), e.rot);
      if ((p - pos).distance < thr) return (sx: o[0], sy: o[1], rot: false);
    }
    return null;
  }

  El? _topHit(Offset p) {
    for (final e in c.design.els.reversed) {
      if (e.visible && elHit(e, p)) return e;
    }
    return null;
  }

  void _down(PointerDownEvent ev) {
    _ptrs++;
    if (_ptrs > 1) {
      _mode = _M.none;
      setState(() => _dragging = false);
      return;
    }
    final p = _mm(ev.localPosition);
    _start = p;
    _mode = _M.none;
    _pending = false;
    final thr = 24 / _scale;
    final s = c.single;
    if (s != null && !s.locked) {
      final h = _handleAt(s, p, thr);
      if (h != null) {
        _e0 = s.copy();
        _mode = h.rot ? _M.rotate : _M.resize;
        _hx = h.sx;
        _hy = h.sy;
        _pending = true;
        setState(() => _dragging = true);
        return;
      }
    }
    final hit = _topHit(p);
    if (hit != null) {
      if (multi) {
        c.toggle(hit.id);
      } else if (!c.sel.contains(hit.id)) {
        c.selectOnly(hit.id);
      }
      final mv = c.selected.where((e) => !e.locked).toList();
      if (c.sel.contains(hit.id) && mv.isNotEmpty) {
        _mode = _M.move;
        _starts = {for (final e in mv) e.id: Offset(e.x, e.y)};
        _startRect = mv.map(elBounds).reduce((a, b) => a.expandToInclude(b));
        _pending = true;
        setState(() => _dragging = true);
      }
    } else if (!multi) {
      c.clearSel();
    }
  }

  void _move(PointerMoveEvent ev) {
    if (_ptrs > 1 || _mode == _M.none) return;
    final p = _mm(ev.localPosition);
    if (_pending) {
      if ((p - _start).distance * _scale < 4) return;
      c.beginGesture();
      _pending = false;
    }
    switch (_mode) {
      case _M.move:
        var d = p - _start;
        final sn = c.snap(_startRect.shift(d), 6 / _scale, c.sel);
        d += Offset(sn.dx, sn.dy);
        c.guidesX = sn.gx;
        c.guidesY = sn.gy;
        c.moveTo(_starts, d);
        break;
      case _M.resize:
        final e0 = _e0!;
        c.resizeFrom(e0, _hx, _hy, p, keepAspect: e0.type == 'image' && e0.nb('lock', true));
        break;
      case _M.rotate:
        c.rotateTo(_e0!.id, p);
        break;
      case _M.none:
        break;
    }
  }

  void _up(PointerEvent ev) {
    _ptrs = math.max(0, _ptrs - 1);
    if (_ptrs == 0) {
      _mode = _M.none;
      _pending = false;
      c.endGesture();
      if (_dragging) setState(() => _dragging = false);
    }
  }

  // ---------------- إضافة عناصر ----------------
  Future<void> _addImage() async {
    final p = await pickImagePath(store);
    if (p == null) return;
    _addAsset(p);
  }

  void _addAsset(String p) async {
    await imgs.ensure(p);
    final im = imgs.get(p);
    final ar = im == null ? 1.0 : im.width / im.height;
    c.add(makeEl(c.design, 'image', src: p, ar: ar));
  }

  Future<void> _replaceImage(El e) async {
    final p = await pickImagePath(store);
    if (p == null) return;
    final im = imgs.get(p);
    c.edit(() {
      e.p['src'] = p;
      if (im != null && e.nb('lock', true)) e.h = e.w / (im.width / im.height);
    });
  }

  Future<void> _signature() async {
    final r = await showDialog<List<List<double>>>(context: context, builder: (_) => const SignaturePad());
    if (r == null || r.isEmpty) return;
    var minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for (final s in r) {
      for (var i = 0; i + 1 < s.length; i += 2) {
        minX = math.min(minX, s[i]);
        maxX = math.max(maxX, s[i]);
        minY = math.min(minY, s[i + 1]);
        maxY = math.max(maxY, s[i + 1]);
      }
    }
    final bw = math.max(maxX - minX, 1.0), bh = math.max(maxY - minY, 1.0);
    final strokes = [
      for (final s in r) [for (var i = 0; i + 1 < s.length; i += 2) ...[(s[i] - minX) / bw, (s[i + 1] - minY) / bh]]
    ];
    var w = 60.0, h = 60 * bh / bw;
    if (h > 40) {
      h = 40;
      w = 40 * bw / bh;
    }
    final d = c.design;
    c.add(El(type: 'draw', name: 'توقيع مرسوم', x: d.w / 2 - w / 2, y: d.h / 2 - h / 2, w: w, h: h, p: {'strokes': strokes, 'color': 0xFF14243A, 'sw': 0.8}));
  }

  Future<void> _editText() async {
    final e = c.single;
    if (e == null) return;
    if (e.type == 'text') {
      final t = await askText(context, 'تحرير النص', initial: e.ns('text', ''), lines: 6);
      if (t != null) c.edit(() => e.p['text'] = t);
    } else if (e.type == 'qr') {
      final t = await askText(context, 'محتوى QR', initial: e.ns('data', ''));
      if (t != null) c.edit(() => e.p['data'] = t);
    }
  }

  void _togglePanel(String k) => setState(() => panel = panel == k ? 'none' : k);

  // ---------------- البناء ----------------
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (ctx, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: GestureDetector(
              onTap: () async {
                final n = await askText(context, 'اسم المشروع', initial: pr['name'] as String);
                if (n != null && n.trim().isNotEmpty) {
                  setState(() => pr['name'] = n.trim());
                  c.dirty = true;
                  _save();
                }
              },
              child: Text(pr['name'] as String, style: const TextStyle(fontSize: 16), overflow: TextOverflow.ellipsis)),
          actions: [
            IconButton(tooltip: 'تراجع', icon: const Icon(Icons.undo), onPressed: c.canUndo ? c.undo : null),
            IconButton(tooltip: 'إعادة', icon: const Icon(Icons.redo), onPressed: c.canRedo ? c.redo : null),
            IconButton(
                tooltip: 'حفظ',
                icon: Icon(c.dirty ? Icons.save_outlined : Icons.check_circle_outline),
                onPressed: () async {
                  await _save();
                  if (mounted) toast(context, 'تم الحفظ');
                }),
            IconButton(tooltip: 'تصدير', icon: const Icon(Icons.ios_share), onPressed: _export),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'all':
                    c.selectAll();
                  case 'tpl':
                    final n = await askText(context, 'اسم القالب', initial: pr['name'] as String);
                    if (n != null && n.trim().isNotEmpty) {
                      await store.saveAsTemplate(n.trim(), c.design);
                      if (mounted) toast(context, 'تم الحفظ في قوالبي');
                    }
                  case 'org':
                    _pickOrg();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('تحديد الكل')),
                PopupMenuItem(value: 'org', child: Text('مؤسسة المشروع')),
                PopupMenuItem(value: 'tpl', child: Text('حفظ كقالب خاص')),
              ],
            ),
          ],
        ),
        body: LayoutBuilder(builder: (ctx, bc) {
          final wide = bc.maxWidth >= 900;
          final main = Column(children: [
            Expanded(child: LayoutBuilder(builder: (_, b) => _canvas(b))),
            _zoomBar(),
            if (c.sel.isNotEmpty) _contextBar(),
            if (!wide && panel != 'none') SizedBox(height: math.min(300, bc.maxHeight * 0.42), child: _panel()),
            _toolBar(),
          ]);
          if (wide && panel != 'none') {
            return Row(children: [Expanded(child: main), SizedBox(width: 360, child: Material(elevation: 4, child: _panel()))]);
          }
          return main;
        }),
      ),
    );
  }

  Future<void> _pickOrg() async {
    final orgs = store.orgs;
    if (orgs.isEmpty) {
      toast(context, 'أضف مؤسسة أولًا من: المزيد ← المؤسسات');
      return;
    }
    final id = await showDialog<String>(
        context: context,
        builder: (dc) => SimpleDialog(title: const Text('اختر المؤسسة'), children: [
              for (final o in orgs) SimpleDialogOption(onPressed: () => Navigator.pop(dc, o['id'] as String), child: Text(o['name'] as String)),
            ]));
    if (id != null) {
      setState(() => pr['orgId'] = id);
      await store.save();
      _tried.clear();
      _ensureImgs();
    }
  }

  Widget _panel() {
    final body = switch (panel) {
      'props' => PropPanel(c: c, store: store, onReplaceImage: _replaceImage),
      'layers' => LayersPanel(c: c),
      'align' => AlignPanel(c: c),
      'page' => PagePanel(c: c, store: store),
      _ => AddPanel(c: c, store: store, onImage: _addImage, onAsset: _addAsset, onSignature: _signature),
    };
    return Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(children: [
          Container(
            height: 28,
            alignment: Alignment.centerLeft,
            child: IconButton(padding: EdgeInsets.zero, iconSize: 20, icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => setState(() => panel = 'none')),
          ),
          Expanded(child: body),
        ]));
  }

  Widget _toolBar() {
    Widget t(String k, IconData i, String l, {bool on = false, VoidCallback? tap}) => Expanded(
        child: InkWell(
            onTap: tap ?? () => _togglePanel(k),
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(i, size: 22, color: (on || panel == k) ? gold : null),
                  Text(l, style: TextStyle(fontSize: 10, color: (on || panel == k) ? gold : null)),
                ]))));
    return Material(
        elevation: 8,
        child: SafeArea(
            top: false,
            child: Row(children: [
              t('add', Icons.add_circle_outline, 'إضافة'),
              t('props', Icons.tune, 'خصائص'),
              t('align', Icons.align_horizontal_center, 'محاذاة'),
              t('layers', Icons.layers_outlined, 'طبقات'),
              t('page', Icons.crop_landscape, 'الصفحة'),
              t('multi', Icons.select_all, 'متعدد', on: multi, tap: () => setState(() => multi = !multi)),
            ])));
  }

  Widget _zoomBar() => Container(
        height: 36,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(children: [
          IconButton(iconSize: 18, onPressed: () => setState(() => zoom = math.max(0.5, zoom - 0.25)), icon: const Icon(Icons.zoom_out)),
          Expanded(child: Slider(value: zoom, min: 0.5, max: 4, onChanged: (v) => setState(() => zoom = v))),
          IconButton(iconSize: 18, onPressed: () => setState(() => zoom = math.min(4, zoom + 0.25)), icon: const Icon(Icons.zoom_in)),
          TextButton(onPressed: () => setState(() => zoom = 1), child: Text('${(zoom * 100).round()}% ملاءمة', style: const TextStyle(fontSize: 11))),
        ]),
      );

  Widget _contextBar() {
    Widget b(IconData i, String t, VoidCallback? on) => IconButton(tooltip: t, icon: Icon(i, size: 20), onPressed: on, visualDensity: VisualDensity.compact);
    final s = c.single;
    final allLocked = c.selected.isNotEmpty && c.selected.every((e) => e.locked);
    return Container(
      height: 42,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        if (s != null && (s.type == 'text' || s.type == 'qr')) b(Icons.edit, 'تحرير', _editText),
        b(Icons.copy, 'نسخ', c.copy),
        b(Icons.paste, 'لصق', c.canPaste ? c.paste : null),
        b(Icons.control_point_duplicate, 'تكرار', c.duplicate),
        b(Icons.delete_outline, 'حذف', c.deleteSel),
        b(allLocked ? Icons.lock : Icons.lock_open, 'قفل/فتح', c.lockSel),
        b(Icons.flip_to_front, 'إلى الأمام', () => c.reorder('front')),
        b(Icons.flip_to_back, 'إلى الخلف', () => c.reorder('back')),
        b(Icons.arrow_upward, 'تقديم طبقة', () => c.reorder('forward')),
        b(Icons.arrow_downward, 'تأخير طبقة', () => c.reorder('backward')),
        b(Icons.group_work_outlined, 'تجميع', c.sel.length > 1 ? c.group : null),
        b(Icons.workspaces_outline, 'فك التجميع', c.ungroup),
      ]),
    );
  }

  Widget _canvas(BoxConstraints b) {
    final d = c.design;
    final base = math.max(0.1, math.min((b.maxWidth - 24) / d.w, (b.maxHeight - 24) / d.h));
    _scale = base * zoom;
    final cw = d.w * _scale, ch = d.h * _scale;
    final ctx = RenderCtx(org: org);
    final phys = _dragging ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics();
    final content = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: SizedBox(
        width: cw + 2 * pad,
        height: ch + 2 * pad,
        child: CustomPaint(
          foregroundPainter: _Overlay(c, _scale),
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: DecoratedBox(
              decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 10)]),
              child: CustomPaint(size: Size(cw, ch), painter: _CanvasPainter(c, _scale, ctx)),
            ),
          ),
        ),
      ),
    );
    return Container(
      color: const Color(0xFF8A94A3),
      child: SingleChildScrollView(
        physics: phys,
        child: SingleChildScrollView(
          physics: phys,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: b.maxWidth, minHeight: b.maxHeight),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }

  // ---------------- التصدير ----------------
  Future<void> _export() async {
    await _save();
    if (!mounted) return;
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ExportSheet(store: store, pr: pr, design: c.design, org: org));
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.c, this.scale, this.ctx) : super(repaint: c);
  final EditorController c;
  final double scale;
  final RenderCtx ctx;
  @override
  void paint(Canvas canvas, Size size) => Cert.paint(canvas, c.design, scale, ctx);
  @override
  bool shouldRepaint(covariant _CanvasPainter o) => true;
}

class _Overlay extends CustomPainter {
  _Overlay(this.c, this.scale) : super(repaint: c);
  final EditorController c;
  final double scale;
  static const pad = _EditorScreenState.pad;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pad, pad);
    final d = c.design;
    final sel = c.selected;
    for (final e in sel) {
      final cs = elCorners(e).map((p) => p * scale).toList();
      final path = Path()..addPolygon(cs, true);
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = e.locked ? Colors.grey : const Color(0xFF2979FF));
    }
    final s = c.single;
    if (s != null && !s.locked) {
      final fill = Paint()..color = Colors.white;
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF2979FF);
      for (final o in const [
        [-1, -1], [1, -1], [1, 1], [-1, 1], [0, -1], [1, 0], [0, 1], [-1, 0]
      ]) {
        final pos = (s.center + rotOff(Offset(o[0] * s.w / 2, o[1] * s.h / 2), s.rot)) * scale;
        final r = Rect.fromCenter(center: pos, width: 11, height: 11);
        canvas.drawRect(r, fill);
        canvas.drawRect(r, line);
      }
      final top = (s.center + rotOff(Offset(0, -s.h / 2), s.rot)) * scale;
      final rp = (s.center + rotOff(Offset(0, -s.h / 2 - 34 / scale), s.rot)) * scale;
      canvas.drawLine(top, rp, line);
      canvas.drawCircle(rp, 7, fill);
      canvas.drawCircle(rp, 7, line);
    }
    final gp = Paint()
      ..color = const Color(0xFFE91E63)
      ..strokeWidth = 1;
    for (final x in c.guidesX) {
      canvas.drawLine(Offset(x * scale, 0), Offset(x * scale, d.h * scale), gp);
    }
    for (final y in c.guidesY) {
      canvas.drawLine(Offset(0, y * scale), Offset(d.w * scale, y * scale), gp);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _Overlay o) => true;
}

/// لوحة رسم التوقيع باللمس.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> strokes = [];
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ارسم التوقيع'),
      content: Container(
        width: 320,
        height: 180,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
        child: GestureDetector(
          onPanStart: (d) => setState(() => strokes.add([d.localPosition])),
          onPanUpdate: (d) => setState(() => strokes.last.add(d.localPosition)),
          child: CustomPaint(painter: _PadPainter(strokes), size: Size.infinite),
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(strokes.clear), child: const Text('مسح')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, [
                  for (final s in strokes) [for (final p in s) ...[p.dx, p.dy]]
                ]),
            child: const Text('إضافة')),
      ],
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes);
  final List<List<Offset>> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = navy
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.5, Paint()..color = navy);
        continue;
      }
      canvas.drawPath(Path()..addPolygon(s, false), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter o) => true;
}

/// نافذة التصدير: PDF / PNG / JPG مع الدقة والهوامش وقيم المتغيرات.
class ExportSheet extends StatefulWidget {
  const ExportSheet({super.key, required this.store, required this.pr, required this.design, required this.org});
  final Store store;
  final Map<String, dynamic> pr;
  final Design design;
  final Map<String, dynamic>? org;
  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  String fmt = 'pdf';
  int dpi = 300, quality = 92;
  bool transparent = false;
  double margin = 0;
  String paper = 'same';
  late TextEditingController name;
  final Map<String, TextEditingController> vars = {};
  bool busy = false;
  String? resultPath;
  Uint8List? resultBytes;
  String? info;

  @override
  void initState() {
    super.initState();
    dpi = (widget.store.settings['dpi'] as num).toInt();
    name = TextEditingController(text: fileSafe(widget.pr['name'] as String));
    final saved = Map<String, dynamic>.from((widget.pr['vars'] as Map?) ?? {});
    final o = widget.org;
    for (final k in widget.design.variables()) {
      if (k == 'certificate_number') continue;
      final orgHas = o != null && RenderCtx(org: o).orgVar(k)?.isNotEmpty == true;
      if (orgHas) continue;
      vars[k] = TextEditingController(text: (saved[k] as String?) ?? (k == 'date' ? todayStr() : ''));
    }
  }

  Future<void> _run({bool printIt = false}) async {
    final f = printIt ? 'pdf' : fmt;
    if (f == 'pdf' && !await ensureActivated(context)) return;
    if (!mounted) return;
    setState(() {
      busy = true;
      info = null;
    });
    try {
      final st = widget.store;
      final v = {for (final e in vars.entries) e.key: e.value.text.trim()};
      widget.pr['vars'] = Map<String, dynamic>.from(v);
      final number = st.nextNumber();
      final all = {...v, 'certificate_number': number};
      final ctx = RenderCtx(vars: all, org: widget.org, keepUnknown: false, placeholders: false);
      final d = widget.design;
      final r = await Exporter.render(d, ctx, dpi.toDouble(), transparent: f == 'png' && transparent);
      Uint8List bytes;
      String ext;
      if (f == 'png') {
        bytes = await Exporter.png(r.image);
        ext = 'png';
      } else {
        final jb = await Exporter.jpg(r.image, quality);
        if (f == 'jpg') {
          bytes = jb;
          ext = 'jpg';
        } else {
          List<double>? pm;
          if (paper == 'A4') pm = [297, 210];
          if (paper == 'A5') pm = [210, 148];
          if (paper == 'Letter') pm = [279.4, 215.9];
          bytes = await Exporter.pdf([jb], d, paperMm: pm, marginMm: margin);
          ext = 'pdf';
        }
      }
      r.image.dispose();
      final fname = '${fileSafe(name.text)}_$number.$ext';
      final file = await Exporter.writeFile(st.exportDir, fname, bytes);
      final recipient = v['recipient_name'];
      st.certs.add({
        'id': uid(),
        'number': number,
        'name': (recipient != null && recipient.isNotEmpty) ? recipient : widget.pr['name'],
        'orgId': widget.org?['id'],
        'orgName': widget.org?['name'],
        'date': v['date'] ?? todayStr(),
        'projectId': widget.pr['id'],
        'projectName': widget.pr['name'],
        'format': ext,
        'path': file.path,
        'vars': all,
        'design': d.toJson(),
        'issuedAt': DateTime.now().millisecondsSinceEpoch,
      });
      st.addHistory({'path': file.path, 'format': ext, 'dpi': r.dpi.round(), 'at': DateTime.now().millisecondsSinceEpoch});
      await st.save();
      if (printIt) await Printing.layoutPdf(onLayout: (_) async => bytes, name: fname);
      if (!mounted) return;
      setState(() {
        resultPath = file.path;
        resultBytes = bytes;
        info = 'تم التصدير (${(bytes.length / 1024).round()} KB، ${r.dpi.round()} DPI)';
      });
    } catch (e) {
      if (mounted) setState(() => info = 'فشل التصدير: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = {'pdf': LicenseManager.I.active ? 'PDF' : 'PDF 🔒', 'png': 'PNG', 'jpg': 'JPG'};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('تصدير الشهادة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          chips<String>([for (final e in cs.entries) MapEntry(e.key, e.value)], fmt, (v) async {
            if (v == 'pdf' && !await ensureActivated(context)) return;
            if (mounted) setState(() => fmt = v);
          }),
          const SizedBox(height: 8),
          const Text('الدقة (DPI)'),
          chips<int>(const [MapEntry(150, '150'), MapEntry(300, '300'), MapEntry(600, '600 (يتطلب ذاكرة)')], dpi, (v) => setState(() => dpi = v)),
          if (fmt != 'png') ...[
            Row(children: [
              const Text('جودة الصورة'),
              Expanded(child: Slider(value: quality.toDouble(), min: 50, max: 100, divisions: 10, label: '$quality', onChanged: (v) => setState(() => quality = v.round()))),
              Text('$quality'),
            ])
          ],
          if (fmt == 'png') SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('خلفية شفافة'), value: transparent, onChanged: (v) => setState(() => transparent = v)),
          if (fmt == 'pdf') ...[
            const Text('مقاس ورق PDF'),
            chips<String>(const [MapEntry('same', 'مطابق للتصميم'), MapEntry('A4', 'A4'), MapEntry('A5', 'A5'), MapEntry('Letter', 'Letter')], paper, (v) => setState(() => paper = v)),
            Row(children: [
              const Text('هامش الطباعة (مم)'),
              Expanded(child: Slider(value: margin, min: 0, max: 20, divisions: 20, label: margin.round().toString(), onChanged: (v) => setState(() => margin = v))),
              Text(margin.round().toString()),
            ]),
          ],
          const SizedBox(height: 4),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الملف', isDense: true, border: OutlineInputBorder())),
          if (vars.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(top: 12, bottom: 4), child: Text('قيم المتغيرات', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final e in vars.entries)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: TextField(controller: e.value, decoration: InputDecoration(labelText: varLabels[e.key] ?? e.key, isDense: true, border: const OutlineInputBorder()))),
          ],
          const SizedBox(height: 4),
          const Text('رقم الشهادة يُولَّد تلقائيًا. للتصدير الدفعي استخدم «الإصدار الجماعي».', style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 12),
          if (busy)
            const LinearProgressIndicator()
          else
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _run, icon: const Icon(Icons.file_download), label: const Text('تصدير'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _run(printIt: true), icon: const Icon(Icons.print), label: Text(LicenseManager.I.active ? 'طباعة' : 'طباعة 🔒'))),
            ]),
          if (info != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(info!)),
          if (resultPath != null)
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () async {
                    final p = await FilePicker.platform.saveFile(dialogTitle: 'مكان الحفظ', fileName: resultPath!.split('/').last, bytes: resultBytes);
                    if (p != null && mounted) toast(context, 'تم الحفظ');
                  },
                  icon: const Icon(Icons.save_alt),
                  label: const Text('حفظ في…')),
              OutlinedButton.icon(
                  onPressed: () => Share.shareXFiles([XFile(resultPath!)]), icon: const Icon(Icons.share), label: const Text('مشاركة')),
            ]),
        ]),
      ),
    );
  }
}
