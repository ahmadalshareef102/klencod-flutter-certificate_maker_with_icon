#!/usr/bin/env python3
"""ينسخ الخطوط إلى assets/fonts ويولّد fonts.json وglyphs.json.
الاستخدام: python3 tools/build_fonts.py /مسار/مجلد/الخطوط"""
import json, os, shutil, sys
from fontTools.ttLib import TTFont

SRC = sys.argv[1] if len(sys.argv) > 1 else '.'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'fonts')
# (ملف, family, تسمية عربية, النوع)  text = نص عربي | latin = إنجليزي | symbol = رموز/زخارف
FONTS = [
 ('AL-Fares.ttf', 'AlFares', 'الفارس (عريض)', 'text'),
 ('DecoType_Thuluth.ttf', 'DecoThuluth', 'ثلث ديكوتايب', 'text'),
 ('Hacen_Liner_Print-out_Light.ttf', 'HacenLinerLight', 'حاسن لاينر خفيف', 'text'),
 ('Hacen_Liner_Screen_Bd.ttf', 'HacenLinerBold', 'حاسن لاينر عريض', 'text'),
 ('Hacen_Promoter.ttf', 'HacenPromoter', 'حاسن بروموتر', 'text'),
 ('Hacen_Vanilla_Ultra_Light.ttf', 'HacenVanilla', 'حاسن فانيلا خفيف', 'text'),
 ('Mohammad_Bold_normal.ttf', 'MohammadBold', 'محمد عريض', 'text'),
 ('Mohammad_Head.ttf', 'MohammadHead', 'محمد للعناوين', 'text'),
 ('Mohammad_Laha.ttf', 'MohammadLaha', 'محمد لاحا', 'text'),
 ('ITCEDSCR.TTF', 'EdwardianScript', 'Edwardian Script (إنجليزي)', 'latin'),
 ('AGA_ARABESQUE_FREE_SAMPLE.TTF', 'AgaArabesque', 'زخارف أرابيسك (رموز)', 'symbol'),
 ('ARASYM_EID_1.TTF', 'AraSymEid1', 'عيد 1 (رموز)', 'symbol'),
 ('ARASYM_EID_2.TTF', 'AraSymEid2', 'عيد 2 (رموز)', 'symbol'),
 ('ARASYM_RAMADAN_1.TTF', 'AraSymRamadan1', 'رمضان 1 (رموز)', 'symbol'),
 ('ARASYM_RAMADAN_2.TTF', 'AraSymRamadan2', 'رمضان 2 (رموز)', 'symbol'),
 ('ARASYM_RAMADAN_3.TTF', 'AraSymRamadan3', 'رمضان 3 (رموز)', 'symbol'),
 ('Fanan.ttf', 'Fanan', 'فنان (رموز)', 'symbol'),
 ('HOR.TTF', 'AlHor', 'الحر (رموز)', 'symbol'),
 ('Sultan__normal.ttf', 'SultanDeco', 'سلطان (زخرفي)', 'symbol'),
 ('SmartphoneProElHarrakCDarrati10gmailcom-OxKp.ttf', 'SmartphonePro', 'أيقونات (رموز)', 'symbol'),
]
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.lower().endswith(('.ttf', '.otf')): os.remove(os.path.join(OUT, f))
man, glyphs = [], {}
for fn, fam, label, kind in FONTS:
    src = os.path.join(SRC, fn)
    if not os.path.exists(src):
        print('مفقود:', fn); continue
    shutil.copy(src, os.path.join(OUT, fam + '.ttf'))
    man.append({'family': fam, 'file': fam + '.ttf', 'label': label, 'kind': kind})
    if kind == 'symbol':
        t = TTFont(src); cps = set()
        for tb in t['cmap'].tables: cps |= set(tb.cmap.keys())
        glyphs[fam] = sorted(c for c in cps if c > 0x20)
json.dump({'fonts': man}, open(os.path.join(OUT, 'fonts.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
json.dump(glyphs, open(os.path.join(OUT, 'glyphs.json'), 'w'), separators=(',', ':'))
print(len(man), 'خطًا؛ رموز:', {k: len(v) for k, v in glyphs.items()})
