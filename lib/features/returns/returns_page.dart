import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_with_order.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../sales/transaction_validator.dart';
import 'return_totals.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({
    super.key,
    this.transactionRepository,
    this.orderRepository,
  });

  final TransactionRepository? transactionRepository;
  final OrderRepository? orderRepository;

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final _searchController = TextEditingController();
  late final TransactionRepository _transactions;
  late final OrderRepository _orders;

  List<TransactionWithOrder> _all = [];
  Order? _searchedOrder;
  List<Transaction> _searchedItems = const [];
  var _searchPerformed = false;
  ReturnPeriod? _selectedPeriod;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _orders = widget.orderRepository ?? OrderRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final all = await _transactions.listItemsJoined();
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
    for (final v in _all) {
      if (v.order.orderStatus == OrderStatus.returned) {
        set.add(ReturnPeriod(v.order.transactionDate.year, v.order.transactionDate.month));
      }
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  List<TransactionWithOrder> get _periodItems {
    if (_selectedPeriod == null) return _all;
    return _all.where((v) {
      final d = v.order.transactionDate;
      return d.year == _selectedPeriod!.year && d.month == _selectedPeriod!.month;
    }).toList();
  }

  /// One entry per returned order, items sorted by item_index.
  List<_ReturnedOrderGroup> get _returnedGroups {
    final map = <String, _ReturnedOrderGroup>{};
    for (final v in _periodItems) {
      if (v.order.orderStatus != OrderStatus.returned) continue;
      final key = '${v.order.accountId}::${v.order.orderId}';
      map.putIfAbsent(key, () => _ReturnedOrderGroup(order: v.order, items: [])).items.add(v.item);
    }
    final list = map.values.toList();
    for (final g in list) {
      g.items.sort((a, b) => a.itemIndex.compareTo(b.itemIndex));
    }
    return list;
  }

  ReturnTotals get _totals => ReturnTotals.fromJoined(_periodItems);

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final results = await _transactions.listItemsJoined(search: query);
    final matches = <Transaction>[];
    Order? matchedOrder;
    for (final v in results) {
      if (v.order.orderId == query) {
        matchedOrder = v.order;
        matches.add(v.item);
      }
    }
    if (!mounted) return;
    setState(() {
      _searchedOrder = matchedOrder;
      _searchedItems = matches;
      _searchPerformed = true;
    });
  }

  Future<void> _editCompensation(Order order) async {
    final controller = TextEditingController(
      text: order.returnShippingCompensation > 0 ? '${order.returnShippingCompensation}' : '',
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
      await _orders.update(order.copyWith(returnShippingCompensation: result));
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
    final groups = _returnedGroups;

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
            isExpanded: true,
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
          _SearchResult(
            order: _searchedOrder,
            items: _searchedItems,
            onEdit: _editCompensation,
          ),
        ],
        const SizedBox(height: 24),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Belum ada paket retur periode ini.')),
          )
        else ...[
          Text('Ringkasan Retur', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 24, runSpacing: 8, children: [
            Text('Total Paket Retur: ${totals.returnedCount}'),
            Text('Total Barang Retur: ${totals.returnedQty} barang'),
            Text('Total Kompensasi Ongkir: ${Rupiah.format(totals.totalCompensation)}'),
            Text('Income Aktif: ${Rupiah.format(totals.activeIncome)}'),
            Text('Income Setelah Retur: ${Rupiah.format(totals.incomeAfterReturn)}'),
            Text('Total HPP Aktif: ${Rupiah.format(totals.activeHpp)}'),
            Text('Profit Setelah Retur: ${Rupiah.format(totals.profitAfterReturn)}'),
          ]),
          const SizedBox(height: 24),
          Text('Paket Retur', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final g in groups)
            _ReturnedOrderCard(group: g, onEdit: () => _editCompensation(g.order)),
        ],
      ],
    );
  }
}

class _ReturnedOrderGroup {
  _ReturnedOrderGroup({required this.order, required this.items});
  final Order order;
  final List<Transaction> items;
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
  const _SearchResult({required this.order, required this.items, required this.onEdit});
  final Order? order;
  final List<Transaction> items;
  final Future<void> Function(Order) onEdit;

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('ID Pesanan tidak ditemukan.'),
        ),
      );
    }
    final isReturned = o.orderStatus == OrderStatus.returned;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID Pesanan: ${o.orderId}'),
            Text('Tanggal Transaksi: ${o.transactionDate.day}/${o.transactionDate.month}/${o.transactionDate.year}'),
            Text('Status: ${o.orderStatus.label}'),
            Text('Item: ${items.length}'),
            Text('Kompensasi Ongkir: ${o.returnShippingCompensation > 0 ? Rupiah.format(o.returnShippingCompensation) : "Belum diinput"}'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: isReturned ? () => onEdit(o) : null,
                child: const Text('KOMPENSASI ONGKIR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnedOrderCard extends StatelessWidget {
  const _ReturnedOrderCard({required this.group, required this.onEdit});
  final _ReturnedOrderGroup group;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final order = group.order;
    final totalQty = group.items.fold<int>(0, (sum, item) => sum + item.quantity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID Pesanan: ${order.orderId}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('Tanggal: ${order.transactionDate.day}/${order.transactionDate.month}/${order.transactionDate.year}'),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: onEdit,
                  child: const Text('KOMPENSASI ONGKIR'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Total Qty Retur: $totalQty'),
            Text('Kompensasi: ${order.returnShippingCompensation > 0 ? Rupiah.format(order.returnShippingCompensation) : "Belum diinput"}'),
            const Divider(height: 24),
            for (final item in group.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('${item.productCode} × ${item.quantity}')),
                    Text('Income: ${Rupiah.format(item.netIncomeAmount)}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}