import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'util.dart';

/// المفتاح العام (Ed25519). المفتاح الخاص لدى المبرمج فقط ولا يوجد في التطبيق.
const _publicKeyB64 = '7yxHJFMlyLaKOK74A0BA8lReuzQh/TNqVepMHd1IYLg=';

const devName = 'أحمد داود طه شريف';
const devPhone = '771274134';

class LicenseException implements Exception {
  @override
  String toString() => 'تصدير PDF والطباعة يتطلبان التفعيل من المبرمج  ()';
}

/// تفعيل دون إنترنت: كود موقَّع بمفتاح المبرمج ومربوط بمعرّف هذا الجهاز.
/// يُخزَّن في license.json خارج النسخ الاحتياطي، فلا ينتقل التفعيل إلى جهاز آخر.
class LicenseManager {
  LicenseManager._();
  static final LicenseManager I = LicenseManager._();

  late File _file;
  String deviceId = '';
  String code = '';
  bool active = false;

  static String _newId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String g() => List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'PCM-${g()}-${g()}-${g()}';
  }

  Future<void> init(Directory dir) async {
    _file = File('${dir.path}/license.json');
    try {
      if (await _file.exists()) {
        final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        deviceId = (j['deviceId'] as String?) ?? '';
        code = (j['code'] as String?) ?? '';
      }
    } catch (_) {}
    if (deviceId.isEmpty) {
      deviceId = _newId();
      await _write();
    }
    active = code.isNotEmpty && await _verify(deviceId, code);
  }

  Future<void> _write() => _file.writeAsString(jsonEncode({'deviceId': deviceId, 'code': code}), flush: true);

  Future<bool> _verify(String id, String c) async {
    try {
      final clean = c.replaceAll(RegExp(r'\s'), '');
      final sig = base64Url.decode(base64Url.normalize(clean));
      if (sig.length != 64) return false;
      final pub = SimplePublicKey(base64.decode(_publicKeyB64), type: KeyPairType.ed25519);
      return await Ed25519().verify(utf8.encode('PCM1|$id'), signature: Signature(sig, publicKey: pub));
    } catch (_) {
      return false;
    }
  }

  Future<bool> activate(String c) async {
    final ok = await _verify(deviceId, c);
    if (ok) {
      code = c.replaceAll(RegExp(r'\s'), '');
      active = true;
      await _write();
    }
    return ok;
  }

  void require() {
    if (!active) throw LicenseException();
  }
}

/// يعرض شاشة التفعيل عند الحاجة. يرجع true إذا كان التطبيق مفعّلًا.
Future<bool> ensureActivated(BuildContext context) async {
  if (LicenseManager.I.active) return true;
  final r = await showDialog<bool>(context: context, builder: (_) => const ActivationDialog());
  return r == true || LicenseManager.I.active;
}

class ActivationDialog extends StatefulWidget {
  const ActivationDialog({super.key});
  @override
  State<ActivationDialog> createState() => _ActivationDialogState();
}

class _ActivationDialogState extends State<ActivationDialog> {
  final tc = TextEditingController();
  String? err;
  bool busy = false;
  LicenseManager get lm => LicenseManager.I;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('التفعيل مطلوب'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('تصدير PDF والطباعة غير متاحين إلا بعد التفعيل من المبرمج:'),
          const SizedBox(height: 6),
          const Text(devName, style: TextStyle(fontWeight: FontWeight.bold)),
          Row(children: [
            const Text(devPhone, textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () => Clipboard.setData(const ClipboardData(text: devPhone))),
          ]),
          const Divider(),
          const Text('معرّف جهازك (أرسله للمبرمج):'),
          SelectableText(lm.deviceId, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          Wrap(spacing: 6, children: [
            TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: lm.deviceId)), icon: const Icon(Icons.copy, size: 16), label: const Text('نسخ')),
            TextButton.icon(
                onPressed: () => Share.share('طلب تفعيل صانع الشهادات\nمعرّف الجهاز: ${lm.deviceId}'),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('إرسال المعرّف')),
          ]),
          const Divider(),
          TextField(
            controller: tc,
            minLines: 1,
            maxLines: 4,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: 'كود التفعيل', errorText: err, border: const OutlineInputBorder(), suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) setState(() => tc.text = d!.text!.trim());
                })),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إغلاق')),
        FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      err = null;
                    });
                    final ok = await lm.activate(tc.text);
                    if (!mounted) return;
                    if (ok) {
                      Navigator.pop(context, true);
                    } else {
                      setState(() {
                        busy = false;
                        err = 'الكود غير صحيح لهذا الجهاز';
                      });
                    }
                  },
            child: const Text('تفعيل')),
      ],
    );
  }
}
