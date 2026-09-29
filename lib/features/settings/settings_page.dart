import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/backup/countcat_backup_service.dart';
import '../../core/currency/rupiah.dart';
import '../../core/profile/avatar_storage.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account.dart';
import '../../data/models/hpp_master.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/hpp_repository.dart';
import 'package:file_picker/file_picker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.repository, this.hppRepository});
  final AccountRepository? repository;
  final HppRepository? hppRepository;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AccountRepository _accounts;
  late final HppRepository _hpp;
  Account? _account;
  List<HppMaster> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _accounts = widget.repository ?? AccountRepository(AppDatabase.instance);
    _hpp = widget.hppRepository ?? HppRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final a = await _accounts.activeAccount();
    final h = a == null ? <HppMaster>[] : await _hpp.list(a.id!, activeOnly: false);
    if (mounted) {
      setState(() {
        _account = a;
        _items = h;
        _loading = false;
      });
    }
  }

  Future<void> _add([HppMaster? x]) async {
    final n = TextEditingController(text: x?.name);
    final p = TextEditingController(text: x?.unitAmount.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(x == null ? 'Create HPP' : 'Edit HPP'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'Nama HPP')),
          TextField(controller: p, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga HPP')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('CANCEL')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('SAVE')),
        ],
      ),
    );
    final amount = Rupiah.parse(p.text);
    if (ok == true && _account != null && n.text.trim().isNotEmpty && amount != null) {
      if (x == null) {
        await _hpp.create(accountId: _account!.id!, name: n.text.trim(), unitAmount: amount);
      } else {
        await _hpp.update(HppMaster(
          id: x.id,
          accountId: x.accountId,
          name: n.text.trim(),
          unitAmount: amount,
          isActive: x.isActive,
          createdAt: x.createdAt,
          updatedAt: x.updatedAt,
        ));
      }
      await _load();
    }
  }

  Widget _profile(BuildContext context) {
    final account = _account!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: _ProfileAvatar(account.photoPath),
          title: Text(account.name),
          subtitle: Text(account.description),
          trailing: TextButton(onPressed: () => _editProfile(account), child: const Text('EDIT')),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _confirmDelete(account),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('DELETE ACCOUNT'),
          ),
        ),
      ],
    );
  }

  Future<void> _editProfile(Account original) async {
    final name = TextEditingController(text: original.name);
    final description = TextEditingController(text: original.description);
    final storage = AvatarStorage();
    String? pendingPath = original.photoPath;
    var remove = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Account'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _ProfileAvatar(remove ? null : pendingPath, radius: 32),
            TextButton(
              onPressed: () async {
                final picked = await storage.pickAndCopy();
                if (picked != null) {
                  setDialogState(() {
                    pendingPath = picked;
                    remove = false;
                  });
                }
              },
              child: const Text('CHANGE PHOTO'),
            ),
            TextButton(
              onPressed: () {
                setDialogState(() {
                  remove = true;
                });
              },
              child: const Text('REMOVE PHOTO'),
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Short description')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('SAVE')),
          ],
        ),
      ),
    );
    if (save != true || name.text.trim().isEmpty) {
      if (pendingPath != original.photoPath) {
        await storage.deleteOwned(pendingPath);
      }
      return;
    }
    final nextPath = remove ? null : pendingPath;
    try {
      await _accounts.update(original.copyWith(name: name.text.trim(), description: description.text.trim(), photoPath: nextPath));
      if (original.photoPath != nextPath) {
        await storage.deleteOwned(original.photoPath);
      }
      if (remove && pendingPath != original.photoPath) {
        await storage.deleteOwned(pendingPath);
      }
      await _load();
    } catch (_) {
      if (pendingPath != original.photoPath) {
        await storage.deleteOwned(pendingPath);
      }
      rethrow;
    }
  }

  Future<void> _confirmDelete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus Account?'),
        content: Text(
          'Account "${account.name}" beserta seluruh transaksi, report, live session, '
          'HPP, account settings, dan avatar milik account tersebut akan dihapus permanen. '
          'Account lain tidak terpengaruh.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('BATAL')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('HAPUS ACCOUNT'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _accounts.delete(account);
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account berhasil dihapus.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus account.')));
    }
  }

  Future<void> _backup() async {
    try {
      final target = await FilePicker.platform.saveFile(dialogTitle: 'Save CountCat backup', fileName: 'countcat-backup.countcat');
      if (target == null) {
        return;
      }
      await CountCatBackupService(AppDatabase.instance).createBackup(destination: File(target));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup created.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }

  Future<void> _restore() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['countcat', 'zip']);
      final path = picked?.files.single.path;
      if (path == null) {
        return;
      }
      await CountCatBackupService(AppDatabase.instance).restore(File(path));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data restored. A safety backup was created.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_account == null) {
      return const Center(child: Text('Buat account terlebih dahulu'));
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(children: [
        Text('Account Profile', style: Theme.of(c).textTheme.headlineSmall),
        _profile(c),
        const SizedBox(height: 24),
        Text('Data', style: Theme.of(c).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 12, children: [
          FilledButton(onPressed: _backup, child: const Text('BACKUP DATA')),
          OutlinedButton(onPressed: _restore, child: const Text('RESTORE DATA')),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Text('HPP Master', style: Theme.of(c).textTheme.titleLarge),
          const Spacer(),
          FilledButton(onPressed: () => _add(), child: const Text('CREATE HPP')),
        ]),
        for (final h in _items)
          ListTile(
            title: Text(h.name),
            subtitle: Text(Rupiah.format(h.unitAmount)),
            trailing: Wrap(children: [
              TextButton(onPressed: h.isActive ? () => _add(h) : null, child: const Text('EDIT')),
              TextButton(
                onPressed: h.isActive
                    ? () async {
                        await _hpp.deactivate(h.id!, h.accountId);
                        await _load();
                      }
                    : null,
                child: const Text('DELETE'),
              ),
            ]),
          ),
      ]),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.path, {this.radius = 20, super.key});
  final String? path;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final valid = file != null && file.existsSync();
    return CircleAvatar(radius: radius, backgroundImage: valid ? FileImage(file) : null, child: valid ? null : const Icon(Icons.person));
  }
}

typedef _ProfileAvatar = ProfileAvatar;