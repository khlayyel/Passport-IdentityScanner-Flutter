// torch_helper_web.dart
import 'dart:html' as html;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

void debugImport() {
  debugPrint("🚀 Import de torch_helper_web.dart réussi !");
}

Future<void> toggleTorchWeb(bool enable) async {
  try {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      debugPrint("❌ MediaDevices non disponible");
      return;
    }

    final stream = await mediaDevices.getUserMedia({
      'video': {
        'facingMode': 'environment',
      }
    });

    final videoTrack = stream.getVideoTracks().first;
    final capabilities = videoTrack.getCapabilities();

    if (capabilities.containsKey('torch') && capabilities['torch'] == true) {
      await videoTrack.applyConstraints({
        'advanced': [{'torch': enable}],
      });
      debugPrint("✅ Torch activée : $enable");
    } else {
      debugPrint("❌ La torche n'est pas supportée sur cet appareil.");
    }
  } catch (e) {
    debugPrint("❌ Erreur lors de l'activation de la torche sur le Web : $e");
  }
}

Future<void> disableTorchWeb() async {
  await toggleTorchWeb(false);
}

