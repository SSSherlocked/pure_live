/// Generated file. Do not edit.
///
/// To regenerate, run: `dart run enven`
class AppConfig {
  /// Override this instance to mock the environment.
  /// Example: `AppConfig.instance = MockAppConfigData();`
  static AppConfigData instance = AppConfigData();

  static String get pureliveUpdateOwner => instance.pureliveUpdateOwner;
  static String get pureliveUpdateRepository => instance.pureliveUpdateRepository;
  static String get pureliveNativeOwner => instance.pureliveNativeOwner;
  static String get pureliveNativeRepository => instance.pureliveNativeRepository;
}

class AppConfigData {
  final String pureliveUpdateOwner = 'SSSherlocked';

  final String pureliveUpdateRepository = 'pure_live';

  final String pureliveNativeOwner = 'SSSherlocked';

  final String pureliveNativeRepository = 'pure_live';
}
