#!/usr/bin/env python3
"""مولّد أكواد التفعيل — للمبرمج فقط. لا ترفع المفتاح الخاص إلى المستودع.
الاستخدام:
  python3 tools/make_activation.py PCM-XXXX-XXXX-XXXX [مسار_المفتاح_الخاص.pem]
المعرّف يرسله المستخدم من شاشة التفعيل. الكود الناتج يُرسَل له ويُلصق في التطبيق."""
import base64, sys
from cryptography.hazmat.primitives import serialization as S

if len(sys.argv) < 2:
    sys.exit(__doc__)
device = sys.argv[1].strip().upper().replace(' ', '')
key_path = sys.argv[2] if len(sys.argv) > 2 else 'activation_private_key.pem'
key = S.load_pem_private_key(open(key_path, 'rb').read(), password=None)
sig = key.sign(('PCM1|' + device).encode('utf-8'))
print(base64.urlsafe_b64encode(sig).decode().rstrip('='))
