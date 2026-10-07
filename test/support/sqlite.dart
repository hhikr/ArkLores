import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs sqflite on the desktop FFI implementation, as the build tools and the
/// live harness do. Call it from `setUpAll`.
void useSqfliteFfi() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
