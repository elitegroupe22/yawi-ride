import 'package:dio/dio.dart';

import 'config.dart';

/// Erreur lisible renvoyée par l'API (message du serveur ou message réseau en français).
class ApiException implements Exception {
  ApiException(this.message, {this.status, this.errors = const {}, this.body = const {}});

  final String message;
  final int? status;

  /// Corps de la réponse d'erreur (ex. « reason » et « passenger » d'un scan refusé).
  final Map<String, dynamic> body;

  /// Pas de réponse du serveur (pas de réseau, délai dépassé).
  bool get offline => status == null;
  final Map<String, String> errors;

  bool get unauthorized => status == 401;

  /// Message du champ s'il existe, sinon le message général.
  String field(String name) => errors[name] ?? '';

  @override
  String toString() => message;
}

/// Client HTTP de l'API Yawi (/api/v1), authentifié par jeton Sanctum.
class Api {
  Api() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      headers: {'Accept': 'application/json', 'X-Yawi-App': AppConfig.version},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  late final Dio _dio;
  String? token;

  /// Appelé quand le serveur refuse le jeton (compte désactivé, jeton révoqué…).
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? data]) =>
      _send(() => _dio.post(path, data: data ?? {}));

  Future<Map<String, dynamic>> put(String path, [Map<String, dynamic>? data]) =>
      _send(() => _dio.put(path, data: data ?? {}));

  Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? data]) =>
      _send(() => _dio.delete(path, data: data ?? {}));

  /// Appel d'une adresse absolue renvoyée par le serveur (ex. état d'un paiement).
  Future<Map<String, dynamic>> getUrl(String url) => _send(() => _dio.getUri(Uri.parse(url)));

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is List) return {'data': data};
      return {};
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  ApiException _translate(DioException e) {
    final res = e.response;
    if (res == null) {
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout =>
          'Le serveur met trop de temps à répondre. Vérifiez votre connexion et réessayez.',
        _ => 'Pas de connexion Internet. Vérifiez vos données mobiles ou le Wi-Fi.',
      };
      return ApiException(msg);
    }

    final status = res.statusCode;
    final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final errors = <String, String>{};
    if (body['errors'] is Map) {
      (body['errors'] as Map).forEach((k, v) {
        if (v is List && v.isNotEmpty) errors[k.toString()] = v.first.toString();
      });
    }

    if (status == 401) onUnauthorized?.call();

    String message = (errors.isNotEmpty ? errors.values.first : null) ?? (body['message']?.toString() ?? '');
    if (message.isEmpty || message == 'Server Error') {
      message = switch (status) {
        401 => 'Votre session a expiré. Reconnectez-vous.',
        403 => 'Action non autorisée.',
        404 => 'Élément introuvable.',
        409 => 'Ajoutez votre numéro de téléphone pour continuer.',
        429 => 'Trop de tentatives. Patientez une minute.',
        _ => 'Le service est momentanément indisponible. Réessayez dans un instant.',
      };
    }
    return ApiException(message, status: status, errors: errors, body: body);
  }
}
