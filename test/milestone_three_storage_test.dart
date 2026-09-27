import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tiktok_seller/core/storage/countcat_data_paths.dart';
import 'package:tiktok_seller/data/database/app_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('data paths keep CountCat data separate from program files', () async {
    final temp = await Directory.systemTemp.createTemp('countcat-paths-');
    final paths = CountCatDataPaths(root: temp);
    final root = await paths.root;
    final database = await paths.databaseFile;
    final avatars = await paths.avatarsDirectory;
    expect(root.path, isNot(contains('.dart_tool')));
    expect(root.path, isNot(contains('${Platform.pathSeparator}build${Platform.pathSeparator}')));
    expect(database.path.endsWith('tiktok_seller.db'), isTrue);
    expect(avatars.path.startsWith(root.path), isTrue);
    await temp.delete(recursive: true);
  });

  test('legacy database is copied once and persistent database wins', () async {
    final temp = await Directory.systemTemp.createTemp('countcat-legacy-');
    final originalCurrent = Directory.current;
    Directory.current = temp;
    try {
      final paths = CountCatDataPaths(root: Directory('${temp.path}${Platform.pathSeparator}user-data'));
      final legacy = paths.legacyDatabaseFile();
      await legacy.parent.create(recursive: true);
      final legacyDb = await databaseFactoryFfi.openDatabase(legacy.path);
      await legacyDb.execute('CREATE TABLE marker (value TEXT)');
      await legacyDb.insert('marker', {'value': 'legacy'});
      await legacyDb.close();
      final database = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      final opened = await database.database;
      expect((await opened.query('marker')).single['value'], 'legacy');
      final persistent = await paths.databaseFile;
      expect(await persistent.exists(), isTrue);
      expect(await legacy.exists(), isTrue);
      await database.close();
      await databaseFactoryFfi.deleteDatabase(legacy.path);
      final repeat = AppDatabase.forTesting(paths: paths, databaseFactory: databaseFactoryFfi);
      expect((await (await repeat.database).query('marker')).single['value'], 'legacy');
      await repeat.close();
    } finally {
      Directory.current = originalCurrent;
      await temp.delete(recursive: true);
    }
  });
}
