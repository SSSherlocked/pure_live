import 'package:flutter/material.dart';
import 'package:pure_live/core/consts/platform_ids.dart';

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
}
