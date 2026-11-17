import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

enum SessionState { loading, guest, passenger, driver }

/// État global : jeton, utilisateur connecté et configuration publique (services, paiement…).
class Session extends ChangeNotifier {
  Session(this.api) {
    api.onUnauthorized = () {
      if (state != SessionState.guest && state != SessionState.loading) _clear();
    };
  }

  final Api api;
  static String get _deviceName => defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android';

  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _tokenKey = 'yawi.token';

  SessionState state = SessionState.loading;
  Map<String, dynamic> user = {};
  Map<String, dynamic> config = {};
  String? bootError;

  /// Appelés après connexion / avant déconnexion (enregistrement de l'appareil pour les notifications).
  Future<void> Function()? onSignedIn;
  Future<void> Function()? onSigningOut;

  bool get isDriver => user['role'] == 'driver';
  Map<String, dynamic> get driver => Map<String, dynamic>.from(user['driver'] as Map? ?? {});
  bool get driverApproved => driver['approved'] == true;
  String get firstName => (user['name']?.toString() ?? '').split(' ').first;

  List<Map<String, dynamic>> get services =>
      ((config['services'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  Map<String, dynamic> get payments => Map<String, dynamic>.from(config['payments'] as Map? ?? {});
  Map<String, dynamic> get contact => Map<String, dynamic>.from(config['contact'] as Map? ?? {});

  Future<void> boot() async {
    state = SessionState.loading;
    bootError = null;
    notifyListeners();
    try {
      config = await api.get('/config');
    } on ApiException catch (e) {
      bootError = e.message;
      notifyListeners();
      return;
    }

    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      state = SessionState.guest;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      final res = await api.get('/me');
      _setUser(res['user']);
      await onSignedIn?.call();
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await _clear();
      } else {
        bootError = e.message;
        notifyListeners();
      }
    }
  }

  Future<void> login(String login, String password) async {
    final res = await api.post('/auth/login', {'login': login, 'password': password, 'device_name': _deviceName});
    await _signedIn(res);
  }

  Future<void> register(Map<String, dynamic> data) async {
    final res = await api.post('/auth/register', {...data, 'device_name': _deviceName});
    await _signedIn(res);
  }

  Future<void> refresh() async {
    final res = await api.get('/me');
    _setUser(res['user']);
  }

  void updateUser(dynamic payload) => _setUser(payload);

  /// Lien à usage unique ouvrant une page du site déjà connectée (dossier chauffeur, support…).
  Future<String> webLink(String path) async {
    final res = await api.post('/auth/web-link', {'path': path});
    return res['url'] as String;
  }

  Future<void> logout() async {
    try {
      await onSigningOut?.call();
      await api.post('/auth/logout');
    } catch (_) {}
    await _clear();
  }

  /// Après suppression du compte : le serveur a déjà révoqué les jetons.
  Future<void> forget() => _clear();

  Future<void> _signedIn(Map<String, dynamic> res) async {
    api.token = res['token'] as String;
    await _storage.write(key: _tokenKey, value: api.token);
    _setUser(res['user']);
    await onSignedIn?.call();
  }

  void _setUser(dynamic payload) {
    user = Map<String, dynamic>.from(payload as Map);
    state = user['role'] == 'driver' ? SessionState.driver : SessionState.passenger;
    notifyListeners();
  }

  Future<void> _clear() async {
    api.token = null;
    user = {};
    await _storage.delete(key: _tokenKey);
    state = SessionState.guest;
    notifyListeners();
  }
}
