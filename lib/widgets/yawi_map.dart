import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/theme.dart';

/// Repère affiché sur la carte.
class Pin {
  const Pin(this.point, this.kind, {this.label});
  final LatLng point;
  final PinKind kind;
  final String? label;
}

enum PinKind { me, pickup, dropoff, driver, nearby }

/// Carte OpenStreetMap (mêmes tuiles que le site), centrée sur Conakry par défaut.
class YawiMap extends StatelessWidget {
  const YawiMap({
    super.key,
    this.controller,
    this.center = const LatLng(9.5370, -13.6773),
    this.zoom = 13,
    this.pins = const [],
    this.route = const [],
    this.onMoved,
    this.interactive = true,
    this.bottomInset = 0,
  });

  final MapController? controller;
  final LatLng center;
  final double zoom;
  final List<Pin> pins;
  final List<LatLng> route;
  final void Function(LatLng center)? onMoved;
  final bool interactive;
  final double bottomInset;

  /// Cadre la carte sur les repères donnés en tenant compte du panneau du bas.
  static void fit(MapController c, List<LatLng> points, {double bottom = 300}) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      c.move(points.first, 15.5);
      return;
    }
    c.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: EdgeInsets.fromLTRB(56, 110, 56, bottom + 40),
      maxZoom: 16,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 5,
        maxZoom: 19,
        backgroundColor: const Color(0xFFE8ECF1),
        interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
        onPositionChanged: onMoved == null ? null : (camera, hasGesture) {
          if (hasGesture) onMoved!(camera.center);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'gn.yawi.app',
          maxNativeZoom: 19,
        ),
        if (route.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: route, strokeWidth: 7, color: Colors.white),
            Polyline(points: route, strokeWidth: 4.5, color: Y.nuit),
          ]),
        MarkerLayer(markers: pins.map(_marker).toList()),
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Y.ardoise)),
          ),
        ),
      ],
    );
  }

  Marker _marker(Pin p) {
    switch (p.kind) {
      case PinKind.me:
        return Marker(
          point: p.point, width: 26, height: 26,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2F6FDB), shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x552F6FDB), blurRadius: 12, spreadRadius: 4)],
            ),
          ),
        );
      case PinKind.pickup:
        return Marker(point: p.point, width: 22, height: 22, child: _dot(Y.feuille));
      case PinKind.dropoff:
        return Marker(
          point: p.point, width: 40, height: 48, alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on, color: Y.braise, size: 44, shadows: [Shadow(color: Color(0x551B2735), blurRadius: 8)]),
        );
      case PinKind.driver:
        return Marker(
          point: p.point, width: 44, height: 44,
          child: Container(
            decoration: BoxDecoration(color: Y.nuit, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: Y.ombre),
            child: const Icon(Icons.local_taxi, color: Y.braiseClair, size: 22),
          ),
        );
      case PinKind.nearby:
        return Marker(
          point: p.point, width: 28, height: 28,
          child: Container(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: Y.ombre),
            child: const Icon(Icons.local_taxi, color: Y.nuit, size: 16),
          ),
        );
    }
  }

  Widget _dot(Color c) => Container(
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), boxShadow: Y.ombre),
      );
}
