import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'alerts.dart';
import 'api.dart';

/// Sécurité du client : envoie sa position à Yawi.
///  - à l'ouverture et au retour dans l'application (si la localisation est déjà autorisée) ;
///  - toutes les 15 s pendant une course ;
///  - tout de suite quand l'équipe d'urgence le demande (notification « locate »),
///    puis toutes les 30 s tant que la demande reste ouverte.
class Presence {
  Presence._();
  static final instance = Presence._();

  Api? _api;
  DateTime? _last;
  bool _requested = false;
  bool _busy = false;
  Timer? _repeat;
  StreamSubscription<Map<String, dynamic>>? _push;

  void start(Api api) {
    _api = api;
    _push ??= Alerts.instance.received.stream.listen((d) {
      if (d['type']?.toString() == 'locate') report(force: true);
    });
    report();
  }

  void stop() {
    _repeat?.cancel();
    _push?.cancel();
    _push = null;
    _api = null;
    _requested = false;
  }

  /// [minGap] : intervalle minimal entre deux envois (2 min par défaut, 15 s en course).
  Future<void> report({bool force = false, Duration minGap = const Duration(minutes: 2)}) async {
    final api = _api;
    if (api == null || _busy) return;
    if (!force && !_requested && _last != null && DateTime.now().difference(_last!) < minGap) return;
    _busy = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      // On ne demande l'autorisation que si l'équipe a besoin de la position.
      if (perm == LocationPermission.denied && force) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return;

      final res = await api.post('/presence', {'lat': pos.latitude, 'lng': pos.longitude});
      _last = DateTime.now();
      _requested = res['requested'] == true;
      _repeat?.cancel();
      if (_requested) _repeat = Timer(const Duration(seconds: 30), () => report(force: true));
    } catch (e) {
      debugPrint('Position non envoyée : $e');
    } finally {
      _busy = false;
    }
  }
}
