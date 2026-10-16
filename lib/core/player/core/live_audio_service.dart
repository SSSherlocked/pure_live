import 'dart:io';

import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/player/core/background_playback_policy.dart';
import 'package:pure_live/core/player/core/background_playback_service.dart';

class LiveAudioService {
  LiveAudioService._();

  static bool get shouldContinueInBackground => BackgroundPlaybackPolicy.shouldContinue(
    backgroundPlaybackEnabled: SettingsService.to.app.enableBackgroundPlay.v,
    audioOnlySessionActive: BackgroundPlaybackService.audioOnlySessionActive,
  );

  static Future<void> setPlayer(
    dynamic player, {
    required bool audioOnly,
    int? sessionId,
    bool Function()? isSourceCurrent,
    double Function()? targetVolume,
  }) async {
    if (isSourceCurrent?.call() == false) return;
    BackgroundPlaybackService.audioOnlySessionActive = audioOnly;
    await syncKeepAlive();
  }

  static Future<void> start(String roomId, String title, String author, String? cover) async {
    await syncKeepAlive();
  }

  static Future<void> stop() async {
    await syncKeepAlive();
  }

  /// The background play switch changed. The foreground service and the
  /// locks are taken by the room when the app leaves (its
  /// `BackgroundPlaybackKeeper`); switching off lets go of anything held.
  static Future<void> configureBackgroundPlayback({required bool enabled}) async {
    if (!enabled) await BackgroundPlaybackService.setForegroundHold(false);
  }

  /// Re-applies the locks to the current foreground hold.
  static Future<void> syncKeepAlive() {
    return BackgroundPlaybackService.setKeepAlive(BackgroundPlaybackService.foregroundHeld);
  }

  static Future<bool> requestPlatformPermissions() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.notification.status != PermissionStatus.granted) {
      bool confirm = await _showExplainDialog(
        title: i18n("permission_notification_title"),
        content: i18n("permission_notification_content"),
      );
      if (confirm) await Permission.notification.request();
      if (await Permission.notification.status != PermissionStatus.granted) return false;
    }

    if (await Permission.ignoreBatteryOptimizations.status != PermissionStatus.granted) {
      bool confirm = await _showExplainDialog(
        title: i18n("permission_battery_title"),
        content: i18n("permission_battery_content"),
      );
      if (confirm) await Permission.ignoreBatteryOptimizations.request();
    }
    return true;
  }

  static Future<bool> _showExplainDialog({required String title, required String content}) async {
    bool isConfirm = false;
    await SmartDialog.show(
      builder: (context) => Container(
        width: 300,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppText.of(context).pageTitle.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(content, textAlign: TextAlign.center, style: AppText.of(context).listPrimary),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(onPressed: () => SmartDialog.dismiss(), child: Text(i18n("permission_cancel"))),
                ElevatedButton(
                  onPressed: () {
                    isConfirm = true;
                    SmartDialog.dismiss();
                  },
                  child: Text(i18n("permission_go_enable")),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return isConfirm;
  }
}
