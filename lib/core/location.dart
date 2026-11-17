import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Résultat d'une demande de position, avec la raison d'un échec à afficher.
class LocationResult {
  LocationResult(this.point, [this.problem]);
  final LatLng? point;
  final LocationProblem? problem;
}

enum LocationProblem { serviceOff, denied, deniedForever }

class Geo {
  static Future<LocationProblem?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationProblem.serviceOff;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) return LocationProblem.deniedForever;
    if (perm == LocationPermission.denied) return LocationProblem.denied;
    return null;
  }

  static Future<LocationResult> current() async {
    final problem = await ensurePermission();
    if (problem != null) return LocationResult(null, problem);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }
    if (pos == null) return LocationResult(null, LocationProblem.serviceOff);
    return LocationResult(LatLng(pos.latitude, pos.longitude));
  }

  /// Flux de positions pour le chauffeur en ligne (toutes les ~15 m).
  static Stream<Position> stream() => Geolocator.getPositionStream(
        locationSettings: settings(accuracy: LocationAccuracy.high, distanceFilter: 15, interval: const Duration(seconds: 8)),
      );

  /// Réglages GPS adaptés à la plateforme (Android : intervalle ; iOS : mode navigation automobile).
  static LocationSettings settings({required LocationAccuracy accuracy, required int distanceFilter, required Duration interval, bool navigation = false}) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        activityType: navigation ? ActivityType.automotiveNavigation : ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return AndroidSettings(accuracy: accuracy, distanceFilter: distanceFilter, intervalDuration: interval);
  }

  static String explain(LocationProblem p) => switch (p) {
        LocationProblem.serviceOff => 'Activez la localisation (GPS) de votre téléphone.',
        LocationProblem.denied => 'Autorisez la localisation pour que Yawi trouve votre position.',
        LocationProblem.deniedForever => 'La localisation est bloquée. Ouvrez les réglages de l\'application pour l\'autoriser.',
      };

  static Future<void> openSettings(LocationProblem p) =>
      p == LocationProblem.serviceOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings();
}
