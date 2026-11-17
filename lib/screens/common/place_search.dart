import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/location.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../../widgets/yawi_map.dart';

/// Lieu choisi : libellé court, adresse et coordonnées.
class Place {
  const Place({required this.label, required this.address, required this.lat, required this.lng});
  final String label;
  final String address;
  final double lat;
  final double lng;

  LatLng get point => LatLng(lat, lng);

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        label: (j['label'] ?? j['address'] ?? '').toString(),
        address: (j['address'] ?? j['label'] ?? '').toString(),
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
      );

  static Future<Place?> fromPosition(Api api, LatLng p) async {
    try {
      final res = await api.get('/geo/reverse', query: {'lat': p.latitude, 'lng': p.longitude});
      final address = res['address']?.toString() ?? 'Position actuelle';
      return Place(label: address.split(',').first, address: address, lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return Place(label: 'Position actuelle', address: 'Position actuelle', lat: p.latitude, lng: p.longitude);
    }
  }
}

IconData placeIcon(String? icon) => switch (icon) {
      'plane' => Icons.flight_takeoff,
      'bag' => Icons.shopping_bag_outlined,
      'clock' => Icons.history,
      'home' => Icons.home_outlined,
      'work' => Icons.work_outline,
      _ => Icons.place_outlined,
    };

/// Recherche d'adresse (lieux rapides, Nominatim), position actuelle ou choix sur la carte.
class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key, required this.title, this.suggestions = const []});
  final String title;
  final List<Map<String, dynamic>> suggestions;

  static Future<Place?> pick(BuildContext context, {required String title, List<Map<String, dynamic>> suggestions = const []}) =>
      Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => PlaceSearchScreen(title: title, suggestions: suggestions)));

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _locating = false;
  String? _error;

  List<Map<String, dynamic>> get _quick {
    final cfg = ((context.read<Session>().config['quick_places'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map));
    final seen = <String>{};
    return [...widget.suggestions, ...cfg].where((p) => seen.add(p['address'].toString())).toList();
  }

  void _changed(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final res = await context.read<Session>().api.get('/geo/search', query: {'q': q});
      if (!mounted || _q.text.trim() != q) return;
      setState(() {
        _results = ((res['results'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = _results.isEmpty ? 'Aucune adresse trouvée. Essayez un quartier ou un repère connu, ou choisissez sur la carte.' : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _here() async {
    setState(() => _locating = true);
    final api = context.read<Session>().api;
    final r = await Geo.current();
    if (!mounted) return;
    if (r.point == null) {
      setState(() => _locating = false);
      toast(context, Geo.explain(r.problem!), error: true);
      return;
    }
    final place = await Place.fromPosition(api, r.point!);
    if (mounted) Navigator.of(context).pop(place);
  }

  Future<void> _onMap() async {
    final place = await Navigator.of(context).push<Place>(MaterialPageRoute(builder: (_) => const MapPickerScreen()));
    if (place != null && mounted) Navigator.of(context).pop(place);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _q.text.trim().length >= 2 ? _results : _quick;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: _changed,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Quartier, rue, repère…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _loading
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : (_q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _q.clear(); _results = []; }))),
            ),
          ),
        ),
        Expanded(
          child: ListView(children: [
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFFE5EEFF), child: Icon(Icons.my_location, color: Color(0xFF1D4FB8))),
              title: const Text('Ma position actuelle', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: _locating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _locating ? null : _here,
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Y.brume, child: Icon(Icons.map_outlined, color: Y.nuit)),
              title: const Text('Choisir sur la carte', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: _onMap,
            ),
            const Divider(height: 24),
            if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), child: Text(_error!, style: const TextStyle(color: Y.ardoise))),
            for (final p in list)
              ListTile(
                leading: CircleAvatar(backgroundColor: Y.braiseVoile, child: Icon(placeIcon(p['icon']?.toString()), color: Y.braiseBtn, size: 20)),
                title: Text(p['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p['address'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.of(context).pop(Place.fromJson(p)),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Choix d'un point en déplaçant la carte sous un repère fixe.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.start});
  final LatLng? start;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  late LatLng _center;
  String _address = 'Déplacez la carte pour placer le repère';
  Timer? _debounce;
  bool _resolving = false;
  Place? _place;

  @override
  void initState() {
    super.initState();
    final c = context.read<Session>().config['map']?['center'] as List?;
    _center = widget.start ?? (c != null ? LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()) : const LatLng(9.537, -13.6773));
    _resolve();
    if (widget.start == null) {
      Geo.current().then((r) {
        if (r.point != null && mounted) {
          _map.move(r.point!, 16);
          _moved(r.point!);
        }
      });
    }
  }

  void _moved(LatLng c) {
    _center = c;
    _debounce?.cancel();
    setState(() => _resolving = true);
    _debounce = Timer(const Duration(milliseconds: 600), _resolve);
  }

  Future<void> _resolve() async {
    final place = await Place.fromPosition(context.read<Session>().api, _center);
    if (!mounted) return;
    setState(() {
      _place = place;
      _address = place?.address ?? _address;
      _resolving = false;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choisir sur la carte')),
      body: Stack(children: [
        YawiMap(controller: _map, center: _center, zoom: 16, onMoved: _moved),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on, color: Y.braise, size: 48, shadows: [Shadow(color: Color(0x551B2735), blurRadius: 10)]),
            ),
          ),
        ),
        Positioned(
          left: 16, right: 16, bottom: 16,
          child: SafeArea(
            child: Panel(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const Icon(Icons.place, color: Y.braiseBtn),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_resolving ? 'Recherche de l\'adresse…' : _address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _resolving || _place == null ? null : () => Navigator.of(context).pop(_place),
                  child: const Text('Valider ce point'),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
