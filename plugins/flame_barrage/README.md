# flame_barrage (Pure Live snapshot)

Source snapshot of [flame_barrage](https://github.com/liuchuancong/flame_barrage)
0.0.9 (MIT), vendored so Pure Live can change how danmaku lanes are chosen.
`pubspec.yaml` points every dependent (the app and media_core_danmaku) here
through `dependency_overrides`.

Changes from upstream:

- `lib/src/scheduler/track_allocator.dart`: lanes fill from the top - a new
  message takes the topmost lane its predecessor has cleared, instead of the
  first empty lane, so a quiet room keeps its danmaku near the top.
