import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/profile/countcat_data_paths.dart';
import '../database/app_database.dart';

class DataBackupService {
  DataBackupService(this._database);
  final AppDatabase _database;

  Future<String?> backupWithPicker() async {
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Simpan backup CountCat', fileName: 'countcat-backup.zip');
    return path == null ? null : backupTo(path);
  }
  Future<String> backupTo(String destination) async {
    await _database.close();
    final root = await CountCatDataPaths.root();
    final encoder = ZipFileEncoder();
    encoder.create(destination);
    final database = await CountCatDataPaths.databaseFile();
    if (!database.existsSync()) throw StateError('Database CountCat tidak ditemukan.');
    encoder.addFile(database, 'tiktok_seller.db');
    final avatars = await CountCatDataPaths.avatars();
    if (avatars.existsSync()) encoder.addDirectory(avatars, 'avatars');
    encoder.close();
    await _database.database;
    return destination;
  }
  Future<String?> restoreWithPicker() async { final selected = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']); if (selected?.files.single.path == null) return null; await restoreFrom(selected!.files.single.path!); return selected.files.single.path; }
  Future<void> restoreFrom(String source) async {
    final staging = await Directory.systemTemp.createTemp('countcat_restore_');
    try {
      final input = InputFileStream(source); final archive = ZipDecoder().decodeBuffer(input); input.close();
      final db = archive.findFile('tiktok_seller.db');
      if (db == null || !db.isFile || db.size == 0) throw FormatException('Backup CountCat tidak valid.');
      extractArchiveToDisk(archive, staging.path);
      final stagedDatabase = File('${staging.path}${Platform.pathSeparator}tiktok_seller.db');
      if (!stagedDatabase.existsSync()) throw FormatException('Backup CountCat tidak valid.');
      await backupTo('${(await CountCatDataPaths.root()).path}${Platform.pathSeparator}safety-backup-${DateTime.now().millisecondsSinceEpoch}.zip');
      await _database.close();
      final target = await CountCatDataPaths.databaseFile();
      await stagedDatabase.copy(target.path);
      final targetAvatars = await CountCatDataPaths.avatars();
      final stagedAvatars = Directory('${staging.path}${Platform.pathSeparator}avatars');
      if (stagedAvatars.existsSync()) { if (targetAvatars.existsSync()) await targetAvatars.delete(recursive: true); await stagedAvatars.rename(targetAvatars.path); }
      await _database.database;
    } finally { if (staging.existsSync()) await staging.delete(recursive: true); }
  }
}
