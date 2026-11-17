import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/sos.dart';
import '../../widgets/ui.dart';
import '../../widgets/yawi_map.dart';
import '../common/web_page.dart';

/// Suivi en direct d'une course ou d'une livraison côté passager.
class RideScreen extends StatefulWidget {
  const RideScreen({super.key, required this.reference});
  final String reference;

  static Future<void> open(BuildContext context, String reference) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => RideScreen(reference: reference)));

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with WidgetsBindingObserver {
  final _map = MapController();
  Map<String, dynamic>? _ride;
  String? _error;
  Timer? _timer;
  String? _lastStatus;
  int? _ringingFor;
  bool _busy = false;
  String? _fitKey;
  StreamSubscription<Map<String, dynamic>>? _push;

  Api get _api => context.read<Session>().api;
  String get _path => '/rides/${widget.reference}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
    _push = Alerts.instance.received.stream.listen((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _push?.cancel();
    if (_ringingFor != null) Sonnerie.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get(_path);
      if (!mounted) return;
      final status = r['status']?.toString();
      if (_lastStatus != null && status != _lastStatus && ['accepted', 'arrived', 'in_progress', 'completed'].contains(status)) {
        Sonnerie.instance.beep();
      }
      _lastStatus = status;
      if (r['is_active'] != true) _timer?.cancel();

      // Le chauffeur relance le passager : sonnerie jusqu'à confirmation
      final nudge = r['nudge_at'] as int?;
      if (nudge != null && nudge != _ringingFor && r['is_active'] == true) {
        _ringingFor = nudge;
        Sonnerie.instance.start();
      } else if (nudge == null && _ringingFor != null) {
        _ringingFor = null;
        Sonnerie.instance.stop();
      }

      setState(() {
        _ride = r;
        _error = null;
      });
      _fit();
    } on ApiException catch (e) {
      if (mounted && _ride == null) setState(() => _error = e.message);
    }
  }

  void _fit() {
    final r = _ride!;
    final pts = <LatLng>[_ll(r['pickup']), _ll(r['dropoff'])];
    final d = r['driver'];
    if (d is Map && d['lat'] != null && r['status'] != 'completed') pts.add(LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()));
    // Recadrage à chaque changement d'étape (et à l'apparition du chauffeur), pas à chaque actualisation
    final key = '${r['status']}-${d is Map && d['lat'] != null}';
    if (_fitKey != key) {
      _fitKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) YawiMap.fit(_map, pts, bottom: MediaQuery.of(context).size.height * .48);
      });
    }
  }

  LatLng _ll(dynamic p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());

  Future<void> _act(String action, [Map<String, dynamic>? data, String? done]) async {
    setState(() => _busy = true);
    try {
      final res = await _api.post('$_path/$action', data);
      if (mounted && (done ?? res['message']) != null) toast(context, (done ?? res['message']).toString());
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ack() async {
    _ringingFor = null;
    await Sonnerie.instance.stop();
    try {
      await _api.post('$_path/nudge/ack');
    } catch (_) {}
    _load();
  }

  Future<void> _cancel() async {
    final r = _ride!;
    final fee = (r['cancellation_fee'] as num?)?.toDouble() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r['kind'] == 'delivery' ? 'Annuler la livraison ?' : 'Annuler la course ?'),
        content: Text(r['driver'] != null && fee > 0
            ? 'Un chauffeur est déjà en route : des frais d\'annulation de ${money(fee)} peuvent s\'appliquer.'
            : 'Votre demande sera retirée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Garder')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Y.alerte, minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Annuler')),
        ],
      ),
    );
    if (ok == true) _act('cancel', {}, 'Course annulée.');
  }

  Future<void> _rate() async {
    int stars = 5;
    final comment = TextEditingController();
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Comment s\'est passée la course ?', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 40,
                  onPressed: () => set(() => stars = i),
                  icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFE0A100)),
                ),
            ]),
            TextField(controller: comment, maxLines: 2, decoration: const InputDecoration(hintText: 'Un mot pour le chauffeur (facultatif)')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Envoyer mon avis')),
          ]),
        ),
      ),
    );
    if (sent == true) _act('rate', {'stars': stars, 'comment': comment.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? RetryView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    final status = r['status']?.toString();
    final colors = StatusColors.of(status);
    final d = r['driver'] is Map ? Map<String, dynamic>.from(r['driver'] as Map) : null;
    final driverPoint = d != null && d['lat'] != null ? LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()) : null;
    final delivery = r['kind'] == 'delivery';

    return Scaffold(
      body: Stack(children: [
        YawiMap(
          controller: _map,
          center: _ll(r['pickup']),
          zoom: 14,
          pins: [
            Pin(_ll(r['pickup']), PinKind.pickup),
            Pin(_ll(r['dropoff']), PinKind.dropoff),
            if (driverPoint != null && r['is_active'] == true) Pin(driverPoint, PinKind.driver),
          ],
        ),
        Positioned(
          left: 12, top: MediaQuery.of(context).padding.top + 8,
          child: FloatingActionButton.small(heroTag: 'retour', backgroundColor: Colors.white, foregroundColor: Y.nuit, onPressed: () => Navigator.pop(context), child: const Icon(Icons.arrow_back)),
        ),
        if (r['is_active'] == true)
          Positioned(right: 12, top: MediaQuery.of(context).padding.top + 8, child: const SosButton()),
        DraggableScrollableSheet(
          initialChildSize: .46, minChildSize: .26, maxChildSize: .9, snap: true,
          builder: (ctx, scroll) => Container(
            decoration: const BoxDecoration(color: Y.craie, borderRadius: BorderRadius.vertical(top: Radius.circular(Y.rSheet)), boxShadow: [BoxShadow(color: Color(0x291B2735), blurRadius: 40)]),
            clipBehavior: Clip.antiAlias,
            child: ListView(controller: scroll, padding: EdgeInsets.zero, children: [
              // Bandeau de statut aux couleurs de l'état
              Container(
                color: colors.background,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: Column(children: [
                  Container(width: 40, height: 5, decoration: BoxDecoration(color: colors.border.withValues(alpha: .4), borderRadius: BorderRadius.circular(9))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(StatusColors.icon(status), color: colors.text, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['status_label'].toString(), style: TextStyle(color: colors.text, fontSize: 19, fontWeight: FontWeight.w700)),
                      Text(_subtitle(r, d), style: TextStyle(color: colors.text.withValues(alpha: .85))),
                    ])),
                  ]),
                  if (status == 'requested') ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(color: colors.border, backgroundColor: Colors.white, minHeight: 4, borderRadius: BorderRadius.circular(4)),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_ringingFor != null) ...[
                    Panel(
                      border: Y.braise,
                      child: Column(children: [
                        const Text('Votre chauffeur vous attend', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        FilledButton(onPressed: _ack, child: const Text('J\'arrive')),
                      ]),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (r['otp'] != null && ['accepted', 'arrived'].contains(status)) ...[
                    _code(delivery ? 'Code de collecte à donner au livreur' : 'Code à donner au chauffeur', r['otp'].toString()),
                    const SizedBox(height: 12),
                  ],
                  if (delivery && r['delivery_code'] != null && status == 'in_progress') ...[
                    _code('Code de livraison (à transmettre au destinataire)', r['delivery_code'].toString()),
                    const SizedBox(height: 12),
                  ],
                  if (d != null) ...[_driverCard(r, d), const SizedBox(height: 14)],
                  RouteLines(from: r['pickup']['address'].toString(), to: r['dropoff']['address'].toString()),
                  const SizedBox(height: 14),
                  Row(children: [
                    Text(r['service'].toString(), style: const TextStyle(color: Y.ardoise)),
                    const Text('  ·  ', style: TextStyle(color: Y.ardoise)),
                    Expanded(child: Text(r['payment_method'].toString(), style: const TextStyle(color: Y.ardoise))),
                    Text(r['fare_label'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ]),
                  if (r['rider'] is Map) ...[
                    const SizedBox(height: 8),
                    Text('Pour ${r['rider']['name']} · ${r['rider']['phone']}', style: const TextStyle(color: Y.ardoise)),
                  ],
                  const SizedBox(height: 20),
                  ..._actions(r, status, d),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  String _subtitle(Map<String, dynamic> r, Map<String, dynamic>? d) {
    switch (r['status']) {
      case 'requested':
        return 'Nous prévenons les chauffeurs proches…';
      case 'accepted':
        final eta = d?['eta_min'];
        return eta != null ? 'Arrivée dans environ $eta min' : 'Le chauffeur est en route';
      case 'arrived':
        return 'Le chauffeur est au point de départ';
      case 'in_progress':
        return 'En route vers la destination';
      case 'completed':
        return 'Merci d\'avoir voyagé avec Yawi';
      case 'expired':
        return 'Aucun chauffeur n\'a accepté à temps';
      default:
        return r['reference'].toString();
    }
  }

  Widget _code(String label, String code) => Panel(
        border: Y.nuit,
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(code, style: const TextStyle(fontFamily: Y.display, fontSize: 24, letterSpacing: 4)),
        ]),
      );

  Widget _driverCard(Map<String, dynamic> r, Map<String, dynamic> d) => Panel(
        border: Y.trait,
        child: Row(children: [
          Avatar(initials: d['initials']?.toString() ?? '?', photo: d['photo']?.toString(), size: 52),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(d['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0A100)),
              Text((d['rating'] as num? ?? 0).toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            Text([d['vehicle'], d['color']].where((e) => e != null && e.toString().isNotEmpty).join(' · '), style: const TextStyle(color: Y.ardoise)),
            if (d['plate'] != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Y.brume, borderRadius: BorderRadius.circular(6), border: Border.all(color: Y.trait)),
                child: Text(d['plate'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
          ])),
          if (d['phone'] != null)
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Y.feuille, foregroundColor: Colors.white),
              tooltip: 'Appeler',
              onPressed: () => dial(d['phone'].toString()),
              icon: const Icon(Icons.call),
            ),
        ]),
      );

  List<Widget> _actions(Map<String, dynamic> r, String? status, Map<String, dynamic>? d) {
    final orderer = r['is_orderer'] != false;
    final out = <Widget>[];
    if (r['is_active'] == true) {
      if (d != null && ['accepted', 'arrived'].contains(status)) {
        out.add(BusyButton(label: 'Relancer le chauffeur', icon: Icons.notifications_active_outlined, outlined: true, busy: _busy, onPressed: () => _act('nudge')));
        out.add(const SizedBox(height: 10));
      }
      if (orderer && status != 'in_progress') {
        out.add(TextButton(style: TextButton.styleFrom(foregroundColor: Y.alerte), onPressed: _busy ? null : _cancel, child: const Text('Annuler')));
      }
      if (r['tracking_url'] != null) {
        out.add(TextButton.icon(
          onPressed: () => openExternal('https://wa.me/?text=${Uri.encodeComponent('Suivez ma course Yawi en direct : ${r['tracking_url']}')}'),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Partager le suivi'),
        ));
      }
    } else if (status == 'completed') {
      if (r['rated'] != true && orderer) {
        out.add(FilledButton.icon(onPressed: _rate, icon: const Icon(Icons.star_rounded), label: const Text('Noter la course')));
        out.add(const SizedBox(height: 10));
      }
      out.add(OutlinedButton.icon(
        onPressed: () => WebPage.open(context, title: 'Reçu', path: '$_path/recu'),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Voir le reçu'),
      ));
    }
    return out;
  }
}
