import 'dart:async';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/core/storage/hive_rx.dart';
import 'package:pure_live/core/layout/app_layout.dart';
import 'package:pure_live/core/storage/hive_pref_util.dart';

/// One setting kept once per [DisplayProfile]: its key inside a profile's
/// JSON map and how a stored or backed-up value is read back.
///
/// [read] answers null for a value it cannot use (missing, wrong type, not
/// finite); [decode] then falls back to the legacy value and finally to
/// [fallback]. Every value that comes out is bounded like the setting itself.
class ProfiledSpec<T> {
  ProfiledSpec(this.key, {required this.fallback, required this.read, Object? Function(T value)? write})
    : _write = write;

  final String key;
  final T fallback;
  final T? Function(Object? raw) read;
  final Object? Function(T value)? _write;

  T decode(Object? raw, [Object? legacy]) => read(raw) ?? read(legacy) ?? fallback;

  /// The JSON form of [value] (the value itself for numbers, flags and text).
  Object? encode(T value) {
    final write = _write;
    return write == null ? value : write(value);
  }

  /// [raw] (or else [legacy], or else [fallback]) bounded and in JSON form.
  Object? normalize(Object? raw, [Object? legacy]) => encode(decode(raw, legacy));

  ProfiledField<T> bind(Rx<T> rx) => ProfiledField<T>(this, rx);

  /// Reads a finite number, clamped to [min]..[max] and then passed through
  /// [normalize] (snapping to a grid, for instance).
  static double? Function(Object?) number({
    required double min,
    required double max,
    double Function(double value)? normalize,
  }) {
    return (raw) {
      if (raw is! num || !raw.isFinite) return null;
      final value = raw.toDouble().clamp(min, max).toDouble();
      return normalize == null ? value : normalize(value);
    };
  }

  /// Reads a finite number as an int through [normalize].
  static int? Function(Object?) integer(int Function(num value) normalize) {
    return (raw) => raw is num && raw.isFinite ? normalize(raw) : null;
  }

  static bool? flag(Object? raw) => raw is bool ? raw : null;

  /// Reads a string through [normalize].
  static String? Function(Object?) text(String Function(String value) normalize) {
    return (raw) => raw is String ? normalize(raw) : null;
  }
}

/// A [ProfiledSpec] bound to the observable the app reads.
class ProfiledField<T> {
  ProfiledField(this.spec, this.rx);

  final ProfiledSpec<T> spec;
  final Rx<T> rx;

  /// The observable's value, bounded and in JSON form.
  Object? snapshot() => spec.normalize(spec.encode(rx.value));

  void apply(Object? raw) => rx.v = spec.decode(raw);
}

/// Settings that are kept once per [DisplayProfile] (phone, tablet, desktop).
///
/// The bound observables keep being what the app reads and edits: they always
/// hold the active profile's values. Each profile is one JSON map in Hive
/// (`<prefix>_phone`, `<prefix>_tablet`, `<prefix>_desktop`); an edit lands in
/// the active profile's map, and [use] saves the active map and loads another
/// one without touching the rest. A profile missing from Hive (the first run
/// of this version) starts from the seed the owner passes to [init], else from
/// the observables' current values (the single setting used so far), and is
/// written right away, so a later launch never seeds it again from values that
/// by then mirror another profile.
class ProfiledSettings {
  ProfiledSettings(this.prefix, this.fields);

  /// Device-local Hive key of the profile last applied, which settings start
  /// from on the next launch before the app shell resolves the layout. Not
  /// part of a backup: it describes this device's screen.
  static const String lastProfileKey = 'displayProfile';

  /// The profile last applied on this device, or the phone one.
  static DisplayProfile get lastProfile =>
      DisplayProfile.tryParse(HivePrefUtil.getString(lastProfileKey)) ?? DisplayProfile.phone;

  final String prefix;
  final List<ProfiledField> fields;

  /// The profile the observables hold.
  final Rx<DisplayProfile> profile = Rx<DisplayProfile>(DisplayProfile.phone);

  final Map<DisplayProfile, Map<String, dynamic>> _maps = {};
  final Map<DisplayProfile, String> _persisted = {};
  Worker? _worker;

  List<ProfiledSpec> get specs => [for (final field in fields) field.spec];

  String storageKey(DisplayProfile profile) => '${prefix}_${profile.name}';

  /// The bounded map of [specs] read from [raw]; a value missing there comes
  /// from [legacy] (same keys), else from the spec's fallback.
  static Map<String, dynamic> normalizeMap(List<ProfiledSpec> specs, Object? raw, [Object? legacy]) {
    final source = raw is Map ? raw : const <String, dynamic>{};
    final old = legacy is Map ? legacy : const <String, dynamic>{};
    return {for (final spec in specs) spec.key: spec.normalize(source[spec.key], old[spec.key])};
  }

  /// Loads (or seeds) the three profiles and makes the observables hold
  /// [initial] (default: [lastProfile]). Call once, after the owner has
  /// bounded the observables' stored values.
  void init({Map<String, dynamic>? Function(DisplayProfile profile)? seed, DisplayProfile? initial}) {
    final current = snapshot();
    for (final profile in DisplayProfile.values) {
      final stored = _readStored(profile);
      if (stored != null) {
        _maps[profile] = normalizeMap(specs, stored, current);
        _persisted[profile] = HivePrefUtil.getString(storageKey(profile)) ?? '';
      } else {
        _maps[profile] = normalizeMap(specs, seed?.call(profile) ?? current, current);
      }
      _store(profile);
    }
    profile.value = initial ?? lastProfile;
    _applyMap(_maps[profile.value]!);
    _worker?.dispose();
    _worker = everAll([for (final field in fields) field.rx], (_) => capture());
  }

  Map<String, dynamic>? _readStored(DisplayProfile profile) {
    final stored = HivePrefUtil.getString(storageKey(profile));
    if (stored == null || stored.isEmpty) return null;
    try {
      final decoded = jsonDecode(stored);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// The observables' values, bounded and in JSON form.
  Map<String, dynamic> snapshot() => {for (final field in fields) field.spec.key: field.snapshot()};

  /// A copy of [profile]'s map; the active one is read from the observables
  /// so an edit not yet captured is included.
  Map<String, dynamic> mapFor(DisplayProfile profile) =>
      profile == this.profile.value ? snapshot() : Map<String, dynamic>.from(_maps[profile] ?? snapshot());

  /// Writes the observables into the active profile's map. Reads them rather
  /// than a worker's event value, so a notification that arrives after a
  /// switch never carries one profile's values into another.
  void capture() {
    _maps[profile.value] = snapshot();
    _store(profile.value);
  }

  void _store(DisplayProfile profile) {
    final map = _maps[profile];
    if (map == null) return;
    final encoded = jsonEncode(map);
    if (_persisted[profile] == encoded) return;
    _persisted[profile] = encoded;
    unawaited(HivePrefUtil.setString(storageKey(profile), encoded));
  }

  void _applyMap(Map<String, dynamic> map) {
    for (final field in fields) {
      field.apply(map[field.spec.key]);
    }
  }

  /// Makes the observables hold [next]'s values. Edits still pending for the
  /// profile being left are saved into it first; the others stay untouched.
  /// Returns whether the profile changed.
  bool use(DisplayProfile next) {
    if (next == profile.value) return false;
    capture();
    profile.value = next;
    _applyMap(_maps[next]!);
    return true;
  }

  /// All three maps keyed by profile name, for a backup.
  Map<String, dynamic> export() => {for (final profile in DisplayProfile.values) profile.name: mapFor(profile)};

  /// Reads the backup form written by [export]. A profile missing from [raw]
  /// (an older backup) takes its values from [legacy] — the backup's single
  /// values for that profile, under the same keys — else the defaults.
  static Map<String, dynamic> parse(
    List<ProfiledSpec> specs,
    Object? raw, {
    Map<String, dynamic>? Function(DisplayProfile profile)? legacy,
  }) {
    final source = raw is Map ? raw : const <String, dynamic>{};
    return {
      for (final profile in DisplayProfile.values)
        profile.name: normalizeMap(specs, source[profile.name], legacy?.call(profile)),
    };
  }

  /// Replaces all three profiles with the output of [parse] and loads the
  /// active one into the observables.
  void restore(Map<String, dynamic> parsed) {
    for (final profile in DisplayProfile.values) {
      _maps[profile] = normalizeMap(specs, parsed[profile.name]);
      _store(profile);
    }
    _applyMap(_maps[profile.value]!);
  }

  void dispose() {
    _worker?.dispose();
    _worker = null;
  }
}
