/// What another domain may ask of the live room's player without depending
/// on the live domain (which installs these when its player starts).
abstract final class LivePlaybackHooks {
  /// Pauses the live room if it is playing. Null until the live player is
  /// up; a page opened without it has nothing to pause.
  static Future<void> Function()? pauseIfPlaying;
}
