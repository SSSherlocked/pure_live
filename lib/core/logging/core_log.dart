import 'app_log.dart';

/// The shared layer's logger. Every line reaches the app log (the in-app
/// page); `Log` writes it to the file as well while the switch is on.
class CoreLog {
  static void d(String message) => Log.d(message);

  static void i(String message) => Log.i(message);

  static void e(String message, StackTrace stackTrace) => Log.e(message, stackTrace);

  static void error(dynamic e) {
    final StackTrace trace = (e is Error) ? (e.stackTrace ?? StackTrace.current) : StackTrace.current;
    Log.e(e.toString(), trace);
  }

  static void w(String message) => Log.w(message);

  static void logPrint(dynamic obj) => Log.logPrint(obj);
}
