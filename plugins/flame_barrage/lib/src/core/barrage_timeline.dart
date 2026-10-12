import '../model/barrage/barrage_item.dart';

/// A recorded stream's comments, dispatched by media time instead of on arrival.
///
/// The live path fires a message the moment the host sends it, which is right
/// for a chat socket and wrong for VOD: there the whole comment list is known
/// up front and each line has to appear at the instant it was originally sent.
/// This class is that mapping — a media position in, the due items out — and
/// holds no Flame, clock or lane knowledge, so the scheduling rule is testable
/// on its own.
///
/// The position fed to [dueBy] is the engine's logic clock, which already
/// advances at `playbackRate`; a video playing at 2× therefore runs its
/// comments at 2× with no extra bookkeeping here.
final class BarrageTimeline {
  /// Creates an empty timeline.
  BarrageTimeline();

  List<BarrageItem> _items = const <BarrageItem>[];
  int _cursor = 0;

  /// Loads [items], keeping the timed ones and ordering them by time.
  ///
  /// Items without [BarrageItem.at] are dropped rather than scheduled at zero:
  /// they belong to the live path, and treating "no time" as "immediately"
  /// would fire an entire list in the first frame after a seek to the start.
  void load(Iterable<BarrageItem> items) {
    final timed = items.where((item) => item.at != null).toList(growable: true)
      ..sort((a, b) => a.at!.compareTo(b.at!));
    _items = timed;
    _cursor = 0;
  }

  /// How many items are still held, loaded ones minus any retracted.
  int get length => _items.length;

  /// Whether nothing is loaded.
  bool get isEmpty => _items.isEmpty;

  /// Whether any item is still ahead of the read position.
  ///
  /// The engine uses this to stay awake: a timeline waiting for its next
  /// moment is pending work even though the dispatch queue is empty, and an
  /// idle-paused clock would never reach that moment.
  bool get hasUpcoming => _cursor < _items.length;

  /// Items not yet released.
  int get remaining => _items.length - _cursor;

  /// The timed items [position] has reached, in time order.
  ///
  /// Releases them: each item is returned once, so calling this every frame
  /// with an advancing position walks the list exactly once.
  List<BarrageItem> dueBy(Duration position) {
    if (!hasUpcoming) {
      return const <BarrageItem>[];
    }
    final due = <BarrageItem>[];
    while (_cursor < _items.length && _items[_cursor].at! <= position) {
      due.add(_items[_cursor]);
      _cursor++;
    }
    return due;
  }

  /// Moves the read position, so everything at or before [position] is past.
  ///
  /// Seeking backwards replays, which is what a viewer dragging the bar back
  /// expects; dropping what is currently on screen is the engine's job, not
  /// this class's.
  void seekTo(Duration position) {
    _cursor = _firstAfter(position);
  }

  /// Drops every **not yet released** item matching [predicate] and returns how
  /// many went — the timeline half of a host-side retraction, so a recalled
  /// comment that has not appeared yet never does.
  ///
  /// Items already released are the dispatch queue's and the screen's business,
  /// and removing them here would report a retraction that changed nothing the
  /// viewer could see.
  int retractWhere(bool Function(BarrageItem item) predicate) {
    if (!hasUpcoming) return 0;

    final kept = <BarrageItem>[];
    var removed = 0;
    for (var i = _cursor; i < _items.length; i++) {
      final item = _items[i];
      if (predicate(item)) {
        removed++;
      } else {
        kept.add(item);
      }
    }
    if (removed == 0) return 0;

    // What is left is exactly the tail that was ahead of the read position,
    // so the cursor restarts at zero and the ordering is still by time.
    _items = kept;
    _cursor = 0;
    return removed;
  }

  /// Empties the timeline and returns the read position to the start.
  void clear() {
    _items = const <BarrageItem>[];
    _cursor = 0;
  }

  int _firstAfter(Duration position) {
    var low = 0;
    var high = _items.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_items[mid].at! <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
