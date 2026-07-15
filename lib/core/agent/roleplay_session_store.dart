import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class RoleplaySessionStore {
  final String? filePath;

  const RoleplaySessionStore({this.filePath});

  Future<Map<String, dynamic>?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> session) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(session), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<File> _file() async {
    if (filePath != null) return File(filePath!);
    final directory = await getApplicationDocumentsDirectory();
    return File(p.join(directory.path, 'roleplay_session.json'));
  }
}
