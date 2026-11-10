#!/usr/bin/env python3
"""يولّد assets/templates/templates.json (30 قالبًا قابلًا للتحرير). شغّله: python3 tools/gen_templates.py"""
import json, os

SCHEMA = 1
def C(h): return 0xFF000000 | int(h.lstrip('#'), 16)
_n = [0]
def nid():
    _n[0] += 1
    return 'e%d' % _n[0]

def el(t, name, x, y, w, h, p, rot=0, op=1.0):
    return {"id": nid(), "type": t, "name": name, "x": round(x, 2), "y": round(y, 2), "w": round(w, 2),
            "h": round(h, 2), "rot": rot, "op": op, "locked": False, "visible": True, "p": p}

def text(name, s, x, y, w, h, size, color, font=None, bold=False, italic=False, align='center',
         fit=False, va='middle', lh=1.3, ls=0, shadow=False):
    return el('text', name, x, y, w, h, {"text": s, "font": font, "size": size, "color": color, "bold": bold,
        "italic": italic, "ul": False, "align": align, "rtl": True, "ls": ls, "lh": lh, "shadow": shadow,
        "strokeW": 0, "strokeColor": 0xFF000000, "fit": fit, "va": va})

def shape(name, kind, x, y, w, h, fill=None, fill2=None, stroke=None, sw=0, radius=0, sides=5, op=1.0):
    return el('shape', name, x, y, w, h, {"kind": kind, "fill": fill, "fill2": fill2, "stroke": stroke,
        "sw": sw, "radius": radius, "sides": sides, "shadow": False, "dash": False}, op=op)

def orn(name, kind, x, y, w, h, color, color2, sw=1.2, op=1.0, extra=None):
    p = {"kind": kind, "color": color, "color2": color2, "sw": sw}
    if extra: p.update(extra)
    return el('ornament', name, x, y, w, h, p, op=op)

def img(name, src, x, y, w, h, fit='contain'):
    return el('image', name, x, y, w, h, {"src": src, "fit": fit, "lock": True, "cl": 0, "ct": 0, "cr": 0,
        "cb": 0, "mask": "none"})

def qr(x, y, s, color):
    return el('qr', 'رمز QR', x, y, s, s, {"data": "{{certificate_number}}", "color": color, "bg": 0xFFFFFFFF})

STYLES = {
 'classic':  dict(bg=C('FFFDF7'), bg2=None, main=C('14243A'), acc=C('C8A45D'), txt=C('2B2B2B'), font='serif'),
 'gold':     dict(bg=C('FFF9E6'), bg2=C('F4E3B5'), main=C('7A5A14'), acc=C('C8A45D'), txt=C('3B2E10'), font='serif'),
 'academic': dict(bg=C('FFFFFF'), bg2=None, main=C('14243A'), acc=C('2F5D8C'), txt=C('222222'), font='serif'),
 'modern':   dict(bg=C('F7F8FA'), bg2=None, main=C('14243A'), acc=C('C8A45D'), txt=C('333333'), font=None),
 'islamic':  dict(bg=C('FBF7EC'), bg2=None, main=C('1F4D3A'), acc=C('C8A45D'), txt=C('24352B'), font='serif'),
 'islamic_dark': dict(bg=C('143D2D'), bg2=C('0E2B20'), main=C('E8C877'), acc=C('C8A45D'), txt=C('F4EBD0'), font='serif'),
 'school':   dict(bg=C('FFFBEF'), bg2=None, main=C('1565C0'), acc=C('F57C00'), txt=C('333333'), font=None),
 'training': dict(bg=C('FFFFFF'), bg2=None, main=C('14243A'), acc=C('00897B'), txt=C('333333'), font=None),
 'admin':    dict(bg=C('FFFFFF'), bg2=None, main=C('37474F'), acc=C('14243A'), txt=C('333333'), font=None),
}

def decor(style, w, h, S):
    m, a = S['main'], S['acc']
    d = []
    if style == 'classic':
        d += [orn('إطار', 'frame3', 8, 8, w-16, h-16, m, a, 1.4), orn('زوايا', 'corners', 12, 12, w-24, h-24, a, m, 1.0, extra={"len": 20})]
    elif style == 'gold':
        d += [orn('إطار ذهبي', 'frame2', 8, 8, w-16, h-16, a, S['main'], 1.8), orn('زوايا', 'corners', 13, 13, w-26, h-26, S['main'], a, 1.0, extra={"len": 24}),
              orn('ختم ذهبي', 'rosette', w/2-15, h-47, 30, 30, a, S['main'], 1.0)]
    elif style == 'academic':
        d += [orn('إطار', 'frame2', 8, 8, w-16, h-16, m, a, 1.6), orn('شريط جانبي', 'sideBars', 8, 8, w-16, h-16, m, a, 2.0)]
    elif style == 'modern':
        d += [shape('شريط علوي', 'rect', 0, 0, w, 12, fill=m), shape('خط ذهبي', 'rect', 0, 12, w, 1.6, fill=a),
              shape('شريط سفلي', 'rect', 0, h-8, w, 8, fill=m), shape('خط ذهبي سفلي', 'rect', 0, h-9.6, w, 1.6, fill=a)]
    elif style == 'islamic':
        d += [orn('نمط إسلامي', 'starPattern', 8, 8, w-16, h-16, a, a, 0.25, op=0.18, extra={"gap": 16}),
              orn('إطار إسلامي', 'frameIslamic', 8, 8, w-16, h-16, m, a, 1.4), orn('زوايا إسلامية', 'cornersIslamic', 12, 12, w-24, h-24, a, m, 1.0, extra={"len": 22})]
    elif style == 'islamic_dark':
        d += [orn('نمط إسلامي', 'starPattern', 8, 8, w-16, h-16, a, a, 0.25, op=0.22, extra={"gap": 16}),
              orn('إطار إسلامي', 'frameIslamic', 8, 8, w-16, h-16, a, m, 1.4), orn('زوايا إسلامية', 'cornersIslamic', 12, 12, w-24, h-24, m, a, 1.0, extra={"len": 22})]
    elif style == 'school':
        d += [orn('إطار', 'frame1', 7, 7, w-14, h-14, m, a, 2.4), orn('إطار داخلي', 'frame1', 11, 11, w-22, h-22, a, a, 0.8),
              shape('نجمة 1', 'star', 16, 16, 14, 14, fill=a, sides=5), shape('نجمة 2', 'star', w-30, 16, 14, 14, fill=a, sides=5),
              shape('نجمة 3', 'star', 16, h-30, 14, 14, fill=m, sides=5), shape('نجمة 4', 'star', w-30, h-30, 14, 14, fill=m, sides=5)]
    elif style == 'training':
        d += [shape('شريط علوي', 'rect', 0, 0, w, 6, fill=m), shape('شريط أخضر', 'rect', 0, 6, w, 2, fill=a),
              shape('شريط سفلي', 'rect', 0, h-6, w, 6, fill=m), shape('شريط أخضر سفلي', 'rect', 0, h-8, w, 2, fill=a)]
    elif style == 'admin':
        d += [orn('إطار', 'frame1', 9, 9, w-18, h-18, m, a, 0.9), shape('شريط', 'rect', 9, 9, w-18, 3, fill=a)]
    return d

TF = {'classic': 'DecoThuluth', 'gold': 'DecoThuluth', 'islamic': 'DecoThuluth', 'islamic_dark': 'DecoThuluth',
      'academic': 'HacenLinerBold', 'modern': 'HacenLinerBold', 'training': 'HacenLinerBold', 'admin': 'HacenLinerBold', 'school': 'MohammadLaha'}

CATS = {
 'thanks':  ('شهادات الشكر والتقدير', 'شهادة شكر وتقدير', 'تتقدم {{institution_name}} بخالص الشكر والتقدير للمذكور أعلاه على جهوده المخلصة وعطائه المتميز، سائلين الله له دوام التوفيق والنجاح.'),
 'participation': ('شهادات المشاركة', 'شهادة مشاركة', 'وذلك لمشاركته الفاعلة في {{course_name}} المقام في {{institution_name}}، شاكرين له حسن مشاركته وتعاونه.'),
 'course':  ('شهادات إتمام الدورات', 'شهادة إتمام دورة', 'وذلك لإتمامه بنجاح دورة «{{course_name}}» بمدة {{duration}}، واجتيازه متطلباتها بتقدير {{grade}}.'),
 'excellence': ('شهادات التفوق', 'شهادة تفوق', 'تقديرًا لتفوقه الدراسي وحصوله على تقدير {{grade}} في {{course_name}}، متمنين له مزيدًا من التقدم والنجاح.'),
 'distinction': ('شهادات الامتياز', 'شهادة امتياز', 'تقديرًا لأدائه الاستثنائي وحصوله على درجة الامتياز في {{course_name}}.'),
 'experience': ('شهادات الخبرة', 'شهادة خبرة', 'تشهد {{institution_name}} بأن المذكور أعلاه عمل لديها في مجال {{course_name}} لمدة {{duration}}، وكان مثالًا في الأمانة والإخلاص، وأُعطيت له هذه الشهادة بناءً على طلبه.'),
 'honor':   ('شهادات التكريم', 'شهادة تكريم', 'تكريمًا له على عطائه ومساهماته المميزة في {{course_name}}، وتقديرًا لما بذله من جهد مشكور.'),
 'attendance': ('شهادات الحضور', 'شهادة حضور', 'وذلك لحضوره فعاليات «{{course_name}}» بمدة {{duration}}، شاكرين له التزامه وحسن حضوره.'),
 'quran':   ('شهادات حفظ القرآن', 'شهادة حفظ القرآن الكريم', 'وذلك لإتمامه حفظ {{course_name}} غيبًا بتقدير {{grade}}، نسأل الله أن ينفع به وأن يجعله من أهل القرآن.'),
 'achievement': ('شهادات الإنجاز', 'شهادة إنجاز', 'تقديرًا لإنجازه المتميز في {{course_name}}، وتحقيقه النتائج المرجوة بجدارة واستحقاق.'),
 'teachers': ('شهادات المعلمين والمدربين', 'شهادة شكر للمعلم والمدرب', 'تقديرًا لجهوده التربوية والتعليمية في {{course_name}}، وعطائه الصادق في خدمة طلابه ومؤسسته.'),
 'special': ('شهادات المناسبات الخاصة', 'شهادة تهنئة', 'بمناسبة {{course_name}}، يسعدنا أن نتقدم له بأطيب التهاني وأصدق الأمنيات بدوام التوفيق.'),
}
CAT_ORDER = list(CATS.keys())

SPECS = [
 ('thanks','classic',0,'شكر كلاسيكي رسمي'), ('thanks','gold',0,'شكر ذهبي فاخر'), ('thanks','modern',0,'شكر عصري'),
 ('participation','modern',0,'مشاركة عصرية'), ('participation','training',1,'مشاركة تدريبية عمودية'),
 ('course','training',0,'إتمام دورة تدريبية'), ('course','academic',0,'إتمام دورة أكاديمية'), ('course','modern',0,'إتمام دورة عصرية'),
 ('excellence','school',0,'تفوق مدرسي'), ('excellence','gold',0,'تفوق ذهبي'),
 ('distinction','gold',0,'امتياز ذهبي'), ('distinction','classic',1,'امتياز كلاسيكي عمودي'),
 ('experience','admin',0,'خبرة إدارية'), ('experience','classic',0,'خبرة كلاسيكية'),
 ('honor','gold',0,'تكريم ذهبي'), ('honor','islamic',0,'تكريم إسلامي'),
 ('attendance','training',0,'حضور تدريبي'), ('attendance','admin',1,'حضور إداري عمودي'),
 ('quran','islamic',0,'حفظ قرآن زخرفة خضراء'), ('quran','islamic_dark',0,'حفظ قرآن أخضر داكن'), ('quran','gold',1,'حفظ قرآن ذهبي عمودي'),
 ('achievement','modern',0,'إنجاز عصري'), ('achievement','school',0,'إنجاز مدرسي'),
 ('teachers','academic',0,'شكر معلم أكاديمي'), ('teachers','classic',0,'شكر معلم كلاسيكي'), ('teachers','islamic',0,'شكر معلم إسلامي'),
 ('special','gold',0,'مناسبة ذهبية'), ('special','modern',0,'مناسبة عصرية'), ('special','islamic',0,'مناسبة إسلامية'), ('special','school',1,'مناسبة مدرسية عمودية'),
]

def build(cat, style, portrait, name, idx):
    _n[0] = 0
    S = STYLES[style]
    w, h = (210.0, 297.0) if portrait else (297.0, 210.0)
    catname, title, body = CATS[cat]
    els = decor(style, w, h, S)
    font, main, acc, txt = S['font'], S['main'], S['acc'], S['txt']
    mc = 24
    if portrait:
        Y = dict(logo=24, inst=54, title=66, sub=92, name=106, body=136, bodyh=76)
        tsize, nsize = 32, 32
    else:
        Y = dict(logo=17, inst=41, title=50, sub=69, name=78, body=98, bodyh=36)
        tsize, nsize = 38, 34
    topshift = 4 if style in ('modern', 'training', 'admin') else 0
    for k in ('logo', 'inst', 'title', 'sub', 'name', 'body'):
        Y[k] += topshift
    cw = w - 2 * mc
    els.append(img('شعار المؤسسة', '@org_logo', w/2-11, Y['logo'], 22, 22))
    tf = TF[style]
    thuluth = tf == 'DecoThuluth'
    els.append(text('اسم المؤسسة', '{{institution_name}}', mc, Y['inst'], cw, 8, 17, main, 'HacenLinerBold', False, fit=True))
    els.append(text('عنوان الشهادة', title, mc, Y['title'], cw, 18, tsize * (1.15 if thuluth else 1), main, tf, not thuluth and tf != 'MohammadLaha', fit=True, shadow=(style == 'gold')))
    els.append(orn('فاصل', 'dividerStar' if 'islamic' in style else 'divider', w/2-45, Y['sub']-1, 90, 6, acc, acc, 0.5))
    els.append(text('عبارة المنح', 'تُمنح هذه الشهادة إلى', mc, Y['sub']+6, cw, 7, 15, txt, font))
    ncol = acc if style in ('classic', 'gold', 'islamic_dark', 'academic') else main
    els.append(text('اسم المستفيد', '{{recipient_name}}', mc, Y['name']+4, cw, 18, nsize * (1.15 if thuluth else 1), ncol, tf, not thuluth and tf != 'MohammadLaha', fit=True))
    els.append(text('نص الشهادة', body, mc+8, Y['body']+4, cw-16, Y['bodyh'], 16, txt, font, align='center', va='top', lh=1.6, fit=True))
    y0f = h - mc - 44
    sx = w - mc - 62
    els.append(img('توقيع المسؤول', '@org_signature', sx+11, y0f, 40, 16))
    els.append(shape('خط التوقيع', 'rect', sx, y0f+17, 62, 0.4, fill=txt))
    els.append(text('اسم المسؤول', '{{signer_name}}', sx, y0f+19, 62, 8, 13, txt, font, True, fit=True))
    els.append(text('صفة المسؤول', '{{signer_title}}', sx, y0f+27, 62, 7, 11, txt, font, fit=True))
    two = cat in ('course', 'teachers', 'participation')
    if two:
        els.append(shape('خط التوقيع 2', 'rect', mc, y0f+17, 62, 0.4, fill=txt))
        els.append(text('اسم المدرب', '{{instructor_name}}', mc, y0f+19, 62, 8, 13, txt, font, True, fit=True))
        els.append(text('صفة المدرب', 'المدرب', mc, y0f+27, 62, 7, 11, txt, font))
    if style != 'gold':
        els.append(img('الختم', '@org_stamp', w/2-14, y0f-2, 28, 28))
    els.append(text('التاريخ والرقم', 'التاريخ: {{date}}   |   رقم الشهادة: {{certificate_number}}', mc, h - mc - 5, cw, 7, 11, txt, font, fit=True))
    if style in ('modern', 'training') and not portrait:
        els.append(qr(mc + 2, (y0f - 30) if two else (y0f + 4), 22, main))
    design = {"schema": SCHEMA, "paper": 'A4P' if portrait else 'A4L', "w": w, "h": h,
              "bg": S['bg'], "bg2": S['bg2'], "bgImage": None, "els": els}
    return {"id": "tpl_%02d" % idx, "name": name, "category": cat, "style": style, "design": design}

def main():
    tpls = [build(c, s, p, n, i + 1) for i, (c, s, p, n) in enumerate(SPECS)]
    out = {"schemaVersion": SCHEMA,
           "categories": [{"id": k, "name": CATS[k][0]} for k in CAT_ORDER],
           "templates": tpls}
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'templates', 'templates.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print('wrote', len(tpls), 'templates ->', os.path.getsize(path), 'bytes')

if __name__ == '__main__':
    main()
