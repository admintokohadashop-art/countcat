import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../sales/transaction_validator.dart';
import 'return_totals.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key, this.transactionRepository});

  final TransactionRepository? transactionRepository;

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final _searchController = TextEditingController();
  late final TransactionRepository _transactions;

  List<Transaction> _all = [];
  Transaction? _searchResult;
  var _searchPerformed = false;
  ReturnPeriod? _selectedPeriod;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final all = await _transactions.listTransactions();
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
      final periods = _availablePeriods;
      if (_selectedPeriod != null && !periods.contains(_selectedPeriod)) {
        _selectedPeriod = null;
      }
    });
  }

  List<ReturnPeriod> get _availablePeriods {
    final set = <ReturnPeriod>{};
    for (final t in _all) {
      if (t.orderStatus == OrderStatus.returned) {
        set.add(ReturnPeriod(t.transactionDate.year, t.transactionDate.month));
      }
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  List<Transaction> get _periodTransactions {
    if (_selectedPeriod == null) return _all;
    return _all.where((t) {
      final d = t.transactionDate;
      return d.year == _selectedPeriod!.year && d.month == _selectedPeriod!.month;
    }).toList();
  }

  List<Transaction> get _periodReturned => _periodTransactions
      .where((t) => t.orderStatus == OrderStatus.returned)
      .toList();

  ReturnTotals get _totals => ReturnTotals.fromTransactions(_periodTransactions);

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final results = await _transactions.listTransactions(search: query);
    Transaction? exact;
    for (final r in results) {
      if (r.orderId == query) { exact = r; break; }
    }
    if (!mounted) return;
    setState(() {
      _searchResult = exact;
      _searchPerformed = true;
    });
  }

  Future<void> _editCompensation(Transaction transaction) async {
    final controller = TextEditingController(
      text: transaction.returnShippingCompensation > 0
          ? '${transaction.returnShippingCompensation}'
          : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kompensasi Ongkir Retur'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nominal Kompensasi (Rp)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('BATAL')),
          FilledButton(
            onPressed: () {
              final parsed = Rupiah.parse(controller.text);
              if (parsed == null) return;
              if (TransactionValidator.returnShippingCompensation(parsed) != null) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await _transactions.updateTransaction(
        transaction.copyWith(returnShippingCompensation: result),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kompensasi ongkir tersimpan.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menyimpan kompensasi.')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final totals = _totals;
    final returned = _periodReturned;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Retur', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  labelText: 'Cari ID Pesanan',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton(onPressed: _search, child: const Text('SEARCH')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<ReturnPeriod?>(
            initialValue: _selectedPeriod,
            decoration: const InputDecoration(labelText: 'Periode', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<ReturnPeriod?>(value: null, child: Text('SEMUA PERIODE')),
              for (final p in _availablePeriods)
                DropdownMenuItem<ReturnPeriod?>(value: p, child: Text(p.label)),
            ],
            onChanged: (value) => setState(() => _selectedPeriod = value),
          ),
        ),
        if (_searchPerformed) ...[
          const SizedBox(height: 16),
          _SearchResult(result: _searchResult, onEdit: _editCompensation),
        ],
        const SizedBox(height: 24),
        if (returned.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Belum ada paket retur periode ini.')),
          )
        else ...[
          Text('Ringkasan Retur', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 24, runSpacing: 8, children: [
            Text('Total Paket Retur: ${totals.returnedCount}'),
            Text('Total Kompensasi Ongkir: ${Rupiah.format(totals.totalCompensation)}'),
            Text('Income Aktif: ${Rupiah.format(totals.activeIncome)}'),
            Text('Income Setelah Retur: ${Rupiah.format(totals.incomeAfterReturn)}'),
            Text('Total HPP Aktif: ${Rupiah.format(totals.activeHpp)}'),
            Text('Profit Setelah Retur: ${Rupiah.format(totals.profitAfterReturn)}'),
          ]),
          const SizedBox(height: 24),
          Text('Paket Retur', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final t in returned)
            _ReturnRow(transaction: t, onEdit: () => _editCompensation(t)),
        ],
      ],
    );
  }
}

class ReturnPeriod implements Comparable<ReturnPeriod> {
  const ReturnPeriod(this.year, this.month);
  final int year;
  final int month;
  String get label => '${_monthNames[month - 1]} $year'.toUpperCase();
  @override
  int compareTo(ReturnPeriod other) =>
      year == other.year ? month.compareTo(other.month) : year.compareTo(other.year);
  @override
  bool operator ==(Object other) =>
      other is ReturnPeriod && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
}

const _monthNames = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

class _SearchResult extends StatelessWidget {
  const _SearchResult({required this.result, required this.onEdit});
  final Transaction? result;
  final Future<void> Function(Transaction) onEdit;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('ID Pesanan tidak ditemukan.'),
        ),
      );
    }
    final isReturned = r.orderStatus == OrderStatus.returned;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID Pesanan: ${r.orderId}'),
            Text('Kode Barang: ${r.productCode}'),
            Text('Tanggal Transaksi: ${r.transactionDate.day}/${r.transactionDate.month}/${r.transactionDate.year}'),
            Text('Income: ${Rupiah.format(r.netIncomeAmount)}'),
            Text('Status: ${r.orderStatus.label}'),
            Text('Kompensasi Ongkir: ${r.returnShippingCompensation > 0 ? Rupiah.format(r.returnShippingCompensation) : "Belum diinput"}'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isReturned ? () => onEdit(r) : null,
                child: const Text('KOMPENSASI ONGKIR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({required this.transaction, required this.onEdit});
  final Transaction transaction;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text('ID Pesanan: ${transaction.orderId}'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kode Barang: ${transaction.productCode}'),
              Text('Tanggal: ${transaction.transactionDate.day}/${transaction.transactionDate.month}/${transaction.transactionDate.year}'),
              Text('Income: ${Rupiah.format(transaction.netIncomeAmount)}'),
              Text('Kompensasi: ${transaction.returnShippingCompensation > 0 ? Rupiah.format(transaction.returnShippingCompensation) : "Belum diinput"}'),
            ],
          ),
          trailing: FilledButton(onPressed: onEdit, child: const Text('KOMPENSASI ONGKIR')),
        ),
      );
}