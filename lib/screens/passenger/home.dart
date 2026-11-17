import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/sos.dart';
import '../../widgets/ui.dart';
import '../../widgets/yawi_map.dart';
import '../common/place_search.dart';
import 'booking.dart';
import 'delivery.dart';
import 'ride_tracking.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onShowRides});
  final VoidCallback onShowRides;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _map = MapController();
  LatLng? _me;
  Place? _pickup;
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _places = [];
  LocationProblem? _locProblem;
  bool _parcel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _locate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<Session>().api.get('/home');
      if (!mounted) return;
      context.read<Session>().updateUser(res['user']);
      setState(() {
        _active = ((res['active'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _places = ((res['places'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _locate() async {
    final api = context.read<Session>().api;
    final r = await Geo.current();
    if (!mounted) return;
    setState(() => _locProblem = r.problem);
    if (r.point == null) return;
    setState(() => _me = r.point);
    _map.move(r.point!, 15.5);
    final place = await Place.fromPosition(api, r.point!);
    if (mounted) setState(() => _pickup = place);
  }

  Future<void> _where() async {
    final to = await PlaceSearchScreen.pick(context, title: _parcel ? 'Livrer où ?' : 'Où allez-vous ?', suggestions: _places);
    if (to == null || !mounted) return;
    _book(to);
  }

  Future<void> _book(Place to) async {
    final page = _parcel ? DeliveryScreen(pickup: _pickup, dropoff: to) : BookingScreen(pickup: _pickup, dropoff: to);
    final ref = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => page));
    if (ref != null && mounted) {
      await RideScreen.open(context, ref);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final center = session.config['map']?['center'] as List?;
    final start = center != null ? LatLng((center[0] as num).toDouble(), (center[1] as num).toDouble()) : const LatLng(9.537, -13.6773);

    return Stack(children: [
      YawiMap(
        controller: _map,
        center: _me ?? start,
        zoom: 13,
        pins: [if (_me != null) Pin(_me!, PinKind.me)],
      ),
      Positioned(left: 16, top: MediaQuery.of(context).padding.top + 12, child: const SosButton()),
      // Bouton « me localiser »
      Positioned(
        right: 16,
        top: MediaQuery.of(context).padding.top + 12,
        child: FloatingActionButton.small(
          heroTag: 'moi',
          backgroundColor: Colors.white,
          foregroundColor: Y.nuit,
          onPressed: _locate,
          tooltip: 'Ma position',
          child: const Icon(Icons.my_location),
        ),
      ),
      DraggableScrollableSheet(
        initialChildSize: _active.isEmpty ? .42 : .52,
        minChildSize: .30,
        maxChildSize: .86,
        snap: true,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Y.craie,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Y.rSheet)),
            boxShadow: [BoxShadow(color: Color(0x291B2735), blurRadius: 40, offset: Offset(0, -12))],
          ),
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 10, 20, 24), children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Y.trait, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 16),
            Text('Bonjour ${session.firstName}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.local_taxi_outlined), label: Text('Course')),
                ButtonSegment(value: true, icon: Icon(Icons.inventory_2_outlined), label: Text('Colis')),
              ],
              selected: {_parcel},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Y.nuit,
                selectedForegroundColor: Colors.white,
                side: const BorderSide(color: Y.trait),
                minimumSize: const Size.fromHeight(46),
                textStyle: const TextStyle(fontFamily: Y.texte, fontWeight: FontWeight.w700),
              ),
              onSelectionChanged: (s) => setState(() => _parcel = s.first),
            ),
            const SizedBox(height: 14),
            Material(
              color: Y.brume,
              borderRadius: BorderRadius.circular(Y.rCtrl),
              child: InkWell(
                borderRadius: BorderRadius.circular(Y.rCtrl),
                onTap: _where,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                  child: Row(children: [
                    const Icon(Icons.search, color: Y.braiseBtn),
                    const SizedBox(width: 12),
                    Text(_parcel ? 'Où livrer le colis ?' : 'Où allez-vous ?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
            if (_locProblem != null) ...[
              const SizedBox(height: 10),
              Panel(
                border: const Color(0xFFE0A100),
                padding: const EdgeInsets.all(12),
                onTap: () => Geo.openSettings(_locProblem!),
                child: Row(children: [
                  const Icon(Icons.location_off_outlined, color: Color(0xFF8A5A00)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(Geo.explain(_locProblem!), style: const TextStyle(fontSize: 13.5))),
                  const Icon(Icons.chevron_right),
                ]),
              ),
            ] else if (_pickup != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.trip_origin, size: 16, color: Y.feuille),
                const SizedBox(width: 6),
                Expanded(child: Text('Départ : ${_pickup!.address}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Y.ardoise, fontSize: 13.5))),
              ]),
            ],
            if (_places.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _places.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = _places[i];
                    return ActionChip(
                      avatar: Icon(placeIcon(p['icon']?.toString()), size: 18, color: Y.braiseBtn),
                      label: Text(p['label'].toString()),
                      onPressed: () => _book(Place.fromJson(p)),
                    );
                  },
                ),
              ),
            ],
            if (_active.isNotEmpty) ...[
              SectionTitle('En cours', trailing: TextButton(onPressed: widget.onShowRides, child: const Text('Tout voir'))),
              for (final r in _active) ...[
                Panel(
                  border: StatusColors.of(r['status']?.toString()).border,
                  onTap: () async {
                    await RideScreen.open(context, r['reference'].toString());
                    _load();
                  },
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      StatusPill(status: r['status']?.toString(), label: r['status_label'].toString()),
                      const Spacer(),
                      Text(r['fare_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 12),
                    RouteLines(from: r['pickup'].toString(), to: r['dropoff'].toString(), dense: true),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ]),
        ),
      ),
    ]);
  }
}
