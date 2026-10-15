import 'package:flutter/material.dart';
import 'package:pure_live/core/consts/platform_ids.dart';
import 'package:pure_live/core/theme/theme.dart';

/// Each platform's brand colour, so its tag is recognisable at a glance: the
/// recorder's task tags and the room cards' platform tags share it.
abstract final class PlatformColors {
  /// Used by the recorder for a platform without a brand colour.
  static const Color fallback = Color.fromARGB(255, 11, 223, 117);

  /// The brand colour of [platform], or null when it has none.
  static Color? of(String? platform) => switch (platform?.trim().toLowerCase()) {
    PlatformIds.bilibili => const Color(0xFFFB7299),
    PlatformIds.douyu => const Color(0xFFFF7700),
    PlatformIds.huya => const Color(0xFFFFB000),
    PlatformIds.douyin => const Color(0xFF000000),
    PlatformIds.cc => const Color.fromARGB(253, 13, 145, 233),
    PlatformIds.iptv => const Color.fromARGB(255, 204, 71, 9),
    PlatformIds.twitch => const Color(0xFF9146FF),
    PlatformIds.soop => const Color(0xFF0675E8),
    _ => null,
  };

  /// How a tinted platform tag (the room header's, a compact card's) is
  /// drawn on [colors]' page: the brand colour as text, kept readable, over a
  /// faint tint of it. On a dark page a near-black brand (抖音) fills the tag
  /// black with light text instead (lightened to a readable grey it barely
  /// stood out); the text a touch under white, which glared on the black.
  /// Null for a platform without a brand colour.
  static ({Color text, Color fill, Color border})? tintedTag(String? platform, ColorScheme colors) {
    final brand = of(platform);
    if (brand == null) return null;
    if (colors.brightness == Brightness.dark && brand.computeLuminance() < 0.05) {
      return (text: const Color(0xFFDDDDDD), fill: Colors.black, border: Colors.white.withValues(alpha: .3));
    }
    final text = readablePrimary(brand.withValues(alpha: 1), colors.surface);
    return (text: text, fill: text.withValues(alpha: .14), border: text.withValues(alpha: .35));
  }
}
