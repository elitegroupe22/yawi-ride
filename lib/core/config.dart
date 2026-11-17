/// Réglages de compilation de l'application.
///
/// L'adresse du serveur peut être changée sans toucher au code :
///   flutter build appbundle --dart-define=YAWI_URL=https://staging.exemple.com
class AppConfig {
  static const String baseUrl = String.fromEnvironment('YAWI_URL', defaultValue: 'https://yawi.elitegroupe-sarl.com');
  static const String version = String.fromEnvironment('YAWI_VERSION', defaultValue: '1.0.0');

  /// Marqueur ajouté au user-agent des pages web ouvertes dans l'application :
  /// le site masque alors ce qui ne concerne que le navigateur (installation, connexion sociale…).
  static const String userAgentMarker = 'YawiApp/$version';

  static String get apiUrl => '$baseUrl/api/v1';
}
