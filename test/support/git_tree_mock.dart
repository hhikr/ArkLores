import 'dart:convert';

import 'package:http/http.dart' as http;

/// Serves GitHub's `git/trees` API for commits described as flat
/// `path → blob hash` maps (paths from the repository root). A tree id is
/// the commit name for the root and `<commit>|<dir>` below it.
Future<http.Response> Function(http.Request) gitTreeHandler(
  Map<String, Map<String, String>> commits, {
  Set<String> truncated = const {},
}) {
  return (request) async {
    final id = request.url.pathSegments.last;
    final recursive = request.url.queryParameters['recursive'] == '1';
    final bar = id.indexOf('|');
    final commit = bar < 0 ? id : id.substring(0, bar);
    final dir = bar < 0 ? '' : id.substring(bar + 1).replaceAll('~', '/');
    final files = commits[commit];
    if (files == null) return http.Response('{"message":"Not Found"}', 404);
    final prefix = dir.isEmpty ? '' : '$dir/';
    final entries = <Map<String, String>>[];
    final seenDirs = <String>{};
    for (final f in files.entries) {
      if (!f.key.startsWith(prefix)) continue;
      final rest = f.key.substring(prefix.length);
      if (recursive) {
        entries.add({'path': rest, 'type': 'blob', 'sha': f.value});
      } else if (rest.contains('/')) {
        final name = rest.substring(0, rest.indexOf('/'));
        if (seenDirs.add(name)) {
          entries.add({
            'path': name,
            'type': 'tree',
            'sha': '$commit|${prefix.replaceAll('/', '~')}$name',
          });
        }
      } else {
        entries.add({'path': rest, 'type': 'blob', 'sha': f.value});
      }
    }
    return http.Response(
      jsonEncode({
        'tree': entries,
        'truncated': truncated.contains(id),
      }),
      200,
    );
  };
}
