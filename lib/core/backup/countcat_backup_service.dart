import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../storage/countcat_data_paths.dart';
import '../../data/database/app_database.dart';

class CountCatBackupService {
  CountCatBackupService(this._database, {CountCatDataPaths? paths}) : _paths = paths ?? CountCatDataPaths();
  static const formatVersion = 1;
  final AppDatabase _database;
  final CountCatDataPaths _paths;

  Future<File> createBackup({File? destination}) async {
    final root = await _paths.root;
    final output = destination ?? File('${(await _paths.backupsDirectory).path}${Platform.pathSeparator}countcat-${DateTime.now().toUtc().toIso8601String().replaceAll(':', '-')}.countcat');
    final snapshot = File('${root.path}${Platform.pathSeparator}.backup-snapshot-${DateTime.now().microsecondsSinceEpoch}.db');
    try {
      final db = await _database.database;
      final quoted = snapshot.path.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$quoted'"); // SQLite creates a transactionally consistent snapshot.
      if (!await snapshot.exists()) throw StateError('Could not create a database snapshot.');
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', 0, utf8.encode(jsonEncode({'formatVersion': formatVersion, 'databaseFilename': CountCatDataPaths.databaseFilename, 'createdAt': DateTime.now().toUtc().toIso8601String()}))))
        ..addFile(ArchiveFile(CountCatDataPaths.databaseFilename, await snapshot.length(), await snapshot.readAsBytes()));
      final avatars = await _paths.avatarsDirectory;
      await for (final entry in avatars.list(recursive: true, followLinks: false)) {
        if (entry is File) {
          final relative = entry.path.substring(avatars.path.length).replaceAll('\\', '/').replaceFirst(RegExp(r'^/'), '');
          archive.addFile(ArchiveFile('avatars/$relative', await entry.length(), await entry.readAsBytes()));
        }
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw StateError('Could not finalize backup archive.');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(encoded, flush: true);
      await _validate(output);
      return output;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<File> restore(File source) async {
    final staged = await _stageAndValidate(source);
    final root = await _paths.root;
    final safety = await createBackup();
    final currentDatabase = await _paths.databaseFile;
    final currentAvatars = await _paths.avatarsDirectory;
    final oldRoot = Directory('${root.path}.restore-old-${DateTime.now().microsecondsSinceEpoch}');
    try {
      await _database.close();
      await oldRoot.create(recursive: true);
      if (await currentDatabase.exists()) await currentDatabase.rename('${oldRoot.path}${Platform.pathSeparator}${CountCatDataPaths.databaseFilename}');
      if (await currentAvatars.exists()) await currentAvatars.rename('${oldRoot.path}${Platform.pathSeparator}avatars');
      await currentDatabase.parent.create(recursive: true);
      await File('${staged.path}${Platform.pathSeparator}${CountCatDataPaths.databaseFilename}').copy(currentDatabase.path);
      final stagedAvatars = Directory('${staged.path}${Platform.pathSeparator}avatars');
      if (await stagedAvatars.exists()) await _copyDirectory(stagedAvatars, currentAvatars);
      await _database.database; // verify that the restored data opens before declaring success
      return safety;
    } catch (_) {
      await _database.close();
      if (await currentDatabase.exists()) await currentDatabase.delete();
      if (await currentAvatars.exists()) await currentAvatars.delete(recursive: true);
      final oldDb = File('${oldRoot.path}${Platform.pathSeparator}${CountCatDataPaths.databaseFilename}');
      final oldAvatars = Directory('${oldRoot.path}${Platform.pathSeparator}avatars');
      if (await oldDb.exists()) await oldDb.rename(currentDatabase.path);
      if (await oldAvatars.exists()) await oldAvatars.rename(currentAvatars.path);
      rethrow;
    } finally {
      if (await staged.exists()) await staged.delete(recursive: true);
    }
  }

  Future<Directory> _stageAndValidate(File backup) async {
    await _validate(backup);
    final decoded = ZipDecoder().decodeBytes(await backup.readAsBytes(), verify: true);
    final staging = await Directory.systemTemp.createTemp('countcat-restore-');
    for (final item in decoded.files) {
      if (!_safe(item.name)) throw FormatException('Unsafe archive path.');
      if (!item.isFile) continue;
      final target = File('${staging.path}${Platform.pathSeparator}${item.name}');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(item.content as List<int>, flush: true);
    }
    // SQLite opening catches corrupt/non-database inputs before live data changes.
    final stagedDb = File('${staging.path}${Platform.pathSeparator}${CountCatDataPaths.databaseFilename}');
    if (!await stagedDb.exists()) throw FormatException('Backup is missing its database.');
    final header = await stagedDb.openRead(0, 16).fold<List<int>>([], (bytes, part) => bytes..addAll(part));
    if (utf8.decode(header, allowMalformed: true) != 'SQLite format 3\u0000') {
      throw FormatException('Backup database is not readable SQLite data.');
    }
    return staging;
  }

  Future<void> _validate(File backup) async {
    if (!await backup.exists()) throw FormatException('Backup file does not exist.');
    final archive = ZipDecoder().decodeBytes(await backup.readAsBytes(), verify: true);
    final files = {for (final item in archive.files) item.name: item};
    if (files.keys.any((name) => !_safe(name))) throw FormatException('Unsafe archive path.');
    final manifest = files['manifest.json'];
    final database = files[CountCatDataPaths.databaseFilename];
    if (manifest == null || database == null || !manifest.isFile || !database.isFile) throw FormatException('Not a CountCat backup.');
    final data = jsonDecode(utf8.decode(manifest.content as List<int>)) as Map<String, dynamic>;
    if (data['formatVersion'] != formatVersion || data['databaseFilename'] != CountCatDataPaths.databaseFilename || data['createdAt'] is! String) throw FormatException('Unsupported CountCat backup format.');
  }

  bool _safe(String name) => name.isNotEmpty && !name.startsWith('/') && !name.startsWith('\\') && !name.contains('..') && !name.contains(':');
  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final item in from.list(recursive: true)) {
      if (item is File) { final relative = item.path.substring(from.path.length); final out = File('${to.path}$relative'); await out.parent.create(recursive: true); await item.copy(out.path); }
    }
  }
}
