import 'dart:io';

import 'package:arklores/core/userdata/library_ref.dart';
import 'package:arklores/core/userdata/user_data_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/temp_dir.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late DateTime now;
  late UserDataStore store;

  UserDataStore open() => UserDataStore(
        factory: databaseFactoryFfi,
        path: p.join(dir.path, userDataFileName),
        clock: () => now,
      );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('arklores_userdata_');
    now = DateTime(2026, 10, 4, 12);
    store = open();
  });

  tearDown(() async {
    await store.close();
    await deleteTempDir(dir);
  });

  group('LibraryRef', () {
    test('round-trips every kind', () {
      final refs = [
        const LibraryRef.story('activities/act1/level_a01.txt'),
        const LibraryRef.record('rec_1'),
        LibraryRef.document('char_002', 'operator_profile_bundle'),
        const LibraryRef.user('u1'),
      ];
      for (final ref in refs) {
        expect(LibraryRef.tryParse(ref.toString()), ref);
      }
      expect(refs.last.isOfficial, isFalse);
      expect(refs.first.isOfficial, isTrue);
    });

    test('unknown kinds and empty ids are skipped, not fatal', () {
      expect(LibraryRef.tryParse('video:x'), isNull);
      expect(LibraryRef.tryParse('story:'), isNull);
      expect(LibraryRef.tryParse('no-colon'), isNull);
      // A colon inside the id survives.
      expect(LibraryRef.tryParse('record:a:b')!.id, 'a:b');
    });
  });

  group('reading history', () {
    const a = LibraryRef.story('s/a.txt');
    const b = LibraryRef.story('s/b.txt');

    test('records opens, counts them and lists newest first', () async {
      await store.recordOpen(a, title: 'A', lineIndex: 3);
      now = now.add(const Duration(minutes: 1));
      await store.recordOpen(b, title: 'B');
      now = now.add(const Duration(minutes: 1));
      await store.recordOpen(a, title: 'A', lineIndex: 9);

      final recent = await store.recent();
      expect(recent.map((r) => r.ref), [a.toString(), b.toString()]);
      expect(recent.first.openCount, 2);
      expect(recent.first.lineIndex, 9);
    });

    test('a citation open keeps the library reading position', () async {
      await store.recordOpen(a, title: 'A', lineIndex: 40);
      await store.recordOpen(a, title: 'A', lineIndex: 7, fromCitation: true);
      final progress = (await store.progressOf(a))!;
      expect(progress.lineIndex, 40);
      expect(progress.fromCitation, isFalse);
    });

    test('citation-only items can be filtered out until read', () async {
      await store.recordOpen(a, title: 'A', lineIndex: 7, fromCitation: true);
      expect(await store.recent(includeCitationOnly: false), isEmpty);
      await store.recordOpen(a, title: 'A', lineIndex: 7);
      expect(await store.recent(includeCitationOnly: false), hasLength(1));
    });

    test('position updates and clearing', () async {
      await store.recordOpen(a, title: 'A');
      await store.updatePosition(a, 120, finished: true);
      final progress = (await store.progressOf(a))!;
      expect(progress.lineIndex, 120);
      expect(progress.finished, isTrue);

      await store.recordOpen(b, title: 'B');
      await store.clearHistory(a);
      expect((await store.recent()).map((r) => r.ref), [b.toString()]);
      await store.clearHistory();
      expect(await store.recent(), isEmpty);
    });
  });

  group('bookmarks', () {
    test('save, list per item, replace and delete', () async {
      const ref = LibraryRef.story('s/a.txt');
      await store.saveBookmark(
        LibraryBookmark(
          id: 'b1',
          ref: ref.toString(),
          title: 'A',
          lineStart: 3,
          lineEnd: 5,
          createdAt: now,
        ),
      );
      await store.saveBookmark(
        LibraryBookmark(
          id: 'b2',
          ref: const LibraryRef.record('r').toString(),
          title: 'R',
          createdAt: now.add(const Duration(seconds: 1)),
        ),
      );
      expect((await store.bookmarks()).map((b) => b.id), ['b2', 'b1']);
      expect((await store.bookmarks(ref: ref)).single.lineEnd, 5);

      await store.saveBookmark(
        LibraryBookmark(
          id: 'b1',
          ref: ref.toString(),
          title: 'A',
          note: 'edited',
          createdAt: now,
        ),
      );
      expect((await store.bookmarks(ref: ref)).single.note, 'edited');

      await store.deleteBookmark('b1');
      expect(await store.bookmarks(ref: ref), isEmpty);
    });
  });

  test('data survives reopening the file', () async {
    const ref = LibraryRef.story('s/a.txt');
    await store.recordOpen(ref, title: 'A', lineIndex: 12);
    await store.close();
    store = open();
    expect((await store.progressOf(ref))!.lineIndex, 12);
    final db = await databaseFactoryFfi.openDatabase(
      p.join(dir.path, userDataFileName),
    );
    expect(await db.getVersion(), userDataSchemaVersion);
    await db.close();
  });
}
