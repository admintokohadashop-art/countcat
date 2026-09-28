import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../core/profile/avatar_storage.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'dashboard_totals.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.repository,
    this.transactionRepository,
  });

  final AccountRepository? repository;
  final TransactionRepository? transactionRepository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final AccountRepository _repo;
  late final TransactionRepository _transactions;
  final _avatars = AvatarStorage();
  List<Account> _items = [];
  Account? _active;
  DashboardTotals _totals = DashboardTotals.fromTransactions(const []);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? AccountRepository(AppDatabase.instance);
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.listAccounts();
    final active = await _repo.activeAccount();
    List<Transaction> transactions = const [];
    if (active != null) {
      transactions = await _transactions.listTransactions();
    }
    if (mounted) {
      setState(() {
        _items = items;
        _active = active;
        _totals = DashboardTotals.fromTransactions(transactions);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final description = TextEditingController();
    String? photoPath;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Account'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () async {
                final picked = await _avatars.pickAndCopy();
                if (picked != null) setDialogState(() => photoPath = picked);
              },
              customBorder: const CircleBorder(),
              child: _Avatar(path: photoPath, radius: 32),
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Account name')),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Short description')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('CANCEL')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('CREATE')),
          ],
        ),
      ),
    );
    if (created != true || name.text.trim().isEmpty) {
      await _avatars.deleteOwned(photoPath);
      return;
    }
    try {
      await _repo.create(name: name.text.trim(), description: description.text.trim(), photoPath: photoPath);
      await _load();
    } catch (_) {
      await _avatars.deleteOwned(photoPath);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      interactive: true,
                      child: ListView(children: [
                        for (final account in _items)
                          Card(
                            color: account.id == _active?.id ? Theme.of(context).colorScheme.secondaryContainer : null,
                            child: ListTile(
                              onTap: () async {
                                await _repo.setActiveAccountId(account.id);
                                await _load();
                              },
                              leading: _Avatar(path: account.photoPath),
                              title: Text(account.name),
                              subtitle: Text(account.description),
                            ),
                          ),
                        if (_active != null) ...[
                          const SizedBox(height: 24),
                          Text('Ringkasan', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                _SummaryRow(label: 'Barang Terjual', value: '${_totals.itemsSold}'),
                                _SummaryRow(label: 'GMV', value: Rupiah.format(_totals.gmv)),
                                _SummaryRow(label: 'Income', value: Rupiah.format(_totals.activeIncome)),
                                _SummaryRow(label: 'Profit', value: Rupiah.format(_totals.profit)),
                                _SummaryRow(label: 'Retur', value: '${_totals.returnedQty} barang'),
                                _SummaryRow(label: 'Kompensasi', value: Rupiah.format(_totals.totalCompensation)),
                              ]),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.add),
                            title: const Text('Create New Account'),
                            onTap: _create,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
      );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value),
        ]),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.path, this.radius = 20});
  final String? path;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    return CircleAvatar(
      radius: radius,
      backgroundImage: file != null && file.existsSync() ? FileImage(file) : null,
      child: file == null || !file.existsSync() ? const Icon(Icons.person) : null,
    );
  }
}