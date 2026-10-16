import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/models/release_model.dart';
import 'package:pure_live/features/about/widgets/release_history_repository.dart';

void main() {
  List<ReleaseModel> releases(List<String> versions) => [
    for (final version in versions) ReleaseModel.fromJson({'version': version, 'date': '2026-10-16'}),
  ];

  test('the copy with the newer newest release wins', () {
    final stale = releases(['3.3.7', '3.3.6', '3.3.5']);
    final fresh = releases(['3.4.2', '3.4.1', '3.4.0', '3.3.8', '3.3.7']);
    expect(compareReleaseLists(fresh, stale), greaterThan(0));
    expect(compareReleaseLists(stale, fresh), lessThan(0));
  });

  test('3.3.10 is newer than 3.3.9', () {
    expect(compareReleaseLists(releases(['3.3.10']), releases(['3.3.9'])), greaterThan(0));
  });

  test('the same newest release: the longer copy wins', () {
    expect(compareReleaseLists(releases(['3.4.2', '3.4.1']), releases(['3.4.2'])), greaterThan(0));
    expect(compareReleaseLists(releases(['3.4.2']), releases(['3.4.2'])), 0);
  });
}
