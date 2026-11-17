import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/yawi_map.dart';

/// Une manœuvre de l'itinéraire (renvoyée par l'API /geo/route?steps=1).
class NavStep {
  NavStep(this.type, this.modifier, this.exit, this.name, this.distance, this.point);

  final String type;
  final String? modifier;
  final int? exit;
  final String name;
  final double distance;
  final LatLng point;

  factory NavStep.fromJson(Map<String, dynamic> j) => NavStep(
        j['type']?.toString() ?? 'continue',
        j['modifier']?.toString(),
        (j['exit'] as num?)?.toInt(),
        j['name']?.toString() ?? '',
        (j['distance'] as num?)?.toDouble() ?? 0,
        LatLng((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
      );

  bool get isArrival => type == 'arrive';

  /// Instruction en français, ex. « Tournez à gauche sur Route du Niger ».
  String instruction() {
    final onto = name.isNotEmpty ? ' sur $name' : '';
    final dir = _direction(modifier);
    switch (type) {
      case 'depart':
        return 'Partez${dir.isNotEmpty ? ' $dir' : ''}$onto';
      case 'arrive':
        return 'Vous arrivez à destination';
      case 'roundabout':
      case 'rotary':
      case 'exit roundabout':
      case 'exit rotary':
        return exit != null ? 'Au rond-point, prenez la ${_ordinal(exit!)} sortie$onto' : 'Prenez le rond-point$onto';
      case 'merge':
        return 'Insérez-vous$onto';
      case 'on ramp':
        return 'Prenez la bretelle${dir.isNotEmpty ? ' $dir' : ''}$onto';
      case 'off ramp':
        return 'Sortez${dir.isNotEmpty ? ' $dir' : ''}$onto';
      case 'fork':
        return 'À l\'embranchement, restez ${modifier?.contains('left') == true ? 'à gauche' : 'à droite'}$onto';
      case 'end of road':
        return 'Au bout de la route, tournez ${modifier?.contains('left') == true ? 'à gauche' : 'à droite'}$onto';
      case 'new name':
      case 'continue':
        return modifier == 'uturn' ? 'Faites demi-tour$onto' : 'Continuez${dir.isNotEmpty && modifier != 'straight' ? ' $dir' : ' tout droit'}$onto';
      default: // turn, notification…
        if (modifier == 'uturn') return 'Faites demi-tour$onto';
        if (modifier == 'straight') return 'Continuez tout droit$onto';
        return 'Tournez $dir$onto';
    }
  }

  IconData icon() {
    if (type == 'arrive') return Icons.flag_rounded;
    if (type.contains('roundabout') || type.contains('rotary')) return Icons.roundabout_right;
    return switch (modifier) {
      'left' => Icons.turn_left,
      'sharp left' => Icons.turn_sharp_left,
      'slight left' => Icons.turn_slight_left,
      'right' => Icons.turn_right,
      'sharp right' => Icons.turn_sharp_right,
      'slight right' => Icons.turn_slight_right,
      'uturn' => Icons.u_turn_left,
      _ => Icons.straight,
    };
  }

  static String _direction(String? m) => switch (m) {
        'left' => 'à gauche',
        'sharp left' => 'franchement à gauche',
        'slight left' => 'légèrement à gauche',
        'right' => 'à droite',
        'sharp right' => 'franchement à droite',
        'slight right' => 'légèrement à droite',
        'straight' => 'tout droit',
        'uturn' => 'demi-tour',
        _ => '',
      };

  static String _ordinal(int n) => n == 1 ? 'première' : (n == 2 ? 'deuxième' : (n == 3 ? 'troisième' : (n == 4 ? 'quatrième' : '${n}e')));
}

/// Guidage GPS dans l'application (sans Google Maps) : carte qui suit le véhicule,
/// instructions tour par tour à l'écran et à la voix, recalcul si l'on sort de l'itinéraire.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key, required this.destination, required this.label});

  final LatLng destination;
  final String label;

  /// Renvoie true si le conducteur est arrivé.
  static Future<bool?> open(BuildContext context, LatLng destination, String label) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => NavigationScreen(destination: destination, label: label)));

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const _dist = Distance();
  static const _arriveM = 30.0;
  static const _offRouteM = 55.0;

  final _map = MapController();
  final _tts = FlutterTts();
  StreamSubscription<Position>? _gps;

  LatLng? _me;
  double _heading = 0;
  double _speed = 0; // m/s
  List<LatLng> _route = [];
  List<NavStep> _steps = [];
  int _step = 1; // prochaine manœuvre (0 = départ)
  double _remainingM = 0;
  double _totalM = 0;
  double _totalS = 0;
  bool _follow = true;
  bool _muted = false;
  bool _loading = true;
  bool _arrived = false;
  String? _error;
  int _offCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _spoken = {};

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tts.setLanguage('fr-FR');
    _tts.setSpeechRate(0.5);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS : annonces audibles même en mode silencieux, en baissant la musique pendant la consigne.
      _tts.setSharedInstance(true);
      _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.duckOthers, IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers]);
    }
    _start();
  }

  @override
  void dispose() {
    _gps?.cancel();
    _tts.stop();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    final r = await Geo.current();
    if (!mounted) return;
    if (r.point == null) {
      setState(() {
        _loading = false;
        _error = Geo.explain(r.problem!);
      });
      return;
    }
    _me = r.point;
    await _reroute(first: true);
    _gps = Geolocator.getPositionStream(
      locationSettings: Geo.settings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 3, interval: const Duration(seconds: 1), navigation: true),
    ).listen(_onPosition, onError: (_) {});
  }

  Future<void> _reroute({bool first = false}) async {
    if (_me == null) return;
    _lastReroute = DateTime.now();
    try {
      final res = await _api.get('/geo/route', query: {
        'from_lat': _me!.latitude, 'from_lng': _me!.longitude,
        'to_lat': widget.destination.latitude, 'to_lng': widget.destination.longitude, 'steps': 1,
      });
      if (!mounted) return;
      final pts = ((res['points'] as List?) ?? []).map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
      final steps = ((res['steps'] as List?) ?? []).map((e) => NavStep.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      setState(() {
        _route = pts;
        _steps = steps;
        _step = steps.length > 1 ? 1 : 0;
        _totalM = (res['distance_m'] as num?)?.toDouble() ?? _polyLength(pts);
        _totalS = (res['duration_s'] as num?)?.toDouble() ?? _totalM / 8;
        _remainingM = _totalM;
        _loading = false;
        _error = res['fallback'] == true ? 'Itinéraire détaillé indisponible : suivez la direction indiquée.' : null;
        _offCount = 0;
        _spoken.clear();
      });
      if (first) {
        _say('C\'est parti. ${_steps.length > 1 ? _steps[1].instruction() : ''}');
      } else {
        _say('Nouvel itinéraire.');
      }
      _camera();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _onPosition(Position p) {
    final here = LatLng(p.latitude, p.longitude);
    if (_me != null && _dist(_me!, here) > 2) _heading = _bearing(_me!, here);
    if (p.heading > 0 && p.speed > 2) _heading = p.heading;
    _me = here;
    _speed = p.speed;

    if (_dist(here, widget.destination) <= _arriveM) {
      if (!_arrived) {
        _arrived = true;
        _say('Vous êtes arrivé.');
      }
      setState(() {});
      return;
    }
    if (_route.length > 1) {
      final (offM, idx) = _nearest(here);
      // Sortie d'itinéraire : 3 positions de suite loin du tracé → recalcul (au plus toutes les 15 s)
      _offCount = offM > _offRouteM ? _offCount + 1 : 0;
      if (_offCount >= 3 && DateTime.now().difference(_lastReroute).inSeconds > 15) {
        _reroute();
      }
      _remainingM = _dist(here, _route[math.min(idx + 1, _route.length - 1)]) + _polyLength(_route.sublist(math.min(idx + 1, _route.length - 1)));
    }
    _advanceStep(here);
    _camera();
    setState(() {});
  }

  /// Passe à la manœuvre suivante une fois la précédente franchie, et annonce à la voix.
  void _advanceStep(LatLng here) {
    if (_steps.isEmpty || _step >= _steps.length) return;
    final d = _dist(here, _steps[_step].point);
    if (d < 20 && _step < _steps.length - 1) {
      _step++;
      return;
    }
    final s = _steps[_step];
    final key = '$_step';
    if (d < 250 && d > 90 && !_spoken.contains('$key-loin')) {
      _spoken.add('$key-loin');
      _say('Dans ${_roundM(d)}, ${s.instruction()}');
    } else if (d <= 45 && !_spoken.contains('$key-pres')) {
      _spoken.add('$key-pres');
      _say(s.instruction());
    }
  }

  void _camera() {
    if (!_follow || _me == null) return;
    try {
      _map.moveAndRotate(_me!, _speed > 14 ? 16 : 17.2, -_heading);
    } catch (_) {}
  }

  Future<void> _say(String text) async {
    if (_muted || text.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Géométrie

  (double, int) _nearest(LatLng p) {
    var best = double.infinity;
    var bestIdx = 0;
    for (var i = 0; i < _route.length - 1; i++) {
      final d = _segmentDistance(p, _route[i], _route[i + 1]);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return (best, bestIdx);
  }

  /// Distance (m) d'un point à un segment, en projection locale équirectangulaire.
  double _segmentDistance(LatLng p, LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat0 = p.latitude * math.pi / 180;
    double x(LatLng q) => (q.longitude - p.longitude) * math.pi / 180 * r * math.cos(lat0);
    double y(LatLng q) => (q.latitude - p.latitude) * math.pi / 180 * r;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final px = ax + t * dx, py = ay + t * dy;
    return math.sqrt(px * px + py * py);
  }

  double _polyLength(List<LatLng> pts) {
    var m = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      m += _dist(pts[i], pts[i + 1]);
    }
    return m;
  }

  double _bearing(LatLng a, LatLng b) => (_dist.bearing(a, b) + 360) % 360;

  String _roundM(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilomètre' : '${(m / 10).round() * 10} mètres';

  String _fmtDist(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '${(m / 10).round() * 10} m';

  // ---------------------------------------------------------------- Écran

  @override
  Widget build(BuildContext context) {
    final next = _steps.isNotEmpty && _step < _steps.length ? _steps[_step] : null;
    final nextDist = next != null && _me != null ? _dist(_me!, next.point) : null;
    final ratio = _totalM > 0 ? (_remainingM / _totalM).clamp(0.0, 1.0) : 1.0;
    final etaMin = (_totalS * ratio / 60).ceil();
    final arrival = DateTime.now().add(Duration(minutes: etaMin));
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(children: [
        YawiMap(
          controller: _map,
          center: _me ?? widget.destination,
          zoom: 16,
          route: _route,
          onMoved: (_) => setState(() => _follow = false),
          pins: [
            Pin(widget.destination, PinKind.dropoff),
            if (_me != null) Pin(_me!, PinKind.me),
          ],
        ),
        // Bandeau de la prochaine manœuvre
        Positioned(
          left: 12, right: 12, top: top + 10,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: _arrived ? Y.feuille : Y.nuit, borderRadius: BorderRadius.circular(Y.rCard), boxShadow: Y.ombre),
            child: _loading
                ? const Row(children: [
                    SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                    SizedBox(width: 14),
                    Text('Calcul de l\'itinéraire…', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                  ])
                : Row(children: [
                    Icon(_arrived ? Icons.flag_rounded : (next?.icon() ?? Icons.navigation), color: Y.braiseClair, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        if (!_arrived && nextDist != null)
                          Text(_fmtDist(nextDist), style: const TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 22)),
                        Text(
                          _arrived ? 'Vous êtes arrivé · ${widget.label}' : (next?.instruction() ?? 'Suivez l\'itinéraire vers ${widget.label}'),
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, height: 1.25),
                        ),
                      ]),
                    ),
                  ]),
          ),
        ),
        if (_error != null)
          Positioned(
            left: 12, right: 12, top: top + 104,
            child: Material(
              color: const Color(0xFFFFF4D6),
              borderRadius: BorderRadius.circular(Y.rCtrl),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w700))),
            ),
          ),
        // Boutons : recentrer, son
        Positioned(
          right: 12, bottom: 150,
          child: Column(children: [
            FloatingActionButton.small(
              heroTag: 'son', backgroundColor: Colors.white, foregroundColor: Y.nuit,
              tooltip: _muted ? 'Activer la voix' : 'Couper la voix',
              onPressed: () {
                setState(() => _muted = !_muted);
                if (_muted) _tts.stop();
              },
              child: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            ),
            const SizedBox(height: 10),
            if (!_follow)
              FloatingActionButton.small(
                heroTag: 'suivre', backgroundColor: Colors.white, foregroundColor: Y.nuit, tooltip: 'Recentrer',
                onPressed: () {
                  setState(() => _follow = true);
                  _camera();
                },
                child: const Icon(Icons.navigation),
              ),
          ]),
        ),
        // Résumé du trajet
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(Y.rSheet)), boxShadow: [BoxShadow(color: Color(0x291B2735), blurRadius: 30)]),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_arrived ? 'Arrivé' : '$etaMin min', style: const TextStyle(fontFamily: Y.display, fontSize: 22, color: Y.feuille)),
                  const SizedBox(height: 2),
                  Text(
                    _arrived ? widget.label : '${_fmtDist(_remainingM)} · arrivée ${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Y.ardoise),
                  ),
                ]),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50), backgroundColor: _arrived ? Y.feuille : Y.alerte),
                onPressed: () => Navigator.of(context).pop(_arrived),
                child: Text(_arrived ? 'Terminer' : 'Quitter'),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
