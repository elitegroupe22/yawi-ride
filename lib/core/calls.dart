import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'config.dart';

/// Message Firebase reçu application fermée ou en arrière-plan (Android) :
/// un appel entrant affiche l'écran d'appel du téléphone, même verrouillé.
@pragma('vm:entry-point')
Future<void> yawiBackgroundMessage(RemoteMessage m) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await Calls.handlePush(Map<String, dynamic>.from(m.data));
}

enum CallPhase { idle, connecting, ringing, incoming, talking, ended }

/// Appels audio par internet (LiveKit) : sortants, entrants (écran d'appel du système), en cours.
class Calls extends ChangeNotifier {
  Calls._();
  static final instance = Calls._();

  Api? _api;
  StreamSubscription<CallEvent?>? _events;
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  Timer? _poll;
  Timer? _clock;
  DateTime? _since;

  CallPhase phase = CallPhase.idle;
  String? callId;
  String otherName = '';
  String otherDetail = '';
  String? endReason;
  bool muted = false;
  bool speaker = false;
  Duration elapsed = Duration.zero;
  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;

  /// Ouvre l'écran d'appel (branché par l'application sur le navigateur racine).
  void Function()? onShowCallScreen;

  // ---------- Démarrage ----------

  Future<void> start(Api api) async {
    _api = api;
    _events ??= FlutterCallkitIncoming.onEvent.listen(_onEvent);
    if (defaultTargetPlatform == TargetPlatform.iOS) unawaited(_registerVoip());
    // Application ouverte en décrochant depuis l'écran d'appel : l'évènement a pu partir avant nous.
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      for (final c in active) {
        if (c.isAccepted && !busy) {
          unawaited(_answer(c.id));
          break;
        }
      }
    } catch (_) {}
    unawaited(checkIncoming());
  }

  /// Application ouverte depuis la notification « Appel entrant » (iPhone sans clé VoIP) : afficher l'appel.
  Future<void> checkIncoming() async {
    if (_api == null || busy) return;
    try {
      final c = (await _api!.get('/calls/incoming'))['call'];
      if (c is Map && c['status'] == 'ringing') {
        final other = Map<String, dynamic>.from(c['other'] as Map? ?? {});
        await handlePush({'type': 'call', 'call_id': c['id'], 'caller_name': other['name'], 'caller_detail': other['detail'], 'ring_seconds': '30'});
      }
    } catch (_) {}
  }

  void stop() {
    _events?.cancel();
    _events = null;
    if (busy) hangUp();
    _api = null;
  }

  Future<void> _registerVoip() async {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token != null && token.isNotEmpty && _api != null) {
        await _api!.post('/devices', {'token': token, 'platform': 'ios_voip', 'app_version': AppConfig.version});
      }
    } catch (e) {
      debugPrint('Jeton VoIP non enregistré : $e');
    }
  }

  /// Notification d'appel (premier plan ou arrière-plan).
  static Future<void> handlePush(Map<String, dynamic> d) async {
    final type = d['type']?.toString();
    final id = d['call_id']?.toString();
    if (id == null || id.isEmpty) return;
    if (type == 'call') {
      if (instance.busy && instance.callId != id) return; // déjà en ligne : l'appel sera manqué
      await FlutterCallkitIncoming.showCallkitIncoming(_params(
        id,
        d['caller_name']?.toString() ?? 'Yawi',
        d['caller_detail']?.toString() ?? 'Appel Yawi',
        ring: int.tryParse(d['ring_seconds']?.toString() ?? '') ?? 40,
      ));
    } else if (type == 'call_end') {
      await FlutterCallkitIncoming.endCall(id);
      if (instance.callId == id && instance.phase == CallPhase.incoming) instance._finish('Appel annulé');
    }
  }

  static CallKitParams _params(String id, String name, String detail, {int ring = 40}) => CallKitParams(
        id: id,
        nameCaller: name,
        appName: 'Yawi',
        handle: detail,
        type: 0,
        duration: ring * 1000,
        extra: {'call_id': id},
        missedCallNotification: const NotificationParams(showNotification: true, isShowCallback: false, subtitle: 'Appel manqué'),
        callingNotification: const NotificationParams(showNotification: true, isShowCallback: true, subtitle: 'Appel en cours', callbackText: 'Raccrocher'),
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#1B2735',
          actionColor: '#0F9D63',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Appels entrants',
          missedCallNotificationChannelName: 'Appels manqués',
          isShowCallID: false,
          isShowFullLockedScreen: true,
          isImportant: true,
          textAccept: 'Répondre',
          textDecline: 'Refuser',
        ),
        ios: const IOSParams(
          handleType: 'generic',
          supportsVideo: false,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'voiceChat',
          audioSessionActive: true,
          supportsDTMF: false,
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          includesCallsInRecents: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

  Timer? _ringWatch;

  /// L'appel sonne ici : si l'appelant raccroche, l'écran d'appel du système s'arrête.
  void _watchRinging(String id) {
    _ringWatch?.cancel();
    var tries = 0;
    _ringWatch = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (++tries > 25 || callId == id && busy) return t.cancel();
      try {
        final c = Map<String, dynamic>.from((await _api!.get('/calls/$id'))['call'] as Map);
        if (c['status'] != 'ringing') {
          t.cancel();
          await FlutterCallkitIncoming.endCall(id);
        }
      } catch (_) {}
    });
  }

  void _onEvent(CallEvent? e) {
    switch (e) {
      case CallEventActionCallIncoming(:final callKitParams):
        if (_api != null) _watchRinging(callKitParams.id);
      case CallEventActionCallAccept(:final callKitParams):
        if (callId != callKitParams.id || phase != CallPhase.talking) unawaited(_answer(callKitParams.id));
      case CallEventActionCallDecline(:final callKitParams):
        unawaited(_api?.post('/calls/${callKitParams.id}/hangup').catchError((_) => <String, dynamic>{}));
        if (callId == callKitParams.id) _finish('Appel refusé');
      case CallEventActionCallEnded(:final callKitParams):
        if (callId == callKitParams.id && busy) hangUp();
      case CallEventActionCallToggleMute(:final id, :final isMuted):
        if (callId == id && muted != isMuted) toggleMute();
      case CallEventActionDidUpdateDevicePushTokenVoip():
        unawaited(_registerVoip());
      default:
        break;
    }
  }

  // ---------- Appel sortant ----------

  /// Appelle l'autre partie de la course. Retourne un message d'erreur, ou null.
  Future<String?> callRide(String reference) async {
    final api = _api;
    if (api == null) return 'Connectez-vous pour appeler.';
    if (busy) return 'Un appel est déjà en cours.';
    _reset(CallPhase.connecting);
    onShowCallScreen?.call();
    try {
      final r = await api.post('/calls', {'ride': reference});
      final c = Map<String, dynamic>.from(r['call'] as Map);
      _apply(c);
      await FlutterCallkitIncoming.startCall(_params(callId!, otherName, otherDetail));
      await _join(c['livekit']);
      if (phase == CallPhase.connecting) phase = (_room?.remoteParticipants.isNotEmpty ?? false) ? CallPhase.talking : CallPhase.ringing;
      if (phase == CallPhase.talking) _startClock();
      notifyListeners();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
      return null;
    } on ApiException catch (e) {
      _finish(e.message);
      return e.message;
    } catch (e) {
      _finish('Appel impossible. Vérifiez votre connexion.');
      return 'Appel impossible. Vérifiez votre connexion.';
    }
  }

  // ---------- Appel entrant ----------

  Future<void> _answer(String id) async {
    final api = _api;
    if (api == null) return;
    _reset(CallPhase.connecting);
    callId = id;
    onShowCallScreen?.call();
    try {
      final r = await api.post('/calls/$id/accept');
      final c = Map<String, dynamic>.from(r['call'] as Map);
      _apply(c);
      await _join(c['livekit']);
      await FlutterCallkitIncoming.setCallConnected(id);
      phase = CallPhase.talking;
      _startClock();
      notifyListeners();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    } on ApiException catch (e) {
      await FlutterCallkitIncoming.endCall(id);
      _finish(e.status == 409 ? 'L\'appel est terminé.' : e.message);
    } catch (_) {
      await FlutterCallkitIncoming.endCall(id);
      _finish('Connexion impossible. Vérifiez votre connexion.');
    }
  }

  // ---------- Pendant l'appel ----------

  Future<void> _join(dynamic livekit) async {
    final lkInfo = Map<String, dynamic>.from(livekit as Map);
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(echoCancellation: true, noiseSuppression: true, autoGainControl: true),
      ),
    );
    _room = room;
    _listener = room.createListener()
      ..on<lk.ParticipantConnectedEvent>((_) {
        if (phase == CallPhase.ringing || phase == CallPhase.connecting) {
          phase = CallPhase.talking;
          _startClock();
          if (callId != null) FlutterCallkitIncoming.setCallConnected(callId!);
          notifyListeners();
        }
      })
      ..on<lk.ParticipantDisconnectedEvent>((_) => hangUp(reason: 'Appel terminé'))
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (busy) hangUp(reason: 'Connexion perdue');
      });
    await room.connect(lkInfo['url'].toString(), lkInfo['token'].toString());
    await room.localParticipant?.setMicrophoneEnabled(true);
    await room.setSpeakerOn(speaker);
    WakelockPlus.enable();
  }

  Future<void> _refresh() async {
    final id = callId;
    if (id == null || _api == null) return;
    try {
      final c = Map<String, dynamic>.from((await _api!.get('/calls/$id'))['call'] as Map);
      final s = c['status']?.toString();
      if (s == 'declined') {
        _finish('Appel refusé', notify: true);
      } else if (s == 'missed') {
        _finish('Pas de réponse', notify: true);
      } else if (['ended', 'cancelled', 'failed'].contains(s)) {
        _finish('Appel terminé', notify: true);
      }
    } catch (_) {}
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    if (callId != null) unawaited(FlutterCallkitIncoming.muteCall(callId!, isMuted: muted));
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await _room?.setSpeakerOn(speaker);
    notifyListeners();
  }

  Future<void> hangUp({String reason = 'Appel terminé'}) async {
    final id = callId;
    if (id != null && busy) unawaited(_api?.post('/calls/$id/hangup').catchError((_) => <String, dynamic>{}));
    _finish(reason, notify: true);
  }

  // ---------- Interne ----------

  void _apply(Map<String, dynamic> c) {
    callId = c['id']?.toString();
    final other = Map<String, dynamic>.from(c['other'] as Map? ?? {});
    otherName = other['name']?.toString() ?? '';
    otherDetail = other['detail']?.toString() ?? '';
  }

  void _reset(CallPhase p) {
    _cleanup();
    phase = p;
    endReason = null;
    muted = false;
    speaker = false;
    elapsed = Duration.zero;
    otherName = '';
    otherDetail = '';
    notifyListeners();
  }

  void _startClock() {
    _since = DateTime.now();
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed = DateTime.now().difference(_since!);
      notifyListeners();
    });
  }

  void _finish(String reason, {bool notify = true}) {
    if (phase == CallPhase.ended || phase == CallPhase.idle) {
      if (phase == CallPhase.idle) return;
    }
    final id = callId;
    _cleanup();
    if (id != null) unawaited(FlutterCallkitIncoming.endCall(id).catchError((_) {}));
    phase = CallPhase.ended;
    endReason = reason;
    if (notify) notifyListeners();
  }

  void _cleanup() {
    _poll?.cancel();
    _clock?.cancel();
    _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    room?.disconnect();
    WakelockPlus.disable();
  }

  /// L'écran d'appel se ferme : retour au repos.
  void dismiss() {
    if (!busy) {
      phase = CallPhase.idle;
      callId = null;
      notifyListeners();
    }
  }
}
