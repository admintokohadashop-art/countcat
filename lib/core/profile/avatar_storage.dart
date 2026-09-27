import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class AvatarStorage {
  AvatarStorage({ImagePicker? picker}) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  Future<String?> pickAndCopy() async {
    final selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected == null) return null;
    final directory = await _avatarDirectory();
    final extension = _extension(selected.path);
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(selected.path).copy(destination.path);
    return destination.path;
  }

  Future<bool> isOwnedPath(String? path) async {
    if (path == null) return false;
    final directory = await _avatarDirectory();
    final normalizedDirectory = '${directory.absolute.path}${Platform.pathSeparator}';
    return File(path).absolute.path.startsWith(normalizedDirectory);
  }

  Future<void> deleteOwned(String? path) async {
    if (!await isOwnedPath(path)) return;
    try {
      await File(path!).delete();
    } on FileSystemException {
      // A missing avatar is already safely removed.
    }
  }

  Future<Directory> _avatarDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}avatars').create(recursive: true);
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '.jpg' : path.substring(dot);
  }
}
