import 'dart:async';

import 'package:dio/dio.dart';
import 'package:media_core_media_kit/media_core_media_kit.dart' as mk;
import 'package:pure_live/core/player/core/playback_input_lease.dart';
import 'package:pure_live/core/player/core/playback_source.dart';

typedef OwnedInputRecipe = Future<PlaybackInputLease> Function(CancelToken cancel);

OwnedInputRecipe? asOwnedInputRecipe(Object? recipe) => recipe is OwnedInputRecipe ? recipe : null;

Object customInputMetadataOf(OwnedPlaybackSource source) => source.createInput;

/// The owned-input leases of one kernel player: the one it plays from and
/// the ones still shutting down. An owned lease is a local relay (a loopback
/// HTTP server and its upstream client), so every lease must be closed when
/// the player moves on or goes away, or the relay outlives the room.
class _OwnedLeaseState {
  PlaybackInputLease? active;
  final Set<PlaybackInputLease> retiring = <PlaybackInputLease>{};
  StreamSubscription<mk.PlayerLog>? disposeWatch;
}

final Expando<_OwnedLeaseState> _ownedStates = Expando<_OwnedLeaseState>();

_OwnedLeaseState _stateOf(mk.Player player) {
  final existing = _ownedStates[player];
  if (existing != null) return existing;
  final state = _OwnedLeaseState();
  _ownedStates[player] = state;
  // media_kit closes every player stream when the player is disposed, so the
  // log stream ending is the signal that no open can follow on this player:
  // whatever lease it still holds is closed here.
  state.disposeWatch = player.stream.log.listen(null, onDone: () => unawaited(closeOwnedInputOnKernelPlayer(player)));
  return state;
}

void _retire(_OwnedLeaseState state, PlaybackInputLease lease) {
  if (!state.retiring.add(lease)) return;
  // A relay that fails to shut down is logged by the relay; the player moves on.
  unawaited(lease.close().catchError((Object _) {}).whenComplete(() => state.retiring.remove(lease)));
}

Future<void> openOwnedInputOnKernelPlayer(dynamic player, Object recipe) async {
  final owned = asOwnedInputRecipe(recipe);
  if (owned == null) {
    throw ArgumentError.value(recipe, 'recipe', 'Not an owned-input recipe');
  }
  final mkPlayer = player as mk.Player;
  final state = _stateOf(mkPlayer);
  final previous = state.active;
  state.active = null;
  if (previous != null) _retire(state, previous);

  final lease = await owned(CancelToken());
  // Another open on this player may have landed while the recipe ran; the
  // later open drives the player, so the earlier lease retires instead of
  // being left behind.
  final landed = state.active;
  state.active = lease;
  if (landed != null) _retire(state, landed);
  try {
    await mkPlayer.open(mk.Media(lease.uri.toString()), play: true);
  } catch (error) {
    if (identical(state.active, lease)) {
      state.active = null;
    }
    _retire(state, lease);
    rethrow;
  }
}

/// Closes the owned-input lease [player] plays from, if any, and waits for
/// every retiring lease of that player. Called before the player opens a
/// plain URL and when the player is disposed.
Future<void> closeOwnedInputOnKernelPlayer(dynamic player) async {
  final state = _ownedStates[player as mk.Player];
  if (state == null) return;
  final active = state.active;
  state.active = null;
  if (active != null) _retire(state, active);
  // `close` memoises its future, so awaiting it again joins the shutdown in
  // flight instead of starting a second one.
  await Future.wait<void>([for (final lease in state.retiring.toList()) lease.close().catchError((Object _) {})]);
}
