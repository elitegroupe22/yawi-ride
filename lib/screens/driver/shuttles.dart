import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/navigation.dart';
import 'shuttle_scan.dart';

/// Onglet Navettes du chauffeur : tournées du jour et des prochains jours.
class ShuttlesScreen extends StatefulWidget {
  const ShuttlesScreen({super.key});

  @override
  State<ShuttlesScreen> createState() => _ShuttlesScreenState();
}

class _ShuttlesScreenState extends State<ShuttlesScreen> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<Session>().api.get('/driver/shuttles');
      if (mounted) {
        setState(() {
          _d = res;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<Map<String, dynamic>> _list(String key) => ((_d?[key] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final today = _list('today');
    final upcoming = _list('upcoming');
    return Scaffold(
      appBar: AppBar(title: const Text('Navettes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _d == null
            ? ListView(children: [if (_error != null) RetryView(message: _error!, onRetry: _load) else const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))])
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                if (today.isEmpty && upcoming.isEmpty)
                  const EmptyState(icon: Icons.directions_bus_outlined, title: 'Aucune navette', message: 'Les tournées d\'entreprise qui vous sont confiées apparaîtront ici.'),
                if (today.isNotEmpty) const SectionTitle('Aujourd\'hui'),
                for (final t in today) _TripTile(t: t, onTap: () => _open(t)),
                if (upcoming.isNotEmpty) const SectionTitle('Prochains jours'),
                for (final t in upcoming) _TripTile(t: t, onTap: () => _open(t)),
                if ((_d?['done_this_month'] as num? ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('${_d!['done_this_month']} tournée(s) effectuée(s) ce mois-ci', textAlign: TextAlign.center, style: const TextStyle(color: Y.ardoise)),
                  ),
              ]),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShuttleTripScreen(reference: t['reference'].toString())));
    _load();
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({required this.t, required this.onTap});
  final Map<String, dynamic> t;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final running = t['status'] == 'in_progress';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        onTap: onTap,
        border: running ? Y.braise : null,
        child: Row(children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: running ? Y.braise : Y.nuit, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(t['scheduled_at'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              Text(t['direction_label'].toString(), style: const TextStyle(color: Color(0xFFE4E9F0), fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(t['company'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Y.ardoise)),
              const SizedBox(height: 4),
              Text(
                [
                  if (t['date_label'] != 'Aujourd\'hui') t['date_label'],
                  if (t['passengers'] != null) '${t['passengers']} passager(s)',
                  if (running && t['boarded'] != null) '${t['boarded']} pointé(s)',
                ].join(' · '),
                style: const TextStyle(color: Y.ardoise, fontSize: 13),
              ),
            ]),
          ),
          StatusPill(status: t['status']?.toString(), label: t['status_label'].toString()),
        ]),
      ),
    );
  }
}

/// Une tournée : départ, scan en rafale, prochain arrêt avec guidage, assistant d'arrivée, liste des passagers.
class ShuttleTripScreen extends StatefulWidget {
  const ShuttleTripScreen({super.key, required this.reference});
  final String reference;

  @override
  State<ShuttleTripScreen> createState() => _ShuttleTripScreenState();
}

class _ShuttleTripScreenState extends State<ShuttleTripScreen> {
  Map<String, dynamic>? _t;
  String? _error;
  bool _busy = false;
  Timer? _poll;
  StreamSubscription<Position>? _gps;
  LatLng? _me;
  DateTime _lastSent = DateTime(2000);
  final _player = AudioPlayer(playerId: 'yawi-tournee');

  // Assistant d'arrivée : arrêt devant lequel on se trouve, et arrêt quitté sans pointage.
  int? _hereStop;
  final Set<int> _announced = {};
  final Set<int> _asked = {};

  Api get _api => context.read<Session>().api;
  bool get _running => _t?['status'] == 'in_progress';
  bool get _aller => _t?['direction'] == 'aller';
  List<Map<String, dynamic>> get _stops => ((_t?['stops'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_running) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gps?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await _api.get('/driver/shuttles/${widget.reference}');
      if (!mounted) return;
      setState(() {
        _t = t;
        _error = null;
      });
      _syncGps();
    } on ApiException catch (e) {
      if (mounted && _t == null) setState(() => _error = e.message);
    }
  }

  /// Pendant la tournée : position envoyée (alertes « navette à proximité » aux passagers) et assistant d'arrivée.
  Future<void> _syncGps() async {
    if (_running && _gps == null) {
      if (await Geo.ensurePermission() != null) return;
      _gps = Geo.stream().listen(_onPosition, onError: (_) {});
    } else if (!_running && _gps != null) {
      await _gps!.cancel();
      _gps = null;
    }
  }

  void _onPosition(Position p) {
    _me = LatLng(p.latitude, p.longitude);
    if (DateTime.now().difference(_lastSent).inSeconds >= 8) {
      _lastSent = DateTime.now();
      _api.post('/driver/location', {'lat': p.latitude, 'lng': p.longitude}).catchError((_) => <String, dynamic>{});
    }
    if (!_aller) {
      if (mounted) setState(() {});
      return;
    }
    // Arrêt le plus proche encore à pointer
    const d = Distance();
    Map<String, dynamic>? near;
    double best = double.infinity;
    for (final s in _stops.where((s) => s['status'] == 'pending' && s['lat'] != null)) {
      final m = d.as(LengthUnit.Meter, _me!, LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()));
      if (m < best) {
        best = m;
        near = s;
      }
    }
    final previous = _hereStop;
    if (near != null && best <= 80) {
      final id = near['id'] as int;
      _hereStop = id;
      if (_announced.add(id)) {
        HapticFeedback.mediumImpact();
        _player.play(AssetSource('sounds/bip.wav'));
      }
    } else {
      _hereStop = null;
    }
    // On repart d'un arrêt sans avoir pointé la personne : on propose « absent ».
    if (previous != null && _hereStop == null) {
      final s = _stops.where((x) => x['id'] == previous).firstOrNull;
      if (s != null && s['status'] == 'pending' && s['lat'] != null && _asked.add(previous)) {
        final m = d.as(LengthUnit.Meter, _me!, LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()));
        if (m > 150) _askLeft(s);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _askLeft(Map<String, dynamic> s) async {
    _player.play(AssetSource('sounds/attention.wav'));
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Vous repartez sans ${s['name']} ?'),
        content: const Text('Sa carte n\'a pas été scannée à cet arrêt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Plus tard')),
          TextButton(onPressed: () => Navigator.pop(c, 'a-bord'), child: const Text('Il est à bord')),
          TextButton(onPressed: () => Navigator.pop(c, 'absent'), child: const Text('Absent', style: TextStyle(color: Y.alerte))),
        ],
      ),
    );
    if (choice != null) _stopAction(s, choice);
  }

  Future<void> _do(String path, {String? success}) async {
    setState(() => _busy = true);
    try {
      final res = await _api.post(path);
      if (!mounted) return;
      if (res['trip'] is Map) setState(() => _t = Map<String, dynamic>.from(res['trip'] as Map));
      if (success != null || res['message'] != null) toast(context, (res['message'] ?? success).toString());
      _syncGps();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    await _do('/driver/shuttles/${widget.reference}/start');
    if (mounted && _running) _scan();
  }

  Future<void> _complete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Terminer la tournée ?'),
        content: Text(_aller
            ? 'Tous les passagers doivent être pointés à bord ou absents.'
            : 'Les passagers encore à bord seront marqués déposés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminer')),
        ],
      ),
    );
    if (ok == true) await _do('/driver/shuttles/${widget.reference}/complete');
  }

  Future<void> _stopAction(Map<String, dynamic> s, String action) =>
      _do('/driver/shuttles/${widget.reference}/stops/${s['id']}/$action');

  void _scan() {
    final t = _t;
    if (t == null) return;
    ShuttleScanScreen.open(context, t, onChanged: (nt) {
      if (mounted) setState(() => _t = nt);
    }).then((_) => _load());
  }

  Future<void> _guide(Map<String, dynamic> target, String label) async {
    if (target['lat'] == null) return;
    await NavigationScreen.open(context, LatLng((target['lat'] as num).toDouble(), (target['lng'] as num).toDouble()), label);
  }

  String? _distance(Map<String, dynamic> s) {
    if (_me == null || s['lat'] == null) return null;
    final m = const Distance().as(LengthUnit.Meter, _me!, LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble()));
    return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Navette')),
        body: _error != null ? RetryView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final counts = Map<String, dynamic>.from((t['counts'] as Map?) ?? {});
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    final boarded = (counts['boarded'] as num?)?.toInt() ?? 0;
    final dropped = (counts['dropped'] as num?)?.toInt() ?? 0;
    final done = _aller ? boarded + dropped : dropped;
    final stops = _stops;
    final next = _aller ? stops.where((s) => s['status'] == 'pending').firstOrNull : null;
    final here = _hereStop == null ? null : stops.where((s) => s['id'] == _hereStop).firstOrNull;
    final site = Map<String, dynamic>.from((t['site'] as Map?) ?? {});

    return Scaffold(
      appBar: AppBar(title: Text('${t['direction_label']} · ${t['scheduled_at']}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
          // En-tête : société, progression
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: Y.nuit, borderRadius: BorderRadius.circular(Y.rCard)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t['title'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17))),
                StatusPill(status: t['status']?.toString(), label: t['status_label'].toString()),
              ]),
              const SizedBox(height: 2),
              Text('${t['company']} · ${t['date_label']}', style: const TextStyle(color: Color(0xFFC9D2DE))),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$done', style: const TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 30, height: 1)),
                Text(' / $total', style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(child: Text(_aller ? 'passagers à bord' : 'passagers déposés${boarded > 0 ? ' · $boarded à bord' : ''}', style: const TextStyle(color: Colors.white))),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8, backgroundColor: Colors.white24, color: Y.feuille),
              ),
              if ((counts['no_show'] as num? ?? 0) > 0 || (counts['excused'] as num? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${counts['no_show']} absent(s) · ${counts['excused']} excusé(s)', style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 13)),
                ),
            ]),
          ),

          // Assistant : on est devant chez quelqu'un
          if (_running && here != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: Y.braise,
                borderRadius: BorderRadius.circular(Y.rCard),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Y.rCard),
                  onTap: _scan,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Avatar(initials: here['initials'].toString(), photo: here['photo']?.toString(), size: 46),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Vous êtes chez ${here['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                          const Text('Touchez pour scanner sa carte', style: TextStyle(color: Colors.white)),
                        ]),
                      ),
                      const Icon(Icons.qr_code_scanner, color: Colors.white, size: 30),
                    ]),
                  ),
                ),
              ),
            ),

          // Prochain arrêt (aller) ou destination (retour)
          if (_running && next != null && here == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Prochain arrêt · n° ${next['position']}', style: const TextStyle(color: Y.ardoise, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (_distance(next) != null) Text(_distance(next)!, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Avatar(initials: next['initials'].toString(), photo: next['photo']?.toString(), size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(next['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(next['address']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Y.ardoise)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => dial(next['phone']?.toString()), icon: const Icon(Icons.call, size: 18), label: const Text('Appeler'))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton.icon(onPressed: () => _guide(next, next['name'].toString()), icon: const Icon(Icons.navigation, size: 18), label: const Text('Guidage'))),
                  ]),
                ]),
              ),
            ),
          if (_running && !_aller && site['lat'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(onPressed: () => _guide(site, site['name'].toString()), icon: const Icon(Icons.navigation), label: Text('Guidage vers ${site['name']}')),
            ),

          if (t['notes'] != null && t['notes'].toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: Panel(child: Text('Consigne : ${t['notes']}'))),

          SectionTitle(_aller ? 'Ordre de ramassage' : 'Passagers'),
          for (final s in stops) _StopTile(s: s, running: _running, aller: _aller, distance: _distance(s), onAction: (a) => _stopAction(s, a)),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: switch (t['status']) {
            'scheduled' => BusyButton(label: 'Démarrer la tournée et scanner', icon: Icons.play_arrow_rounded, busy: _busy, onPressed: _start),
            'in_progress' => Row(children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    style: FilledButton.styleFrom(backgroundColor: Y.braiseBtn),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scanner les cartes'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: OutlinedButton(onPressed: _busy ? null : _complete, child: const Text('Terminer'))),
              ]),
            _ => Text('Tournée ${t['status_label'].toString().toLowerCase()}.', textAlign: TextAlign.center, style: const TextStyle(color: Y.ardoise)),
          },
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.s, required this.running, required this.aller, required this.onAction, this.distance});
  final Map<String, dynamic> s;
  final bool running;
  final bool aller;
  final String? distance;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final status = s['status']?.toString();
    final (bg, fg) = switch (status) {
      'boarded' => (Y.feuilleVoile, const Color(0xFF0A6B44)),
      'dropped' => (const Color(0xFFE3EEFC), const Color(0xFF1E5BB0)),
      'no_show' => (const Color(0xFFFDE8EB), const Color(0xFFA50E26)),
      'excused' => (Y.brume, Y.ardoise),
      _ => (const Color(0xFFFFF4D6), const Color(0xFF7A5300)),
    };
    final actions = <(String, String)>[
      if (running && status == 'pending') ('a-bord', 'À bord'),
      if (running && status == 'pending') ('absent', 'Absent'),
      if (running && !aller && status == 'boarded') ('depose', 'Déposé'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          SizedBox(width: 26, child: Text('${s['position']}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: Y.ardoise))),
          Avatar(initials: s['initials'].toString(), photo: s['photo']?.toString(), size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text([s['address'], if (distance != null && status == 'pending') distance].whereType<String>().join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Y.ardoise, fontSize: 12.5)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                child: Text('${s['status_label']}${s['time'] != null ? ' · ${s['time']}' : ''}', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (v) => v == 'appeler' ? dial(s['phone']?.toString()) : onAction(v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'appeler', child: Text('Appeler')),
              for (final a in actions) PopupMenuItem(value: a.$1, child: Text(a.$2)),
            ],
          ),
        ]),
      ),
    );
  }
}
