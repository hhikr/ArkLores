/// Half-open line intervals shared by execution and call deduplication.
const storyReadRangesError =
    'ranges 应为最多四段 [[start, count], ...]，start 为非负整数，count 为正整数。';

bool validStoryReadRanges(Object? value) =>
    value is List &&
    value.isNotEmpty &&
    value.length <= 4 &&
    value.every((Object? r) =>
        r is List &&
        r.length == 2 &&
        r[0] is int &&
        r[1] is int &&
        (r[0] as int) >= 0 &&
        (r[1] as int) > 0,);

List<(int, int)> storyReadRanges(List<dynamic> value) {
  final sorted = value
      .map((Object? item) {
        final r = item as List;
        return (r[0] as int, (r[0] as int) + (r[1] as int));
      })
      .toList()
    ..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}
