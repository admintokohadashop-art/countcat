import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CountCatDataPaths {
  static const databaseFileName = 'tiktok_seller.db';
  static Future<Directory> root() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}CountCat').create(recursive: true);
  }
  static Future<File> databaseFile() async => File('${(await root()).path}${Platform.pathSeparator}$databaseFileName');
  static Future<Directory> avatars() async => Directory('${(await root()).path}${Platform.pathSeparator}avatars').create(recursive: true);
  static File legacyDatabase(Directory workingDirectory) => File('${workingDirectory.path}${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}sqflite_common_ffi${Platform.pathSeparator}databases${Platform.pathSeparator}$databaseFileName');
}
