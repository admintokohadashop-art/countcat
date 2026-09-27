import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/profile/avatar_storage.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account.dart';
import '../../data/repositories/account_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _repo = AccountRepository(AppDatabase.instance);
  final _avatars = AvatarStorage();
  List<Account> _items = [];
  Account? _active;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async { final items = await _repo.listAccounts(); final active = await _repo.activeAccount(); if (mounted) setState(() { _items = items; _active = active; _loading = false; }); }

  Future<void> _create() async {
    final name = TextEditingController(); final description = TextEditingController(); String? photoPath;
    final created = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(title: const Text('Create New Account'), content: Column(mainAxisSize: MainAxisSize.min, children: [InkWell(onTap: () async { final picked = await _avatars.pickAndCopy(); if (picked != null) setDialogState(() => photoPath = picked); }, customBorder: const CircleBorder(), child: _Avatar(path: photoPath, radius: 32)), TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')), TextField(controller: description, decoration: const InputDecoration(labelText: 'Short description'))]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('CREATE'))])));
    if (created != true || name.text.trim().isEmpty) { await _avatars.deleteOwned(photoPath); return; }
    try { await _repo.create(name: name.text.trim(), description: description.text.trim(), photoPath: photoPath); await _load(); } catch (_) { await _avatars.deleteOwned(photoPath); rethrow; }
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: _loading ? const Center(child: CircularProgressIndicator()) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 16), Expanded(child: Scrollbar(thumbVisibility: true, interactive: true, child: ListView(children: [for (final account in _items) Card(color: account.id == _active?.id ? Theme.of(context).colorScheme.secondaryContainer : null, child: ListTile(onTap: () async { await _repo.setActiveAccountId(account.id); await _load(); }, leading: _Avatar(path: account.photoPath), title: Text(account.name), subtitle: Text(account.description))), ListTile(leading: const Icon(Icons.add), title: const Text('Create New Account'), onTap: _create)])))]));
}

class _Avatar extends StatelessWidget { const _Avatar({this.path, this.radius = 20}); final String? path; final double radius; @override Widget build(BuildContext context) { final file = path == null ? null : File(path!); return CircleAvatar(radius: radius, backgroundImage: file != null && file.existsSync() ? FileImage(file) : null, child: file == null || !file.existsSync() ? const Icon(Icons.person) : null); } }
