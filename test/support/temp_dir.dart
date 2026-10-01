import 'dart:io';

/// Deletes a test temp directory, tolerating Windows file locks.
///
/// Tests open SQLite files through shared sqflite connections that outlive a
/// single test. POSIX allows deleting open files; Windows does not, so a
/// strict delete fails the teardown even though the test itself passed. A
/// leftover temp directory is harmless (the OS temp dir is cleaned later).
Future<void> deleteTempDir(Directory dir) async {
  if (!dir.existsSync()) return;
  try {
    await dir.delete(recursive: true);
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
}
