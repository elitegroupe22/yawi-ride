import 'dart:async';
import 'dart:ui' show Color;

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'config.dart';

/// Sonnerie des nouvelles demandes (chauffeur) et des relances.
/// Lue sur le flux « alarme / notification » : audible même quand le média est coupé.
class Sonnerie {
  Sonnerie._();
  static final instance = Sonnerie._();

  final AudioPlayer _ring = AudioPlayer(playerId: 'yawi-sonnerie');
  final AudioPlayer _beep = AudioPlayer(playerId: 'yawi-bip');
  bool _ringing = false;
  Timer? _vibe;

  Future<void> init() async {
    final ctx = AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        stayAwake: true,
      ),
      // iOS : catégorie « lecture » pour être audible même avec le bouton silencieux.
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    );
    await AudioPlayer.global.setAudioContext(ctx);
    await _ring.setReleaseMode(ReleaseMode.loop);
  }

  bool get ringing => _ringing;

  Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    try {
      await _ring.play(AssetSource('sounds/sonnerie.wav'), volume: 1);
    } catch (_) {}
    HapticFeedback.heavyImpact();
    _vibe = Timer.periodic(const Duration(milliseconds: 1300), (_) => HapticFeedback.heavyImpact());
  }

  Future<void> stop() async {
    _ringing = false;
    _vibe?.cancel();
    try {
      await _ring.stop();
    } catch (_) {}
  }

  Future<void> beep() async {
    try {
      await _beep.play(AssetSource('sounds/bip.wav'));
    } catch (_) {}
    HapticFeedback.mediumImpact();
  }
}

/// Notifications : Firebase Cloud Messaging (serveur) + affichage local quand l'app est ouverte.
class Alerts {
  Alerts._();
  static final instance = Alerts._();

  final _local = FlutterLocalNotificationsPlugin();
  bool firebaseReady = false;
  String? _token;
  Api? _api;

  /// Adresse (chemin du site) d'une notification touchée : l'application ouvre l'écran correspondant.
  final opened = StreamController<String>.broadcast();

  /// Message reçu application ouverte (pour rafraîchir l'écran courant sans attendre).
  final received = StreamController<Map<String, dynamic>>.broadcast();

  static const _alertes = AndroidNotificationChannel(
    'alertes', 'Courses et alertes',
    description: 'Nouvelles demandes, arrivée du chauffeur, relances.',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('sonnerie'),
    enableVibration: true,
  );
  // Le son d'un canal Android ne peut plus changer après sa création : nouvel identifiant pour le son Yawi.
  static const _infos = AndroidNotificationChannel(
    'infos_yawi', 'Informations',
    description: 'Paiements, reçus et informations de compte.',
    importance: Importance.defaultImportance,
    sound: RawResourceAndroidNotificationSound('bip'),
  );

  Future<void> init() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_yawi'),
        // iOS : les autorisations sont demandées à la connexion (register), pas au lancement.
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null && r.payload!.isNotEmpty) opened.add(r.payload!);
      },
    );
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_alertes);
    await android?.createNotificationChannel(_infos);
    await android?.deleteNotificationChannel('infos'); // ancien canal, au son du téléphone

    try {
      await Firebase.initializeApp();
      firebaseReady = true;
    } catch (e) {
      // Sans google-services.json, l'application fonctionne sans notifications push (suivi par actualisation).
      debugPrint('Firebase indisponible : $e');
      return;
    }

    FirebaseMessaging.onMessage.listen((m) {
      final data = Map<String, dynamic>.from(m.data);
      received.add(data);
      final n = m.notification;
      if (n != null) show(n.title ?? 'Yawi', n.body ?? '', url: data['url']?.toString(), urgent: _isIOS ? m.notification?.apple?.sound?.name != 'bip.wav' : m.notification?.android?.channelId != _infos.id);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final url = m.data['url']?.toString();
      if (url != null) opened.add(url);
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final url = initial?.data['url']?.toString();
    if (url != null) Future.delayed(const Duration(milliseconds: 800), () => opened.add(url));

    FirebaseMessaging.instance.onTokenRefresh.listen((t) {
      _token = t;
      if (_api?.token != null) _send(t);
    });
  }

  /// Demande l'autorisation (Android 13+) puis enregistre l'appareil auprès du serveur.
  Future<void> register(Api api) async {
    _api = api;
    final android = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    final ios = _local.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
    if (!firebaseReady) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      if (_isIOS) {
        // Sur iOS, le jeton Firebase n'existe qu'une fois le jeton APNs reçu d'Apple.
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns == null) await Future.delayed(const Duration(milliseconds: 600));
        }
        if (apns == null) return; // onTokenRefresh prendra le relais
      }
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await _send(_token!);
    } catch (e) {
      debugPrint('Enregistrement push impossible : $e');
    }
  }

  Future<void> unregister() async {
    if (_token == null || _api == null) return;
    try {
      await _api!.delete('/devices', {'token': _token});
    } catch (_) {}
  }

  Future<void> _send(String token) =>
      _api!.post('/devices', {'token': token, 'platform': _isIOS ? 'ios' : 'android', 'app_version': AppConfig.version}).catchError((_) => <String, dynamic>{});

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> show(String title, String body, {String? url, bool urgent = true}) async {
    final channel = urgent ? _alertes : _infos;
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id, channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          playSound: true,
          sound: channel.sound, // Android 7 et moins : le son est porté par la notification
          priority: urgent ? Priority.max : Priority.defaultPriority,
          icon: '@drawable/ic_stat_yawi',
          color: const Color(0xFFF94304),
          category: urgent ? AndroidNotificationCategory.call : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          sound: urgent ? 'sonnerie.wav' : 'bip.wav', // fichiers ajoutés au bundle iOS (tool/ios)
          interruptionLevel: urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        ),
      ),
      payload: url,
    );
  }
}
