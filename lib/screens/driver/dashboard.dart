import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/api.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/sos.dart';
import '../../widgets/call_options.dart';
import '../../widgets/ui.dart';
import '../../widgets/yawi_map.dart';
import '../common/navigation.dart';

/// Tableau de bord chauffeur : en ligne / hors ligne, demandes entrantes (sonnerie), course en cours.
class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> with WidgetsBindingObserver {
  final _map = MapController();
  Timer? _poll;
  Timer? _tick;
  StreamSubscription<Position>? _gps;
  StreamSubscription<Map<String, dynamic>>? _push;
  LatLng? _me;
  bool _online = false;
  bool _toggling = false;
  bool _busy = false;
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _requests = [];
  final Map<String, DateTime> _deadlines = {};
  final Set<String> _seen = {};
  int? _nudgeFor;
  String? _lastStatus;
  LocationProblem? _locProblem;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _feed();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _feed());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_requests.isNotEmpty && mounted) setState(() {});
    });
    _push = Alerts.instance.received.stream.listen((_) => _feed());
    _startGps();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tick?.cancel();
    _gps?.cancel();
    _push?.cancel();
    Sonnerie.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _feed();
  }

  Future<void> _startGps() async {
    final problem = await Geo.ensurePermission();
    if (!mounted) return;
    setState(() => _locProblem = problem);
    if (problem != null) return;
    _gps?.cancel();
    _gps = Geo.stream().listen((p) {
      final first = _me == null;
      _me = LatLng(p.latitude, p.longitude);
      if (first) _map.move(_me!, 15.5);
      if (mounted) setState(() {});
      // Position envoyée au plus toutes les 8 s quand le chauffeur est en ligne
      if (_online && DateTime.now().difference(_lastSent).inSeconds >= 8) {
        _lastSent = DateTime.now();
        _api.post('/driver/location', {'lat': p.latitude, 'lng': p.longitude}).catchError((_) => <String, dynamic>{});
      }
    }, onError: (_) {});
  }

  Future<void> _feed() async {
    try {
      final f = await _api.get('/driver/feed');
      if (!mounted) return;
      final requests = ((f['requests'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final current = f['current'] is Map ? Map<String, dynamic>.from(f['current'] as Map) : null;

      for (final r in requests) {
        final ref = r['reference'].toString();
        _deadlines.putIfAbsent(ref, () => DateTime.now().add(Duration(seconds: (r['expires_in'] as num?)?.toInt() ?? 30)));
      }
      final fresh = requests.where((r) => !_seen.contains(r['reference'])).toList();
      if (fresh.isNotEmpty) _seen.addAll(fresh.map((r) => r['reference'].toString()));

      // Sonnerie : nouvelle demande, ou relance du passager
      final nudge = current?['nudge_at'] as int?;
      final shouldRing = requests.isNotEmpty || (nudge != null && nudge != _nudgeFor);
      if (shouldRing && !Sonnerie.instance.ringing) Sonnerie.instance.start();
      if (!shouldRing && Sonnerie.instance.ringing) Sonnerie.instance.stop();

      final status = current?['status']?.toString();
      if (_lastStatus != null && status != _lastStatus && status == 'cancelled') {
        toast(context, 'Le passager a annulé la course.', error: true);
      }
      _lastStatus = status;

      setState(() {
        _online = f['online'] == true;
        _stats = Map<String, dynamic>.from(f['stats'] as Map? ?? {});
        _current = current;
        _requests = requests;
      });
    } on ApiException catch (e) {
      if (e.status == 403 && mounted) context.read<Session>().refresh().catchError((_) {});
    } catch (_) {}
  }

  Future<void> _toggle(bool on) async {
    if (on && _locProblem != null) {
      await Geo.openSettings(_locProblem!);
      return _startGps();
    }
    setState(() => _toggling = true);
    try {
      final res = await _api.post('/driver/online', {'online': on});
      setState(() => _online = res['online'] == true);
      if (_online && _me != null) {
        _lastSent = DateTime.now();
        await _api.post('/driver/location', {'lat': _me!.latitude, 'lng': _me!.longitude});
      }
      HapticFeedback.mediumImpact();
      _feed();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _act(String ref, String action, [Map<String, dynamic>? data]) async {
    setState(() => _busy = true);
    try {
      final res = await _api.post('/driver/rides/$ref/$action', data);
      if (mounted && res['message'] != null) toast(context, res['message'].toString());
      if (action == 'accept' || action == 'decline') {
        await Sonnerie.instance.stop();
        _requests.removeWhere((r) => r['reference'] == ref);
      }
      await _feed();
      return;
    } catch (e) {
      if (mounted) toastError(context, e);
      await _feed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ackNudge(String ref) async {
    _nudgeFor = _current?['nudge_at'] as int?;
    await Sonnerie.instance.stop();
    _api.post('/driver/rides/$ref/nudge/ack').catchError((_) => <String, dynamic>{});
  }

  Future<String?> _askCode(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(hint, style: const TextStyle(color: Y.ardoise)),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: Y.display, fontSize: 28, letterSpacing: 10),
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Valider')),
        ],
      ),
    );
  }

  Future<void> _start(Map<String, dynamic> r) async {
    final code = await _askCode('Code du passager', r['kind'] == 'delivery' ? 'Demandez le code de collecte à l\'expéditeur.' : 'Demandez au passager son code à 4 chiffres.');
    if (code != null && code.length == 4) _act(r['reference'].toString(), 'start', {'otp': code});
  }

  Future<void> _complete(Map<String, dynamic> r) async {
    final ref = r['reference'].toString();
    if (r['kind'] == 'delivery') {
      final code = await _askCode('Code de livraison', 'Demandez au destinataire le code reçu par SMS.');
      if (code == null || code.length != 4) return;
      await _act(ref, 'complete', {'code': code});
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Terminer la course ?'),
          content: Text('Montant : ${r['fare_label']} · ${r['payment_method']}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Pas encore')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminer')),
          ],
        ),
      );
      if (ok != true) return;
      await _act(ref, 'complete');
    }
    if (mounted) _ratePassenger(ref);
  }

  Future<void> _ratePassenger(String ref) async {
    int stars = 5;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Notez le passager', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(iconSize: 40, onPressed: () => set(() => stars = i), icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE0A100))),
            ]),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer')),
          ]),
        ),
      ),
    );
    if (sent == true) {
      _api.post('/driver/rides/$ref/rate', {'stars': stars}).catchError((_) => <String, dynamic>{});
    }
  }

  Future<void> _release(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Relâcher la course ?'),
        content: const Text('Elle sera proposée à un autre chauffeur. Des annulations répétées baissent votre priorité.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Y.alerte, minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Relâcher')),
        ],
      ),
    );
    if (ok == true) _act(ref, 'cancel');
  }

  /// Guidage GPS intégré (plus de Google Maps) vers le point de prise en charge ou la destination.
  Future<void> _navigate(Map<String, dynamic> point, String label) async {
    final arrived = await NavigationScreen.open(context, LatLng((point['lat'] as num).toDouble(), (point['lng'] as num).toDouble()), label);
    if (arrived == true && mounted && _current?['status'] == 'accepted') {
      toast(context, 'Vous êtes au point de prise en charge : touchez « Je suis arrivé ».');
    }
    _feed();
  }

  LatLng _ll(dynamic p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final cur = _current;
    final req = _requests.isNotEmpty ? _requests.first : null;
    final pins = <Pin>[
      if (_me != null) Pin(_me!, PinKind.driver),
      if (cur != null) ...[Pin(_ll(cur['pickup']), PinKind.pickup), Pin(_ll(cur['dropoff']), PinKind.dropoff)],
      if (cur == null && req != null) ...[Pin(_ll(req['pickup']), PinKind.pickup), Pin(_ll(req['dropoff']), PinKind.dropoff)],
    ];

    return Scaffold(
      body: Stack(children: [
        YawiMap(controller: _map, center: _me ?? const LatLng(9.537, -13.6773), zoom: 14, pins: pins),
        // Barre du haut : interrupteur en ligne + chiffres du jour
        Positioned(
          left: 12, right: 12, top: MediaQuery.of(context).padding.top + 8,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              decoration: BoxDecoration(color: _online ? Y.nuit : Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: Y.ombre),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: _online ? const Color(0xFF3DDC97) : Y.ardoise, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Text(_online ? 'En ligne' : 'Hors ligne', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _online ? Colors.white : Y.nuit))),
                if (_toggling) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                Switch(value: _online, onChanged: _toggling ? null : _toggle),
              ]),
            ),
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerRight, child: SosButton()),
            const SizedBox(height: 8),
            Row(children: [
              _stat('Aujourd\'hui', '${_stats['earnings_label'] ?? '0'} GNF'),
              const SizedBox(width: 8),
              _stat('Courses', '${_stats['rides_today'] ?? 0}'),
              const SizedBox(width: 8),
              _stat('Note', '${_stats['rating'] ?? '–'} ★'),
            ]),
            if (_locProblem != null) ...[
              const SizedBox(height: 8),
              Panel(
                border: Y.alerte,
                padding: const EdgeInsets.all(12),
                onTap: () async {
                  await Geo.openSettings(_locProblem!);
                  _startGps();
                },
                child: Row(children: [
                  const Icon(Icons.location_off, color: Y.alerte),
                  const SizedBox(width: 10),
                  Expanded(child: Text(Geo.explain(_locProblem!))),
                ]),
              ),
            ],
          ]),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: cur != null
                    ? _currentCard(cur)
                    : req != null
                        ? _requestCard(req)
                        : _idleCard(),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: Y.ombre),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: Y.ardoise)),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _idleCard() => Panel(
        key: const ValueKey('attente'),
        child: Row(children: [
          Icon(_online ? Icons.radar : Icons.power_settings_new, color: _online ? Y.feuille : Y.ardoise, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(
            _online ? 'Vous êtes visible. Les demandes proches s\'affichent ici avec une sonnerie.' : 'Passez en ligne pour recevoir des courses.',
            style: const TextStyle(height: 1.35),
          )),
        ]),
      );

  Widget _requestCard(Map<String, dynamic> r) {
    final ref = r['reference'].toString();
    final left = _deadlines[ref]?.difference(DateTime.now()).inSeconds.clamp(0, 999) ?? 0;
    final delivery = r['kind'] == 'delivery';
    return Container(
      key: ValueKey('demande-$ref'),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Y.rCard), border: Border.all(color: Y.braise, width: 2), boxShadow: Y.ombre),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Y.braiseVoile, borderRadius: BorderRadius.circular(99)),
            child: Text(delivery ? 'Nouvelle livraison' : 'Nouvelle course', style: const TextStyle(color: Y.braiseBtn, fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          Text('${left}s', style: const TextStyle(fontWeight: FontWeight.w700, color: Y.ardoise)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(r['fare_label'].toString(), style: const TextStyle(fontFamily: Y.display, fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(child: Text('${r['payment_method']} · ${r['service']}', style: const TextStyle(color: Y.ardoise))),
        ]),
        const SizedBox(height: 4),
        Text(
          'À ${r['pickup_distance_km'] ?? '?'} km · trajet ${r['distance_km'] ?? '?'} km, ~${r['duration_min'] ?? '?'} min',
          style: const TextStyle(color: Y.ardoise, fontSize: 13),
        ),
        const SizedBox(height: 12),
        RouteLines(from: r['pickup']['address'].toString(), to: r['dropoff']['address'].toString(), dense: true),
        if (r['parcel'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Colis : ${r['parcel']}', style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        Text('${r['passenger']} · ★ ${(r['passenger_rating'] as num? ?? 5).toStringAsFixed(1)}${r['for_other'] == true ? ' · pour un proche' : ''}', style: const TextStyle(color: Y.ardoise)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: BusyButton(label: 'Ignorer', outlined: true, busy: false, onPressed: _busy ? null : () => _act(ref, 'decline'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: BusyButton(label: 'Accepter', busy: _busy, onPressed: () => _act(ref, 'accept'))),
        ]),
      ]),
    );
  }

  Widget _currentCard(Map<String, dynamic> r) {
    final ref = r['reference'].toString();
    final status = r['status']?.toString();
    final colors = StatusColors.of(status);
    final p = Map<String, dynamic>.from(r['passenger'] as Map? ?? {});
    final toPickup = status == 'accepted' || status == 'arrived';
    final nudged = r['nudge_at'] != null && r['nudge_at'] != _nudgeFor;

    return Container(
      key: ValueKey('course-$ref-$status'),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Y.rCard), boxShadow: Y.ombre),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: colors.background,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(StatusColors.icon(status), color: colors.text),
            const SizedBox(width: 8),
            Expanded(child: Text(r['status_label'].toString(), style: TextStyle(color: colors.text, fontWeight: FontWeight.w700, fontSize: 16))),
            Text(r['driver_earnings_label']?.toString() ?? r['fare_label'].toString(), style: TextStyle(color: colors.text, fontWeight: FontWeight.w700)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (nudged) ...[
              Panel(
                border: Y.braise,
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  const Icon(Icons.notifications_active, color: Y.braiseBtn),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Le passager vous relance', style: TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(onPressed: () => _ackNudge(ref), child: const Text('OK')),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Avatar(initials: p['initials']?.toString() ?? '?', size: 44),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  p['ordered_by'] != null ? 'Commandé par ${p['ordered_by']}' : '★ ${(p['rating'] as num? ?? 5).toStringAsFixed(1)} · ${r['payment_method']}',
                  style: const TextStyle(color: Y.ardoise, fontSize: 13),
                ),
              ])),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Y.feuille),
                tooltip: 'Appeler',
                onPressed: () => CallOptions.show(
                  context,
                  reference: ref,
                  name: p['name']?.toString() ?? 'le client',
                  phone: p['phone']?.toString(),
                  onNudge: toPickup ? () => _act(ref, 'nudge') : null,
                ),
                icon: const Icon(Icons.call, color: Colors.white),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Y.nuit),
                tooltip: 'Itinéraire',
                onPressed: () => _navigate(toPickup ? r['pickup'] : r['dropoff'], (toPickup ? r['pickup'] : r['dropoff'])['address'].toString()),
                icon: const Icon(Icons.navigation_outlined, color: Colors.white),
              ),
            ]),
            const SizedBox(height: 12),
            RouteLines(from: r['pickup']['address'].toString(), to: r['dropoff']['address'].toString(), dense: true),
            if (r['kind'] == 'delivery' && r['parcel'] is Map) ...[
              const SizedBox(height: 8),
              Text('Colis : ${r['parcel']['type']}${r['parcel']['fragile'] == true ? ' · fragile' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            if (toPickup || status == 'in_progress') ...[
              OutlinedButton.icon(
                onPressed: () => _navigate(toPickup ? r['pickup'] : r['dropoff'], (toPickup ? r['pickup'] : r['dropoff'])['address'].toString()),
                icon: const Icon(Icons.navigation_rounded),
                label: Text(toPickup ? 'Guidage vers le client' : 'Guidage vers la destination'),
              ),
              const SizedBox(height: 10),
            ],
            if (status == 'accepted')
              BusyButton(label: 'Je suis arrivé', icon: Icons.place, busy: _busy, onPressed: () => _act(ref, 'arrived')),
            if (status == 'arrived')
              BusyButton(label: r['kind'] == 'delivery' ? 'Colis récupéré' : 'Démarrer la course', icon: Icons.play_arrow_rounded, busy: _busy, onPressed: () => _start(r)),
            if (status == 'in_progress')
              BusyButton(label: r['kind'] == 'delivery' ? 'Colis livré' : 'Terminer la course', icon: Icons.flag_rounded, busy: _busy, onPressed: () => _complete(r)),
            if (toPickup)
              Row(children: [
                Expanded(child: TextButton.icon(onPressed: _busy ? null : () => _act(ref, 'nudge'), icon: const Icon(Icons.notifications_outlined), label: const Text('Relancer'))),
                Expanded(child: TextButton(style: TextButton.styleFrom(foregroundColor: Y.alerte), onPressed: _busy ? null : () => _release(ref), child: const Text('Relâcher'))),
              ]),
          ]),
        ),
      ]),
    );
  }
}
