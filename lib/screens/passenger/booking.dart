import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../widgets/yawi_map.dart';
import '../common/place_search.dart';

/// Itinéraire, estimation par service, mode de paiement puis commande.
/// Retourne la référence de la course créée.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, this.pickup, required this.dropoff});
  final Place? pickup;
  final Place dropoff;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _map = MapController();
  Place? _from;
  late Place _to;
  List<LatLng> _route = [];
  List<Map<String, dynamic>> _services = [];
  List<LatLng> _nearby = [];
  int? _service;
  String _payment = 'cash';
  bool _forOther = false;
  final _riderName = TextEditingController();
  final _riderPhone = TextEditingController();
  bool _estimating = false;
  bool _ordering = false;
  String? _error;

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _from = widget.pickup;
    _to = widget.dropoff;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_from == null) {
        _pickFrom();
      } else {
        _refresh();
      }
    });
  }

  Future<void> _pickFrom() async {
    final p = await PlaceSearchScreen.pick(context, title: 'Point de départ');
    if (p == null) {
      if (_from == null && mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _from = p);
    _refresh();
  }

  Future<void> _pickTo() async {
    final p = await PlaceSearchScreen.pick(context, title: 'Destination');
    if (p == null) return;
    setState(() => _to = p);
    _refresh();
  }

  Future<void> _refresh() async {
    if (_from == null) return;
    setState(() {
      _estimating = true;
      _error = null;
    });
    final coords = {'pickup_lat': _from!.lat, 'pickup_lng': _from!.lng, 'dropoff_lat': _to.lat, 'dropoff_lng': _to.lng};
    try {
      final results = await Future.wait([
        _api.post('/estimate', coords),
        _api.get('/geo/route', query: {'from_lat': _from!.lat, 'from_lng': _from!.lng, 'to_lat': _to.lat, 'to_lng': _to.lng}),
      ]);
      if (!mounted) return;
      final est = results[0];
      final route = results[1];
      setState(() {
        _services = ((est['services'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((s) => s['allowed'] != false).toList();
        _nearby = ((est['drivers'] as List?) ?? []).map((d) => LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble())).toList();
        _route = ((route['points'] as List?) ?? []).map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList();
        if (_services.isNotEmpty && !_services.any((s) => s['id'] == _service)) {
          _service = (_services.firstWhere((s) => (s['drivers'] ?? 0) > 0, orElse: () => _services.first))['id'] as int;
        }
      });
      YawiMap.fit(_map, _route.isNotEmpty ? _route : [_from!.point, _to.point], bottom: MediaQuery.of(context).size.height * .5);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _order() async {
    if (_service == null || _from == null) return;
    if (_forOther && (_riderName.text.trim().isEmpty || _riderPhone.text.trim().length < 8)) {
      toast(context, 'Indiquez le nom et le téléphone de la personne à transporter.', error: true);
      return;
    }
    setState(() => _ordering = true);
    try {
      final res = await _api.post('/rides', {
        'pickup_address': _from!.address, 'pickup_lat': _from!.lat, 'pickup_lng': _from!.lng,
        'dropoff_address': _to.address, 'dropoff_lat': _to.lat, 'dropoff_lng': _to.lng,
        'service_type_id': _service,
        'payment_method': _payment,
        'for_other': _forOther,
        if (_forOther) 'rider_name': _riderName.text.trim(),
        if (_forOther) 'rider_phone': _riderPhone.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(res['reference'].toString());
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final wallet = (session.user['wallet'] as num?)?.toDouble() ?? 0;
    final selected = _services.where((s) => s['id'] == _service).firstOrNull;
    final fare = (selected?['fare'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      body: Stack(children: [
        YawiMap(
          controller: _map,
          center: _from?.point ?? _to.point,
          zoom: 14,
          route: _route,
          pins: [
            for (final n in _nearby) Pin(n, PinKind.nearby),
            if (_from != null) Pin(_from!.point, PinKind.pickup),
            Pin(_to.point, PinKind.dropoff),
          ],
        ),
        Positioned(
          left: 12, top: MediaQuery.of(context).padding.top + 8,
          child: FloatingActionButton.small(
            heroTag: 'retour', backgroundColor: Colors.white, foregroundColor: Y.nuit,
            onPressed: () => Navigator.of(context).pop(), child: const Icon(Icons.arrow_back),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: .58, minChildSize: .35, maxChildSize: .92, snap: true,
          builder: (ctx, scroll) => Container(
            decoration: const BoxDecoration(color: Y.craie, borderRadius: BorderRadius.vertical(top: Radius.circular(Y.rSheet)), boxShadow: [BoxShadow(color: Color(0x291B2735), blurRadius: 40)]),
            child: Column(children: [
              Expanded(
                child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 20, 16), children: [
                  Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Y.trait, borderRadius: BorderRadius.circular(9)))),
                  const SizedBox(height: 14),
                  _addressRow(Icons.trip_origin, Y.feuille, 'Départ', _from?.address ?? 'Choisir le départ', _pickFrom),
                  const SizedBox(height: 8),
                  _addressRow(Icons.location_on, Y.braise, 'Arrivée', _to.address, _pickTo),
                  const SectionTitle('Choisissez votre course'),
                  if (_estimating && _services.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    Panel(border: Y.alerte, child: Row(children: [
                      Expanded(child: Text(_error!)),
                      TextButton(onPressed: _refresh, child: const Text('Réessayer')),
                    ]))
                  else
                    for (final s in _services) ...[_serviceTile(s), const SizedBox(height: 8)],
                  const SectionTitle('Paiement'),
                  Row(children: [
                    Expanded(child: _payTile('cash', Icons.payments_outlined, 'Espèces', 'Au chauffeur')),
                    const SizedBox(width: 10),
                    Expanded(child: _payTile('wallet', Icons.account_balance_wallet_outlined, 'Portefeuille', money(wallet), disabled: wallet < fare && fare > 0)),
                  ]),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _forOther,
                    onChanged: (v) => setState(() => _forOther = v),
                    title: const Text('Pour quelqu\'un d\'autre', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Le chauffeur appellera cette personne.'),
                  ),
                  if (_forOther) ...[
                    TextField(controller: _riderName, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Nom de la personne')),
                    const SizedBox(height: 10),
                    TextField(controller: _riderPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone de la personne', prefixText: '+224 ')),
                  ],
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: BusyButton(
                    label: selected == null ? 'Commander' : 'Commander · ${selected['fare_label']}',
                    busy: _ordering,
                    onPressed: selected == null || _from == null ? null : _order,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _addressRow(IconData icon, Color color, String label, String value, VoidCallback onTap) => Material(
        color: Y.brume,
        borderRadius: BorderRadius.circular(Y.rCtrl),
        child: InkWell(
          borderRadius: BorderRadius.circular(Y.rCtrl),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Y.ardoise)),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
              const Icon(Icons.edit_outlined, size: 18, color: Y.ardoise),
            ]),
          ),
        ),
      );

  Widget _serviceTile(Map<String, dynamic> s) {
    final on = s['id'] == _service;
    final drivers = (s['drivers'] as num?)?.toInt() ?? 0;
    final eta = s['eta_min'];
    return Panel(
      border: on ? Y.nuit : Y.trait,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => setState(() => _service = s['id'] as int),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(color: on ? Y.nuit : Y.brume, borderRadius: BorderRadius.circular(12)),
          child: Icon(_serviceIcon(s['icon']?.toString()), color: on ? Y.braiseClair : Y.nuit),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 2),
          Text(
            drivers == 0 ? 'Aucun chauffeur à proximité' : (eta != null ? 'À $eta min · ${s['capacity']} places' : '$drivers chauffeur(s) proches'),
            style: TextStyle(fontSize: 13, color: drivers == 0 ? const Color(0xFF8A5A00) : Y.ardoise),
          ),
        ])),
        Text(s['fare_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
    );
  }

  Widget _payTile(String value, IconData icon, String label, String hint, {bool disabled = false}) {
    final on = _payment == value;
    return Opacity(
      opacity: disabled ? .5 : 1,
      child: Panel(
        border: on ? Y.nuit : Y.trait,
        padding: const EdgeInsets.all(12),
        onTap: disabled ? () => toast(context, 'Solde insuffisant : rechargez votre portefeuille ou payez en espèces.') : () => setState(() => _payment = value),
        child: Row(children: [
          Icon(icon, color: on ? Y.braiseBtn : Y.nuit),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(hint, style: const TextStyle(fontSize: 12.5, color: Y.ardoise), overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }
}

IconData _serviceIcon(String? icon) => switch (icon) {
      'bike' => Icons.two_wheeler,
      'auto' => Icons.electric_rickshaw,
      'suv' => Icons.airport_shuttle,
      'premium' => Icons.directions_car_filled,
      _ => Icons.local_taxi,
    };

IconData serviceIcon(String? icon) => _serviceIcon(icon);
