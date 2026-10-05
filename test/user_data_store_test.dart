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
    now = DateTime(2026, 10, 5, 12);
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
      expect(LibraryRef.tryParse('record:a:b')!.id, 'a:b');
    });
  });

  group('reading history', () {
    const a = LibraryRef.story('s/a.txt');
    const b = LibraryRef.story('s/b.txt');

    test('one row per item: newest first, anchor replaced, visits counted',
        () async {
      await store.recordOpen(a, title: 'A', lineIndex: 3, snippet: 'first');
      now = now.add(const Duration(minutes: 1));
      await store.recordOpen(b, title: 'B', lineIndex: 0, snippet: 'b0');
      now = now.add(const Duration(minutes: 1));
      await store.recordOpen(a, title: 'A2', lineIndex: 9, snippet: 'second');

      final recent = await store.recent();
      expect(recent.map((r) => r.ref), [a.toString(), b.toString()]);
      expect(recent.first.openCount, 2);
      expect(recent.first.lineIndex, 9);
      expect(recent.first.snippet, 'second');
      expect(recent.first.title, 'A2');
      expect(recent.first.openedAt, now);
    });

    test('the snippet is cut to its limit', () async {
      await store.recordOpen(
        a,
        title: 'A',
        lineIndex: 0,
        snippet: '  ${'x' * 200}',
      );
      expect((await store.recent()).single.snippet, 'x' * historySnippetLength);
    });

    test('clearing one item or everything', () async {
      await store.recordOpen(a, title: 'A', lineIndex: 0, snippet: '');
      await store.recordOpen(b, title: 'B', lineIndex: 0, snippet: '');
      await store.clearHistory(a);
      expect((await store.recent()).map((r) => r.ref), [b.toString()]);
      await store.clearHistory();
      expect(await store.recent(), isEmpty);
    });

    test('the oldest entries are dropped beyond the limit', () async {
      for (var i = 0; i < historyLimit + 5; i++) {
        now = now.add(const Duration(seconds: 1));
        await store.recordOpen(
          LibraryRef.story('s/$i.txt'),
          title: '$i',
          lineIndex: 0,
          snippet: '',
        );
      }
      final all = await store.recent(limit: 1000);
      expect(all, hasLength(historyLimit));
      expect(all.first.title, '${historyLimit + 4}');
      expect(all.last.title, '5');
    });
  });

  group('reanchorLine', () {
    final lines = ['零', '一一一', '二二二', '三三三', '四四四'];

    test('keeps the anchor while the line is still there', () {
      expect(reanchorLine(lines, 2, '二二'), (index: 2, exact: true));
    });

    test('follows the line when lines were added or removed before it', () {
      final shifted = ['新', '新', ...lines];
      expect(reanchorLine(shifted, 2, '二二'), (index: 4, exact: true));
      expect(reanchorLine(lines.sublist(1), 2, '三三'), (index: 2, exact: true));
    });

    test('takes the nearest of several equal lines', () {
      final twice = ['同', 'x', 'x', 'x', '同'];
      expect(reanchorLine(twice, 3, '同'), (index: 4, exact: true));
    });

    test('falls back to the clamped position when the text is gone', () {
      expect(reanchorLine(lines, 3, '没有'), (index: 3, exact: false));
      expect(reanchorLine(lines, 99, '没有'), (index: 4, exact: false));
      expect(reanchorLine(const [], 3, '没有'), isNull);
    });
  });

  group('migrations', () {
    test('a new file gets the current version', () async {
      await store.recent();
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(
        p.join(dir.path, userDataFileName),
      );
      expect(await db.getVersion(), userDataSchemaVersion);
      await db.close();
    });

    test('data survives reopening the file', () async {
      const ref = LibraryRef.story('s/a.txt');
      await store.recordOpen(ref, title: 'A', lineIndex: 12, snippet: 'hi');
      await store.close();
      store = open();
      expect((await store.recent()).single.lineIndex, 12);
    });

    test('an older file is upgraded step by step, data kept', () async {
      // Simulate a file written before the last step existed.
      final path = p.join(dir.path, userDataFileName);
      final old = await databaseFactoryFfi.openDatabase(path);
      await old.execute('CREATE TABLE marker (v TEXT)');
      await old.insert('marker', {'v': 'kept'});
      await old.setVersion(0);
      await old.close();

      store = open();
      await store.recordOpen(
        const LibraryRef.story('s/a.txt'),
        title: 'A',
        lineIndex: 1,
        snippet: 's',
      );
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), userDataSchemaVersion);
      expect((await db.query('marker')).single['v'], 'kept');
      await db.close();
    });

    test('a file from a newer app is opened, not downgraded or wiped',
        () async {
      final path = p.join(dir.path, userDataFileName);
      await store.recordOpen(
        const LibraryRef.story('s/a.txt'),
        title: 'A',
        lineIndex: 1,
        snippet: 's',
      );
      await store.close();
      final future = await databaseFactoryFfi.openDatabase(path);
      await future.execute('CREATE TABLE later (v TEXT)');
      await future.setVersion(userDataSchemaVersion + 3);
      await future.close();

      store = open();
      expect((await store.recent()).single.lineIndex, 1);
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      expect(await db.getVersion(), userDataSchemaVersion + 3);
      expect(await db.query('later'), isEmpty);
      await db.close();
    });
  });
}
