import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:media_core/media_core.dart';
import 'package:pure_live/core/player/kernel/player_consts.dart';
import 'package:pure_live/core/player/presentation/fullscreen_window.dart';
import 'package:pure_live/core/player/presentation/kernel_floating_window_presenter.dart';
import 'package:pure_live/domains/live/domain/global_player_service.dart';
import 'package:media_core_floating/media_core_floating.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart' hide PlayerConsts;
import 'package:pure_live/core/player/presentation/windows_pip_driver.dart';
import 'package:pure_live/core/player/kernel/owned_input_opener.dart';
import 'package:pure_live/core/player/kernel/mpv_log_forwarder.dart';
import 'package:media_core_ijk_player/media_core_ijk_player.dart';
import 'package:media_core_logging/media_core_logging.dart' as mlog;
import 'package:media_core_mediasession/media_core_mediasession.dart';
import 'package:pure_live/core/player/kernel/media_kit_live_properties.dart';
import 'package:pure_live/core/player/kernel/open_volume.dart';
import 'package:media_core_better_player/media_core_better_player.dart';
import 'package:pure_live/core/config/player_settings_controller.dart';

class PlayerKernelService {
  PlayerKernelService._();

  static final PlayerKernelService instance = PlayerKernelService._();

  static final FloatingDriver floatingDriver = FloatingDriver();

  static mlog.MemoryLogSink? logRing;

  PlayerKernel? _kernel;

  PlayerKernel get kernel {
    _kernel ??= _buildKernel();
    return _kernel!;
  }

  PlayerKernel _buildKernel() {
    final kernel = PlayerKernel()
      ..registerBackend(
        MediaKitAdapterFactory(
          playerConfiguration: MediaKitLiveProperties.playerConfiguration(),
          customInputOpener: openOwnedInputOnKernelPlayer,
          beforeOpen: (player, source) async {
            attachMpvLogForwarder(player);
            // A plain URL replaces an owned input (a local relay) on the same
            // player; nothing else would close that relay. An owned source
            // closes its predecessor itself in the opener.
            if (source.metadata[kMediaKitCustomInputKey] == null) {
              await closeOwnedInputOnKernelPlayer(player);
            }
            final initialVolume = OpenVolume.resolve(source);
            if (initialVolume != null) {
              try {
                await player.setVolume(initialVolume * 100.0);
              } catch (_) {}
            }
            await MediaKitLiveProperties.applyToSource(player, source);
          },
          videoControllerConfigurationBuilder: MediaKitLiveProperties.buildVideoControllerConfiguration,
          // The app declares every tuning value it wants; the adapter applies
          // only what it is told.
          configure: MediaKitLiveProperties.applyTo,
        ).registration(),
      );

    if (PlayerConsts.mobileOnlyEnginesAvailable(defaultTargetPlatform)) {
      kernel
        ..registerBackend(
          const FlvLzcPlayerAdapterFactory(
            // ijkplayer otherwise sits on the resolver's first address (an
            // IPv6 one on most phones) for the whole open timeout; on a
            // network where IPv6 to a CDN is black-holed every FLV line
            // burned the kernel's 10 s window. Try the addresses one at a
            // time with a short budget so IPv4 gets its turn in time.
            options: <EngineOption>[
              EngineOption('addrinfo_one_by_one', 1, domain: 'format'),
              EngineOption('addrinfo_timeout', 2000000, domain: 'format'),
              EngineOption('open_timeout', 3000000, domain: 'format'),
            ],
          ).registration(),
        )
        ..registerBackend(const BetterPlayerAdapterFactory().registration());
    }

    kernel.attachPresentation(
      PresentationDriverChain(
        bindings: [
          PresentationDriverBinding(
            modes: {PresentationMode.fullscreen, PresentationMode.windowFullscreen},
            driver: fullscreenDriver,
          ),
          PresentationDriverBinding(modes: {PresentationMode.pip}, driver: windowsPipDriver),
          PresentationDriverBinding(modes: {PresentationMode.floating}, driver: floatingDriver),
        ],
      ),
    );
    // The driver ships with a null presenter, so a `floating` request was
    // silently dropped. Install the host surface so any host that calls
    // kernel.enterFloating (the local video player) actually opens a window for
    // that handle.
    floatingDriver.updatePresenter(KernelFloatingWindowPresenter(kernel: kernel, driver: floatingDriver));
    return kernel;
  }

  static Future<void> ensureInitialized() async {
    MediaKitPlayerAdapter.ensureInitialized();

    // The desktop chrome asks the window, not a player, whether the picture is
    // compact, and the driver is what makes it compact. Start mirroring it
    // before any player can ask for the mode.
    observeWindowsPipState();

    // Output settings ride two rails: mpv-property changes (hwdec, tuning
    // table, shaders, ao, ...) apply to the live engine through engine
    // options; a render-context change (vo / custom-output switch) needs a
    // same-backend engine rebuild, which preserves source, position and
    // play intent.
    PlayerSettingsController.outputSettingsDispatcher = ({required bool rebuild}) {
      final player = GlobalPlayerService.instance.player;
      // Between rooms the warm engine still knows the room left: a rebuild
      // or an option that reloads would play it again behind the home page.
      // Let the engine go; the next room opens one with these settings.
      if (!player.isServingRoom) {
        unawaited(player.releaseIdleEngine());
        return;
      }
      final handle = player.handle;
      if (handle == null) return;
      if (rebuild) {
        unawaited(handle.rebuildEngine(reason: 'video output settings changed'));
        return;
      }
      unawaited(MediaKitLiveProperties.engineOptions().then((options) => handle.applyEngineOptions(options)));
    };
    // The rest of the mpv settings are read when an engine is created and
    // are not applied to a running one: the room on screen keeps playing as
    // it is. Its engine is not kept warm for the next room (that one would
    // still run on the old settings); between rooms the warm engine goes now.
    PlayerSettingsController.engineSettingsDispatcher = () {
      final player = GlobalPlayerService.instance.player;
      if (player.isServingRoom) {
        player.retireEngineOnClose();
      } else {
        unawaited(player.releaseIdleEngine());
      }
    };
    logRing = mlog.MediaCoreLog.attachMemorySink(capacity: 500);
    // The ring feeds the app log (LogController pumps it); a release build
    // keeps the kernel's info lines (engine, source and candidate changes),
    // which is what a stalled start needs to be explained.
    mlog.MediaCoreLog.level = const bool.fromEnvironment('dart.vm.product') ? mlog.LogLevel.info : mlog.LogLevel.debug;
    // Exiting the app (swiping it away) ends the media service with it: no
    // playback carrying on, no notification left behind, no media button
    // bringing a closed app back.
    await MediaSessionBootstrap.attachTo(
      instance.kernel,
      config: const MediaSessionConfig.video(androidStopOnRemoveTask: true, androidResumeOnClick: false),
    );
  }
}
