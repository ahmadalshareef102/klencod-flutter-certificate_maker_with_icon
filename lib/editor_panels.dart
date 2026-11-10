import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'editor_state.dart';
import 'model.dart';
import 'painter.dart';
import 'store.dart';
import 'util.dart';

const palette = <int>[
  0xFF14243A, 0xFFC8A45D, 0xFF000000, 0xFFFFFFFF, 0xFF6B7280, 0xFFB91C1C, 0xFF15803D,
  0xFF1D4ED8, 0xFF0F766E, 0xFF7E22CE, 0xFFEA580C, 0xFF78350F, 0xFF1F4D3A, 0xFFF3F5F8,
];

const ornKinds = <String, String>{
  'frame1': 'إطار بسيط',
  'frame2': 'إطار مزدوج',
  'frame3': 'إطار فاخر',
  'frameIslamic': 'إطار إسلامي',
  'corners': 'زخارف زوايا',
  'cornersIslamic': 'زوايا إسلامية',
  'sideBars': 'إطار جانبي',
  'divider': 'خط زخرفي',
  'dividerStar': 'خط بنجمة',
  'rosette': 'ختم ذهبي',
  'starPattern': 'نمط نجمي',
  'ribbon': 'شريط',
};

const shapeKinds = <String, String>{
  'rect': 'مستطيل',
  'square': 'مربع',
  'circle': 'دائرة',
  'line': 'خط',
  'triangle': 'مثلث',
  'poly': 'مضلع',
  'star': 'نجمة',
};

/// يلتقط صورة من الجهاز ويخزنها محليًا. يرجع المسار أو null.
Future<String?> pickImagePath(Store store) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.image);
  final path = r?.files.single.path;
  if (path == null) return null;
  final dst = await store.importMedia(path);
  await imgs.ensure(dst);
  return dst;
}

Future<int?> pickColorDialog(BuildContext c, int initial) async {
  final tc = TextEditingController(text: initial.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase());
  return showDialog<int>(
      context: c,
      builder: (_) => AlertDialog(
            title: const Text('لون مخصص (HEX)'),
            content: TextField(controller: tc, maxLength: 6, textDirection: TextDirection.ltr, decoration: const InputDecoration(prefixText: '#')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () {
                    final v = int.tryParse(tc.text, radix: 16);
                    if (v != null && tc.text.length == 6) Navigator.pop(c, 0xFF000000 | v);
                  },
                  child: const Text('موافق')),
            ],
          ));
}

class ColorRow extends StatelessWidget {
  const ColorRow(this.label, this.value, this.onPick, {super.key, this.allowNone = false});
  final String label;
  final int? value;
  final void Function(int?) onPick;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    Widget sw(int? v, {Widget? child}) {
      final sel = v == value;
      return GestureDetector(
        onTap: () => onPick(v),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: v == null ? Colors.white : Color(v),
              shape: BoxShape.circle,
              border: Border.all(color: sel ? gold : Colors.black26, width: sel ? 3 : 1)),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  if (allowNone) sw(null, child: const Icon(Icons.block, size: 18, color: Colors.red)),
                  for (final c in palette) sw(c),
                  GestureDetector(
                    onTap: () async {
                      final r = await pickColorDialog(context, value ?? 0xFF000000);
                      if (r != null) onPick(r);
                    },
                    child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.palette_outlined)),
                  ),
                ]))),
      ]),
    );
  }
}

Widget sliderRow(EditorController c, String label, double v, double min, double max, void Function(double) on, {String Function(double)? fmt}) {
  return Row(children: [
    SizedBox(width: 78, child: Text(label, style: const TextStyle(fontSize: 12))),
    Expanded(
        child: Slider(
      value: v.clamp(min, max),
      min: min,
      max: max,
      onChangeStart: (_) => c.beginGesture(),
      onChanged: on,
      onChangeEnd: (_) => c.endGesture(),
    )),
    SizedBox(width: 44, child: Text(fmt != null ? fmt(v) : v.toStringAsFixed(1), style: const TextStyle(fontSize: 11))),
  ]);
}

Widget chips<T>(List<MapEntry<T, String>> items, T cur, void Function(T) on) => Wrap(spacing: 6, runSpacing: 4, children: [
      for (final it in items)
        ChoiceChip(label: Text(it.value, style: const TextStyle(fontSize: 12)), selected: it.key == cur, onSelected: (_) => on(it.key)),
    ]);

/// حقل نصي مرتبط بالعنصر دون قفز المؤشر.
class BoundField extends StatefulWidget {
  const BoundField({super.key, required this.value, required this.onChanged, this.label, this.lines = 1, this.rtl = true, this.number = false});
  final String value;
  final String? label;
  final int lines;
  final bool rtl, number;
  final void Function(String) onChanged;
  @override
  State<BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<BoundField> {
  late final TextEditingController tc = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(BoundField o) {
    super.didUpdateWidget(o);
    if (widget.number) {
      final a = double.tryParse(tc.text), b = double.tryParse(widget.value);
      if (a != null && b != null && (a - b).abs() < 0.06) return;
    }
    if (widget.value != tc.text) {
      tc.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: tc,
        minLines: 1,
        maxLines: widget.lines,
        keyboardType: widget.number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.multiline,
        textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
        decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()),
        style: const TextStyle(fontSize: 13),
        onChanged: widget.onChanged,
      );
}

class PropPanel extends StatelessWidget {
  const PropPanel({super.key, required this.c, required this.store, required this.onReplaceImage});
  final EditorController c;
  final Store store;
  final Future<void> Function(El) onReplaceImage;

  void sp(El e, String k, dynamic v, {String? tag}) => c.edit(() => e.p[k] = v, tag: tag ?? '$k${e.id}');

  Widget toggle(String label, bool v, void Function(bool) on) => FilterChip(label: Text(label, style: const TextStyle(fontSize: 12)), selected: v, onSelected: on);

  Widget geom(El e) {
    Widget f(String l, double v, void Function(double) set) => Expanded(
            child: Padding(
          padding: const EdgeInsets.all(2),
          child: BoundField(
              value: v.toStringAsFixed(1),
              label: l,
              number: true,
              rtl: false,
              onChanged: (s) {
                final d = double.tryParse(s);
                if (d != null) c.edit(() => set(d), tag: 'geo$l${e.id}');
              }),
        ));
    return Row(children: [
      f('X', e.x, (d) => e.x = d),
      f('Y', e.y, (d) => e.y = d),
      f('عرض', e.w, (d) => e.w = d < 1 ? 1 : d),
      f('ارتفاع', e.h, (d) => e.h = d < 1 ? 1 : d),
    ]);
  }

  List<Widget> textProps(BuildContext ctx, El e) {
    final fams = <MapEntry<String?, String>>[
      const MapEntry(null, 'الافتراضي'),
      const MapEntry('serif', 'نسخ (Serif)'),
      const MapEntry('monospace', 'ثابت'),
      for (final f in store.fontList) MapEntry(f['family'] as String, f['label'] as String),
    ];
    final curFont = e.p['font'] is String ? e.p['font'] as String : null;
    return [
      if (store.glyphs.containsKey(e.p['font']))
        Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
                onPressed: () => _glyphPicker(ctx, e),
                icon: const Icon(Icons.apps),
                label: const Text('جدول الرموز'))),
      BoundField(value: e.ns('text', ''), lines: 4, label: 'النص (يدعم {{المتغيرات}})', rtl: e.nb('rtl', true), onChanged: (s) => sp(e, 'text', s, tag: 'txt${e.id}')),
      const SizedBox(height: 6),
      Row(children: [
        const SizedBox(width: 78, child: Text('الخط', style: TextStyle(fontSize: 12))),
        Expanded(
            child: DropdownButton<String?>(
          isExpanded: true,
          value: fams.any((f) => f.key == curFont) ? curFont : null,
          items: [for (final f in fams) DropdownMenuItem<String?>(value: f.key, child: Text(f.value, style: TextStyle(fontFamily: f.key)))],
          onChanged: (v) => sp(e, 'font', v),
        )),
      ]),
      sliderRow(c, 'الحجم (pt)', e.nd('size', 18), 6, 160, (v) => sp(e, 'size', v.roundToDouble()), fmt: (v) => v.round().toString()),
      ColorRow('اللون', e.ni('color', 0xFF000000), (v) => sp(e, 'color', v ?? 0xFF000000)),
      Wrap(spacing: 6, children: [
        toggle('عريض', e.nb('bold', false), (v) => sp(e, 'bold', v)),
        toggle('مائل', e.nb('italic', false), (v) => sp(e, 'italic', v)),
        toggle('تسطير', e.nb('ul', false), (v) => sp(e, 'ul', v)),
        toggle('ظل', e.nb('shadow', false), (v) => sp(e, 'shadow', v)),
        toggle('تصغير تلقائي', e.nb('fit', false), (v) => sp(e, 'fit', v)),
      ]),
      const SizedBox(height: 6),
      chips<String>(const [MapEntry('right', 'يمين'), MapEntry('center', 'وسط'), MapEntry('left', 'يسار'), MapEntry('justify', 'ضبط')], e.ns('align', 'center'), (v) => sp(e, 'align', v)),
      const SizedBox(height: 4),
      chips<bool>(const [MapEntry(true, 'RTL ←'), MapEntry(false, 'LTR →')], e.nb('rtl', true), (v) => sp(e, 'rtl', v)),
      const SizedBox(height: 4),
      chips<String>(const [MapEntry('top', 'أعلى'), MapEntry('middle', 'منتصف'), MapEntry('bottom', 'أسفل')], e.ns('va', 'middle'), (v) => sp(e, 'va', v)),
      sliderRow(c, 'تباعد الحروف', e.nd('ls', 0), -2, 20, (v) => sp(e, 'ls', v), fmt: (v) => v.toStringAsFixed(1)),
      const Padding(padding: EdgeInsets.only(right: 78), child: Text('لا يُطبَّق على النص العربي لحفظ اتصال الحروف', style: TextStyle(fontSize: 10, color: Colors.black45))),
      sliderRow(c, 'تباعد الأسطر', e.nd('lh', 1.3), 0.8, 3, (v) => sp(e, 'lh', v)),
      sliderRow(c, 'حد النص (mm)', e.nd('strokeW', 0), 0, 2, (v) => sp(e, 'strokeW', v)),
      if (e.nd('strokeW', 0) > 0) ColorRow('لون الحد', e.ni('strokeColor', 0xFF000000), (v) => sp(e, 'strokeColor', v ?? 0xFF000000)),
    ];
  }

  /// جدول رموز الخط الزخرفي: اضغط رمزًا لإضافته إلى النص.
  void _glyphPicker(BuildContext ctx, El e) {
    final fam = e.p['font'] as String;
    final cps = store.glyphs[fam] ?? const <int>[];
    showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        builder: (sc) => SizedBox(
            height: MediaQuery.of(sc).size.height * 0.6,
            child: GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 64, mainAxisSpacing: 6, crossAxisSpacing: 6),
              itemCount: cps.length,
              itemBuilder: (_, i) {
                final ch = String.fromCharCode(cps[i]);
                return InkWell(
                    onTap: () {
                      sp(e, 'text', e.ns('text', '') + ch, tag: 'glyph${e.id}');
                      Navigator.pop(sc);
                    },
                    child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
                        child: Text(ch, style: TextStyle(fontFamily: fam, fontSize: 30))));
              },
            )));
  }

  List<Widget> shapeProps(El e) {
    final kind = e.ns('kind', 'rect');
    return [
      chips<String>(const [
        MapEntry('rect', 'مستطيل'),
        MapEntry('ellipse', 'دائرة/بيضاوي'),
        MapEntry('triangle', 'مثلث'),
        MapEntry('poly', 'مضلع'),
        MapEntry('star', 'نجمة'),
        MapEntry('line', 'خط'),
      ], kind, (v) => sp(e, 'kind', v)),
      if (kind != 'line') ColorRow('التعبئة', e.p['fill'] is num ? e.ni('fill', 0) : null, (v) => sp(e, 'fill', v), allowNone: true),
      if (kind != 'line') ColorRow('تدرج إلى', e.p['fill2'] is num ? e.ni('fill2', 0) : null, (v) => sp(e, 'fill2', v), allowNone: true),
      ColorRow('الحدود', e.p['stroke'] is num ? e.ni('stroke', 0) : null, (v) => sp(e, 'stroke', v), allowNone: true),
      sliderRow(c, 'السماكة (mm)', e.nd('sw', 0), 0, 8, (v) => sp(e, 'sw', v)),
      if (kind == 'rect') sliderRow(c, 'الزوايا (mm)', e.nd('radius', 0), 0, 40, (v) => sp(e, 'radius', v)),
      if (kind == 'poly' || kind == 'star') sliderRow(c, 'عدد الأضلاع', e.nd('sides', 5), 3, 16, (v) => sp(e, 'sides', v.round()), fmt: (v) => v.round().toString()),
      Wrap(spacing: 6, children: [
        toggle('ظل', e.nb('shadow', false), (v) => sp(e, 'shadow', v)),
        if (kind == 'line') toggle('متقطع', e.nb('dash', false), (v) => sp(e, 'dash', v)),
      ]),
    ];
  }

  List<Widget> ornProps(El e) => [
        chips<String>([for (final k in ornKinds.entries) MapEntry(k.key, k.value)], e.ns('kind', 'frame1'), (v) => sp(e, 'kind', v)),
        ColorRow('اللون 1', e.ni('color', 0xFFC8A45D), (v) => sp(e, 'color', v ?? 0xFFC8A45D)),
        ColorRow('اللون 2', e.ni('color2', 0xFF14243A), (v) => sp(e, 'color2', v ?? 0xFF14243A)),
        sliderRow(c, 'السماكة (mm)', e.nd('sw', 1.2), 0.1, 6, (v) => sp(e, 'sw', v)),
        if (e.ns('kind', '') == 'starPattern') sliderRow(c, 'التباعد (mm)', e.nd('gap', 14), 6, 40, (v) => sp(e, 'gap', v)),
        if (e.ns('kind', '').startsWith('corners')) sliderRow(c, 'طول الزاوية', e.nd('len', 22), 8, 60, (v) => sp(e, 'len', v)),
      ];

  List<Widget> imageProps(BuildContext ctx, El e) => [
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () => onReplaceImage(e), icon: const Icon(Icons.swap_horiz), label: const Text('استبدال')),
          OutlinedButton.icon(
              onPressed: () async {
                final src = e.ns('src', '');
                if (src.isEmpty || src.startsWith('@') || src.startsWith('asset:')) {
                  toast(ctx, 'اختر صورة من الجهاز أولًا');
                  return;
                }
                final np = await store.removeWhiteBg(src);
                await imgs.ensure(np);
                sp(e, 'src', np);
              },
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('إزالة الخلفية البيضاء')),
        ]),
        const SizedBox(height: 4),
        chips<String>(const [MapEntry('contain', 'احتواء'), MapEntry('cover', 'تغطية'), MapEntry('fill', 'تمديد')], e.ns('fit', 'contain'), (v) => sp(e, 'fit', v)),
        const SizedBox(height: 4),
        chips<String>(const [MapEntry('none', 'مستطيل'), MapEntry('round', 'زوايا مدورة'), MapEntry('circle', 'دائري')], e.ns('mask', 'none'), (v) => sp(e, 'mask', v)),
        toggle('الحفاظ على النسبة عند التكبير', e.nb('lock', true), (v) => sp(e, 'lock', v)),
        sliderRow(c, 'قص يمين', e.nd('cr', 0), 0, 0.8, (v) => sp(e, 'cr', v), fmt: (v) => '${(v * 100).round()}%'),
        sliderRow(c, 'قص يسار', e.nd('cl', 0), 0, 0.8, (v) => sp(e, 'cl', v), fmt: (v) => '${(v * 100).round()}%'),
        sliderRow(c, 'قص أعلى', e.nd('ct', 0), 0, 0.8, (v) => sp(e, 'ct', v), fmt: (v) => '${(v * 100).round()}%'),
        sliderRow(c, 'قص أسفل', e.nd('cb', 0), 0, 0.8, (v) => sp(e, 'cb', v), fmt: (v) => '${(v * 100).round()}%'),
      ];

  List<Widget> qrProps(El e) => [
        BoundField(value: e.ns('data', ''), label: 'محتوى QR (مثال: {{certificate_number}})', rtl: false, onChanged: (s) => sp(e, 'data', s, tag: 'qrd${e.id}')),
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('تنبيه: رمز QR يحمل النص فقط، ولا يوفّر تحققًا عامًا دون خدمة تحقق.', style: TextStyle(fontSize: 10, color: Colors.black54))),
        ColorRow('لون الرمز', e.ni('color', 0xFF000000), (v) => sp(e, 'color', v ?? 0xFF000000)),
        ColorRow('الخلفية', e.ni('bg', 0xFFFFFFFF), (v) => sp(e, 'bg', v ?? 0xFFFFFFFF)),
      ];

  List<Widget> drawProps(El e) => [
        ColorRow('لون الخط', e.ni('color', 0xFF14243A), (v) => sp(e, 'color', v ?? 0xFF14243A)),
        sliderRow(c, 'السماكة (mm)', e.nd('sw', 0.8), 0.2, 4, (v) => sp(e, 'sw', v)),
      ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final e = c.single;
          if (e == null) {
            return Center(child: Text(c.sel.isEmpty ? 'حدد عنصرًا لتعديل خصائصه' : 'تم تحديد ${c.sel.length} عناصر — استخدم المحاذاة والترتيب', style: const TextStyle(color: Colors.black54)));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 16), children: [
            Text('${e.name.isEmpty ? e.type : e.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...switch (e.type) {
              'text' => textProps(ctx, e),
              'shape' => shapeProps(e),
              'ornament' => ornProps(e),
              'image' => imageProps(ctx, e),
              'qr' => qrProps(e),
              _ => drawProps(e),
            },
            const Divider(),
            sliderRow(c, 'الشفافية', e.opacity, 0, 1, (v) => c.edit(() => e.opacity = v, tag: 'op${e.id}'), fmt: (v) => '${(v * 100).round()}%'),
            sliderRow(c, 'التدوير', e.rot, -180, 180, (v) => c.edit(() => e.rot = v.roundToDouble(), tag: 'rot${e.id}'), fmt: (v) => '${v.round()}°'),
            const SizedBox(height: 4),
            geom(e),
          ]);
        });
  }
}

class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.c});
  final EditorController c;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final list = c.design.els.reversed.toList();
          if (list.isEmpty) return const Center(child: Text('لا توجد عناصر بعد'));
          return ReorderableListView.builder(
            itemCount: list.length,
            onReorder: c.reorderLayer,
            buildDefaultDragHandles: true,
            itemBuilder: (_, i) {
              final e = list[i];
              final sel = c.sel.contains(e.id);
              final title = e.name.isNotEmpty ? e.name : e.type;
              final sub = e.type == 'text' ? e.ns('text', '') : e.type;
              return Material(
                key: ValueKey(e.id),
                color: sel ? gold.withOpacity(0.18) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: () => c.selectOnly(e.id),
                  onLongPress: () async {
                    final n = await askText(ctx, 'إعادة تسمية الطبقة', initial: title);
                    if (n != null) c.rename(e.id, n);
                  },
                  leading: IconButton(
                      icon: Icon(e.visible ? Icons.visibility : Icons.visibility_off, size: 20),
                      onPressed: () => c.toggleVisible(e.id)),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: Icon(e.locked ? Icons.lock : Icons.lock_open, size: 20), onPressed: () => c.toggleLock(e.id)),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => c.deleteIds({e.id})),
                    const SizedBox(width: 22),
                  ]),
                ),
              );
            },
          );
        });
  }
}

class AlignPanel extends StatelessWidget {
  const AlignPanel({super.key, required this.c});
  final EditorController c;
  @override
  Widget build(BuildContext context) {
    Widget b(IconData i, String t, VoidCallback on) => Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton.icon(onPressed: on, icon: Icon(i, size: 18), label: Text(t, style: const TextStyle(fontSize: 12))));
    return AnimatedBuilder(
        animation: c,
        builder: (_, __) => ListView(padding: const EdgeInsets.all(10), children: [
              Text(c.sel.length > 1 ? 'المحاذاة بالنسبة للتحديد' : 'المحاذاة بالنسبة للورقة', style: const TextStyle(fontWeight: FontWeight.bold)),
              Wrap(children: [
                b(Icons.align_horizontal_left, 'يسار', () => c.align('left')),
                b(Icons.align_horizontal_center, 'وسط أفقي', () => c.align('center')),
                b(Icons.align_horizontal_right, 'يمين', () => c.align('right')),
                b(Icons.align_vertical_top, 'أعلى', () => c.align('top')),
                b(Icons.align_vertical_center, 'وسط رأسي', () => c.align('middle')),
                b(Icons.align_vertical_bottom, 'أسفل', () => c.align('bottom')),
                b(Icons.horizontal_distribute, 'توزيع أفقي', () => c.distribute(true)),
                b(Icons.vertical_distribute, 'توزيع رأسي', () => c.distribute(false)),
              ]),
              const Text('التوزيع يتطلب تحديد 3 عناصر فأكثر.', style: TextStyle(fontSize: 11, color: Colors.black54)),
            ]));
  }
}

class AddPanel extends StatelessWidget {
  const AddPanel({super.key, required this.c, required this.store, required this.onImage, required this.onAsset, required this.onSignature});
  final EditorController c;
  final Store store;
  final VoidCallback onImage, onSignature;
  final void Function(String path) onAsset;

  @override
  Widget build(BuildContext context) {
    Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 4), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));
    Widget btn(String t, IconData i, VoidCallback on) => ActionChip(avatar: Icon(i, size: 16), label: Text(t, style: const TextStyle(fontSize: 12)), onPressed: on);
    return ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 16), children: [
      head('أساسيات'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        btn('نص', Icons.title, () => c.add(makeEl(c.design, 'text'))),
        btn('صورة من الجهاز', Icons.image_outlined, onImage),
        btn('رسم توقيع', Icons.draw_outlined, onSignature),
        btn('رمز QR', Icons.qr_code_2, () => c.add(makeEl(c.design, 'qr'))),
      ]),
      head('عناصر المؤسسة (تُدرج تلقائيًا)'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        btn('شعار', Icons.business, () => c.add(makeEl(c.design, 'image', src: '@org_logo')..name = 'شعار المؤسسة')),
        btn('توقيع', Icons.edit, () => c.add(makeEl(c.design, 'image', src: '@org_signature', ar: 2.5)..name = 'توقيع المسؤول')),
        btn('ختم', Icons.verified_outlined, () => c.add(makeEl(c.design, 'image', src: '@org_stamp')..name = 'الختم')),
      ]),
      head('متغيرات ديناميكية'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final v in varLabels.entries)
          btn(v.value, Icons.data_object, () => c.add(makeEl(c.design, 'text', text: '{{${v.key}}}')..name = v.value)),
      ]),
      head('أشكال'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final k in shapeKinds.entries) btn(k.value, Icons.category_outlined, () => c.add(makeEl(c.design, 'shape', kind: k.key))),
      ]),
      head('إطارات وزخارف'),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final k in ornKinds.entries) btn(k.value, Icons.auto_awesome, () => c.add(makeEl(c.design, 'ornament', kind: k.key))),
      ]),
      head('مكتبتي (الصور المحفوظة)'),
      if (store.assets.isEmpty) const Text('لا توجد أصول. أضفها من: المزيد ← مكتبة العناصر.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final a in store.assets)
          InkWell(
            onTap: () => onAsset(a['path'] as String),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
              child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(File(a['path'] as String), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
            ),
          ),
      ]),
    ]);
  }
}

class PagePanel extends StatelessWidget {
  const PagePanel({super.key, required this.c, required this.store});
  final EditorController c;
  final Store store;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: c,
        builder: (ctx, _) {
          final d = c.design;
          return ListView(padding: const EdgeInsets.all(12), children: [
            const Text('مقاس الورقة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            chips<String>([for (final k in paperNames.entries) MapEntry(k.key, k.value)], d.paper, (v) => c.setPaper(v)),
            if (d.paper == 'custom')
              Row(children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: BoundField(value: d.w.toStringAsFixed(1), label: 'العرض mm', number: true, rtl: false, onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null && v >= 20 && v <= 1000) c.setPaper('custom', w: v, h: d.h);
                }))),
                Expanded(child: Padding(padding: const EdgeInsets.all(4), child: BoundField(value: d.h.toStringAsFixed(1), label: 'الارتفاع mm', number: true, rtl: false, onChanged: (s) {
                  final v = double.tryParse(s);
                  if (v != null && v >= 20 && v <= 1000) c.setPaper('custom', w: d.w, h: v);
                }))),
              ]),
            Text('${d.w.toStringAsFixed(1)} × ${d.h.toStringAsFixed(1)} مم', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const Divider(),
            const Text('الخلفية', style: TextStyle(fontWeight: FontWeight.bold)),
            ColorRow('اللون', d.bg, (v) => c.edit(() => d.bg = v ?? 0xFFFFFFFF, tag: 'bg')),
            ColorRow('تدرج إلى', d.bg2, (v) => c.edit(() => d.bg2 = v, tag: 'bg2'), allowNone: true),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: () async {
                    final p = await pickImagePath(store);
                    if (p != null) c.edit(() => d.bgImage = p);
                  },
                  icon: const Icon(Icons.wallpaper),
                  label: const Text('صورة خلفية')),
              if (d.bgImage != null) OutlinedButton(onPressed: () => c.edit(() => d.bgImage = null), child: const Text('إزالة الصورة')),
            ]),
          ]);
        });
  }
}
