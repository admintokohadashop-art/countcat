import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The one place that defines where user-owned CountCat files live.
class CountCatDataPaths {
  CountCatDataPaths({Directory? root}) : _root = root;

  static const databaseFilename = 'tiktok_seller.db';
  final Directory? _root;

  Future<Directory> get root async {
    final base = _root ?? await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}CountCat')
        .create(recursive: true);
  }

  Future<File> get databaseFile async => File('${(await root).path}${Platform.pathSeparator}$databaseFilename');
  Future<Directory> get avatarsDirectory async => Directory('${(await root).path}${Platform.pathSeparator}avatars').create(recursive: true);
  Future<Directory> get backupsDirectory async => Directory('${(await root).path}${Platform.pathSeparator}backups').create(recursive: true);

  /// The development FFI location used by older Windows builds.
  File legacyDatabaseFile({Directory? workingDirectory}) {
    final cwd = workingDirectory ?? Directory.current;
    return File('${cwd.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}sqflite_common_ffi${Platform.pathSeparator}databases${Platform.pathSeparator}$databaseFilename');
  }
}
