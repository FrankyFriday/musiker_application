class AppConfig {
  static const String appId = 'musiker_application';
  static const String canonicalServerAppId = 'musiker_app';

  static bool matchesServerAppId(Object? value) =>
      value == appId || value == canonicalServerAppId;
  static const String wsDomain = 'notenserver.mattis-westerhoff.de';
}
