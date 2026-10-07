// The GitHub endpoints the source client uses, served from memory: the
// latest commit, git trees, raw files and the codeload zip.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'git_tree_mock.dart';

/// Serves [commits] (commit → path → content, paths from the repository
/// root) with [latest] as the branch head. Every request URL is added to
/// [requests]. A data table missing from a commit is served as `{}` (the
/// update downloads every context table it does not have).
MockClient fakeGitHub(
  Map<String, Map<String, String>> commits, {
  required String latest,
  List<Uri>? requests,
}) {
  String blob(String content) => sha1.convert(utf8.encode(content)).toString();
  final trees = gitTreeHandler({
    for (final MapEntry(key: commit, value: files) in commits.entries)
      commit: {for (final f in files.entries) f.key: blob(f.value)},
  });

  return MockClient((request) async {
    requests?.add(request.url);
    final url = request.url;
    final segments = url.pathSegments;
    switch (url.host) {
      case 'api.github.com' when segments.contains('trees'):
        return trees(request);
      case 'api.github.com' when segments.contains('commits'):
        return http.Response(jsonEncode({'sha': latest}), 200);
      case 'raw.githubusercontent.com':
        // /<owner>/<repo>/<sha>/<path…>
        final files = commits[segments[2]];
        final path = segments.skip(3).join('/');
        final content = files?[path] ??
            (files != null && path.contains('/excel/') ? '{}' : null);
        return content == null
            ? http.Response('404: Not Found', 404)
            : http.Response.bytes(utf8.encode(content), 200);
      case 'codeload.github.com':
        final sha = segments.last;
        final files = commits[sha];
        if (files == null) return http.Response('', 404);
        final archive = Archive();
        for (final MapEntry(key: path, value: content) in files.entries) {
          final bytes = utf8.encode(content);
          archive.addFile(
              ArchiveFile('ArknightsGameData-$sha/$path', bytes.length, bytes),);
        }
        return http.Response.bytes(ZipEncoder().encode(archive)!, 200);
    }
    return http.Response('unexpected ${request.url}', 500);
  });
}
