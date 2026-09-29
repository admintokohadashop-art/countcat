import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/live_session.dart';
import '../../data/models/monthly_report.dart';
import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_with_order.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../data/repositories/monthly_report_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../sales/transaction_validator.dart';
import 'report_totals.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    this.transactionRepository,
    this.monthlyReportRepository,
    this.liveSessionRepository,
    this.orderRepository,
  });

  final TransactionRepository? transactionRepository;
  final MonthlyReportRepository? monthlyReportRepository;
  final LiveSessionRepository? liveSessionRepository;
  final OrderRepository? orderRepository;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final TransactionRepository _transactions;
  late final MonthlyReportRepository _monthlyReports;
  List<ReportMonth> _months = [];
  var _loading = true;
  var _revision = 0;

  @override
  void initState() {
    super.initState();
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _monthlyReports = widget.monthlyReportRepository ?? MonthlyReportRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _transactions.listItemsJoined(),
      _monthlyReports.listReports(),
    ]);
    final months = <ReportMonth>{};
    for (final item in values[0] as List<TransactionWithOrder>) {
      final date = item.order.transactionDate;
      months.add(ReportMonth(date.year, date.month));
    }
    for (final item in values[1] as List<MonthlyReport>) {
      months.add(ReportMonth(item.year, item.month));
    }
    if (!mounted) return;
    setState(() {
      _months = months.toList()..sort((a, b) => b.compareTo(a));
      _loading = false;
      _revision++;
    });
  }

  Future<void> _openMonth(ReportMonth month) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MonthDetailPage(
          month: month,
          transactionRepository: widget.transactionRepository,
          monthlyReportRepository: widget.monthlyReportRepository,
          liveSessionRepository: widget.liveSessionRepository,
          orderRepository: widget.orderRepository,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Rekap Bulanan', style: Theme.of(context).textTheme.headlineSmall)),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
                ]),
                const SizedBox(height: 16),
                Expanded(
                  child: _months.isEmpty
                      ? const Center(child: Text('Belum ada transaksi.'))
                      : ListView(children: [
                          for (final month in _months)
                            _MonthCard(
                              key: ValueKey('${month.year}-${month.month}-$_revision'),
                              month: month,
                              reports: _monthlyReports,
                              onOpen: () => _openMonth(month),
                            ),
                        ]),
                ),
                const _Footer(),
              ]),
      );
}

class _MonthCard extends StatefulWidget {
  const _MonthCard({required this.month, required this.reports, required this.onOpen, super.key});
  final ReportMonth month;
  final MonthlyReportRepository reports;
  final Future<void> Function() onOpen;
  @override
  State<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends State<_MonthCard> {
  MonthlyReport? _report;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final reports = await widget.reports.listReports();
    final matches = reports.where((item) => item.year == widget.month.year && item.month == widget.month.month);
    if (mounted) setState(() => _report = matches.isEmpty ? null : matches.first);
  }

  Future<void> _open() async {
    await widget.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Card(
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (context, constraints) {
            final summary = report == null
                ? const Text('Belum disubmit')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total GMV: ${Rupiah.format(report.gmvTotal)}'),
                      Text('Total Income: ${Rupiah.format(report.netIncomeTotal)}'),
                      Text('Total Profit: ${Rupiah.format(report.profitTotal)}'),
                      Text('Terakhir diperbarui: ${_formatDateTime(report.submittedAt)}'),
                    ],
                  );
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.month.label, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(widget.month.periodLabel),
              ],
            );
            return constraints.maxWidth >= 600
                ? Row(children: [Expanded(child: heading), const SizedBox(width: 24), summary])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [heading, const SizedBox(height: 12), summary]);
          }),
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

class ReportMonth implements Comparable<ReportMonth> {
  const ReportMonth(this.year, this.month);
  final int year;
  final int month;
  DateTime get start => DateTime(year, month);
  DateTime get end => DateTime(year, month + 1);
  String get label => '${_monthNames[month - 1]} $year'.toUpperCase();
  String get periodLabel => '1 ${_monthNames[month - 1]} $year — ${end.subtract(const Duration(days: 1)).day} ${_monthNames[month - 1]} $year';
  @override
  int compareTo(ReportMonth other) => year == other.year ? month.compareTo(other.month) : year.compareTo(other.year);
  @override
  bool operator ==(Object other) => other is ReportMonth && other.year == year && other.month == month;
  @override
  int get hashCode => Object.hash(year, month);
}

const _monthNames = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

class _Footer extends StatelessWidget {
  const _Footer();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Center(child: Text('© 2026 Pram', style: Theme.of(context).textTheme.bodySmall)),
      );
}

class _OrderGroup {
  _OrderGroup({required this.order, required this.items});
  final Order order;
  final List<TransactionWithOrder> items;
}

class MonthDetailPage extends StatefulWidget {
  const MonthDetailPage({
    required this.month,
    super.key,
    this.transactionRepository,
    this.monthlyReportRepository,
    this.liveSessionRepository,
    this.orderRepository,
  });
  final ReportMonth month;
  final TransactionRepository? transactionRepository;
  final MonthlyReportRepository? monthlyReportRepository;
  final LiveSessionRepository? liveSessionRepository;
  final OrderRepository? orderRepository;
  @override
  State<MonthDetailPage> createState() => _MonthDetailPageState();
}

class _MonthDetailPageState extends State<MonthDetailPage> {
  final _search = TextEditingController();
  final _horizontalTableController = ScrollController();
  late final TransactionRepository _transactions;
  late final LiveSessionRepository _sessions;
  late final MonthlyReportRepository _monthlyReports;
  late final OrderRepository _orders;
  List<TransactionWithOrder> _items = [];
  List<LiveSession> _liveSessions = [];
  int? _sessionId;
  PaymentStatus? _paymentStatus;
  OrderStatus? _orderStatus;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _sessions = widget.liveSessionRepository ?? LiveSessionRepository(AppDatabase.instance);
    _monthlyReports = widget.monthlyReportRepository ?? MonthlyReportRepository(AppDatabase.instance);
    _orders = widget.orderRepository ?? OrderRepository(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _transactions.listItemsJoined(
        search: _search.text,
        liveSessionId: _sessionId,
        paymentStatus: _paymentStatus,
        orderStatus: _orderStatus,
        periodStart: widget.month.start,
        periodEnd: widget.month.end,
      ),
      _sessions.listSessions(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<TransactionWithOrder>;
      _liveSessions = results[1] as List<LiveSession>;
      _loading = false;
    });
  }

  List<_OrderGroup> get _groups {
    final map = <String, _OrderGroup>{};
    for (final v in _items) {
      final key = '${v.order.accountId}::${v.order.orderId}';
      map.putIfAbsent(key, () => _OrderGroup(order: v.order, items: [])).items.add(v);
    }
    final list = map.values.toList();
    for (final g in list) {
      g.items.sort((a, b) => a.item.itemIndex.compareTo(b.item.itemIndex));
    }
    return list;
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _sessionId = null;
      _paymentStatus = null;
      _orderStatus = null;
    });
    _load();
  }

  Future<void> _copyOrderId(String orderId) async {
    try {
      await Clipboard.setData(ClipboardData(text: orderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ID Pesanan disalin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyalin ID Pesanan.')),
      );
    }
  }

  Future<void> _editItem(Transaction item) async {
    final updated = await showDialog<Transaction>(
      context: context,
      builder: (_) => _ItemEditDialog(item: item),
    );
    if (updated == null) return;
    try {
      await _transactions.updateItem(updated);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item diperbarui.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui item.')));
    }
  }

  Future<void> _editOrder(Order order) async {
    final updated = await showDialog<Order>(
      context: context,
      builder: (_) => _OrderEditDialog(order: order, sessions: _liveSessions),
    );
    if (updated == null) return;
    try {
      await _orders.update(updated);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order diperbarui.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui order.')));
    }
  }

  Future<void> _deleteItem(Transaction item) async {
    final id = item.id;
    if (id == null) return;
    final siblingsCount = _items.where((v) => v.order.id == item.orderFk).length;
    final lastOne = siblingsCount <= 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(lastOne ? 'Hapus order?' : 'Hapus item?'),
        content: Text(lastOne
            ? 'Item ini adalah item terakhir pada order ini. Menghapusnya juga akan menghapus order "${item.orderId}".'
            : 'Item "${item.productCode}" akan dihapus permanen dari order "${item.orderId}". Item lain pada order ini tidak terpengaruh.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('BATAL')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('HAPUS')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _transactions.deleteItem(id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item dihapus.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus item.')));
    }
  }

  Future<void> _submitReport() async {
    // Submit Report is intentionally independent of UI search / filters.
    final all = await _transactions.listItemsJoined(
      periodStart: widget.month.start,
      periodEnd: widget.month.end,
    );
    final totals = ReportTotals.fromJoined(all);
    await _monthlyReports.save(MonthlyReport(
      year: widget.month.year,
      month: widget.month.month,
      periodStart: widget.month.start,
      periodEnd: widget.month.end,
      gmvTotal: totals.gmv,
      netIncomeTotal: totals.netIncome,
      hppTotal: totals.hpp,
      profitTotal: totals.profit,
      submittedAt: DateTime.now(),
    ));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report bulanan berhasil disimpan.')));
  }

  @override
  void dispose() {
    _search.dispose();
    _horizontalTableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Reports — ${widget.month.label}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.month.periodLabel),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: (_) => _load(),
                  decoration: const InputDecoration(labelText: 'Cari ID Pesanan atau Kode Barang', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _filter<int?>('Live Session', _sessionId, [
                    const DropdownMenuItem(value: null, child: Text('SEMUA')),
                    ..._liveSessions.map((session) => DropdownMenuItem(value: session.id, child: SizedBox(width: 180, child: Text(session.name, maxLines: 1, overflow: TextOverflow.ellipsis)))),
                  ], (value) { setState(() => _sessionId = value); _load(); }),
                  _filter<PaymentStatus?>('Status Pembayaran', _paymentStatus, [
                    const DropdownMenuItem(value: null, child: Text('SEMUA')),
                    ...PaymentStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))),
                  ], (value) { setState(() => _paymentStatus = value); _load(); }),
                  _filter<OrderStatus?>('Status Pesanan', _orderStatus, [
                    const DropdownMenuItem(value: null, child: Text('SEMUA')),
                    ...OrderStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))),
                  ], (value) { setState(() => _orderStatus = value); _load(); }),
                  OutlinedButton(onPressed: _clearFilters, child: const Text('RESET')),
                  FilledButton(onPressed: _submitReport, child: const Text('SUBMIT REPORT')),
                ]),
                const SizedBox(height: 16),
                Expanded(
                  child: Scrollbar(
                    controller: _horizontalTableController,
                    thumbVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _horizontalTableController,
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('No')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Harga Jual')),
                          DataColumn(label: Text('GMV')),
                          DataColumn(label: Text('Kode Barang')),
                          DataColumn(label: Text('ID Pesanan')),
                          DataColumn(label: Text('Keterangan')),
                          DataColumn(label: Text('Dibayar Tanggal')),
                          DataColumn(label: Text('Income')),
                          DataColumn(label: Text('HPP')),
                          DataColumn(label: Text('Profit')),
                          DataColumn(label: Text('Status Pembayaran')),
                          DataColumn(label: Text('Status Pesanan')),
                          DataColumn(label: Text('Action')),
                        ],
                        rows: _buildRows(context),
                      ),
                    ),
                  ),
                ),
                const _Footer(),
              ]),
      ),
    );
  }

  List<DataRow> _buildRows(BuildContext context) {
    final rows = <DataRow>[];
    final groups = _groups;
    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      for (var i = 0; i < group.items.length; i++) {
        rows.add(_dataRowFor(group, i, g + 1));
      }
    }
    rows.add(_totalDataRow(context));
    return rows;
  }

  DataRow _dataRowFor(_OrderGroup group, int itemIndex, int groupNumber) {
    final v = group.items[itemIndex];
    final isFirst = itemIndex == 0;
    final order = group.order;
    final item = v.item;
    final hppTotal = item.hppUnitAmount * item.quantity;
    final profit = item.netIncomeAmount - hppTotal;
    return DataRow(cells: [
      DataCell(Text(isFirst ? '$groupNumber' : '')),
      DataCell(Text('${item.quantity}')),
      DataCell(Text(Rupiah.format(item.unitPrice))),
      DataCell(Text(Rupiah.format(item.gmvAmount))),
      DataCell(Text(item.productCode)),
      DataCell(isFirst
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Text(order.orderId),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy ID Pesanan',
                visualDensity: VisualDensity.compact,
                onPressed: () => _copyOrderId(order.orderId),
              ),
            ])
          : const Text('')),
      DataCell(Text(isFirst ? (order.paymentDescription ?? '-') : '')),
      DataCell(Text(isFirst ? _formatPaidAt(order.paidAt) : '')),
      DataCell(Text(Rupiah.format(item.netIncomeAmount))),
      DataCell(Text(Rupiah.format(hppTotal))),
      DataCell(Text(Rupiah.format(profit))),
      DataCell(Text(isFirst ? order.paymentStatus.label : '')),
      DataCell(Text(isFirst ? order.orderStatus.label : '')),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        if (isFirst) TextButton(onPressed: () => _editOrder(order), child: const Text('Edit Order')),
        TextButton(onPressed: () => _editItem(item), child: const Text('Edit Item')),
        TextButton(onPressed: () => _deleteItem(item), child: const Text('Delete')),
      ])),
    ]);
  }

  /// UI-only total row (M7-B). Every cell carries a stable ValueKey so widget
  /// tests can read the rendered value directly via `find.byKey` without
  /// walking the DataTable's internal widget tree (`TableRow` is not a stable
  /// surface for finders).
  DataRow _totalDataRow(BuildContext context) {
    var qty = 0, gmv = 0, income = 0, hpp = 0, profit = 0;
    for (final v in _items) {
      qty += v.item.quantity;
      gmv += v.item.gmvAmount;
      income += v.item.netIncomeAmount;
      final cost = v.item.hppUnitAmount * v.item.quantity;
      hpp += cost;
      profit += v.item.netIncomeAmount - cost;
    }
    final bold = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    return DataRow(
      color: WidgetStateProperty.all(bg),
      cells: [
        DataCell(Text('TOTAL', key: const ValueKey('__total__'), style: bold)),
        DataCell(Text('$qty', key: const ValueKey('__total_qty__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_harga__'), style: bold)),
        DataCell(Text(Rupiah.format(gmv), key: const ValueKey('__total_gmv__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_kode__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_order__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_keterangan__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_dibayar__'), style: bold)),
        DataCell(Text(Rupiah.format(income), key: const ValueKey('__total_income__'), style: bold)),
        DataCell(Text(Rupiah.format(hpp), key: const ValueKey('__total_hpp__'), style: bold)),
        DataCell(Text(Rupiah.format(profit), key: const ValueKey('__total_profit__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_status_bayar__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_status_pesan__'), style: bold)),
        DataCell(Text('', key: const ValueKey('__total_action__'), style: bold)),
      ],
    );
  }

  String _formatPaidAt(DateTime? paidAt) {
    if (paidAt == null) return '-';
    final local = paidAt.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }

  Widget _filter<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> changed) => SizedBox(
        width: 220,
        child: DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: items,
          onChanged: changed,
        ),
      );
}

class _ItemEditDialog extends StatefulWidget {
  const _ItemEditDialog({required this.item});
  final Transaction item;
  @override
  State<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<_ItemEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _product;
  late final TextEditingController _qty;
  late final TextEditingController _unitPrice;
  late final TextEditingController _income;

  @override
  void initState() {
    super.initState();
    _product = TextEditingController(text: widget.item.productCode);
    _qty = TextEditingController(text: '${widget.item.quantity}');
    _unitPrice = TextEditingController(text: widget.item.unitPrice > 0 ? '${widget.item.unitPrice}' : '');
    _income = TextEditingController(text: '${widget.item.netIncomeAmount}');
    _unitPrice.addListener(_refresh);
    _qty.addListener(_refresh);
    _income.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int get _qtyValue => int.tryParse(_qty.text) ?? 0;
  int get _unitPriceValue => Rupiah.parse(_unitPrice.text) ?? 0;
  int get _incomeValue => Rupiah.parse(_income.text) ?? 0;
  int get _gmvValue => _unitPriceValue * _qtyValue;
  int get _hppUnit => widget.item.hppUnitAmount;
  int get _profitValue => _incomeValue - (_hppUnit * _qtyValue);

  void _save() {
    final unitPrice = Rupiah.parse(_unitPrice.text);
    final income = Rupiah.parse(_income.text);
    if (!(_form.currentState?.validate() ?? false) ||
        TransactionValidator.unitPrice(unitPrice) != null ||
        TransactionValidator.rupiah(income, 'Income') != null) {
      return;
    }
    final qty = int.parse(_qty.text);
    Navigator.pop(
      context,
      widget.item.copyWith(
        productCode: _product.text.trim(),
        quantity: qty,
        unitPrice: unitPrice,
        gmvAmount: unitPrice! * qty,
        netIncomeAmount: income,
      ),
    );
  }

  @override
  void dispose() {
    _unitPrice.removeListener(_refresh);
    _qty.removeListener(_refresh);
    _income.removeListener(_refresh);
    _product.dispose();
    _qty.dispose();
    _unitPrice.dispose();
    _income.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Item'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _product, validator: TransactionValidator.productCode, decoration: const InputDecoration(labelText: 'Kode Barang')),
                _field(_qty, 'Qty', TransactionValidator.quantity),
                _field(_unitPrice, 'Harga Jual', (v) => TransactionValidator.unitPrice(Rupiah.parse(v ?? ''))),
                _readOnly('GMV', Rupiah.format(_gmvValue)),
                _field(_income, 'Income', (v) => TransactionValidator.rupiah(Rupiah.parse(v ?? ''), 'Income')),
                _readOnly('HPP', Rupiah.format(_hppUnit)),
                _readOnly('Profit', Rupiah.format(_profitValue)),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          FilledButton(onPressed: _save, child: const Text('SIMPAN')),
        ],
      );

  Widget _field(TextEditingController c, String label, String? Function(String?)? v) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(controller: c, validator: v, decoration: InputDecoration(labelText: label)),
      );

  Widget _readOnly(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: InputDecorator(decoration: InputDecoration(labelText: label), child: Text(value)),
      );
}

class _OrderEditDialog extends StatefulWidget {
  const _OrderEditDialog({required this.order, required this.sessions});
  final Order order;
  final List<LiveSession> sessions;
  @override
  State<_OrderEditDialog> createState() => _OrderEditDialogState();
}

class _OrderEditDialogState extends State<_OrderEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _orderId;
  late final TextEditingController _description;
  late final TextEditingController _compensation;
  late int? _sessionId;
  late PaymentStatus _payment;
  late OrderStatus _orderStatus;
  late DateTime _transactionDate;
  DateTime? _paidAt;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _orderId = TextEditingController(text: o.orderId);
    _description = TextEditingController(text: o.paymentDescription ?? '');
    _compensation = TextEditingController(text: o.returnShippingCompensation > 0 ? '${o.returnShippingCompensation}' : '');
    _sessionId = o.liveSessionId;
    _payment = o.paymentStatus;
    _orderStatus = o.orderStatus;
    _transactionDate = DateTime(o.transactionDate.year, o.transactionDate.month, o.transactionDate.day);
    _paidAt = o.paidAt;
  }

  Future<void> _pickTransactionDate() async {
    final v = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _transactionDate);
    if (v != null && mounted) setState(() => _transactionDate = DateTime(v.year, v.month, v.day));
  }

  Future<void> _pickPaidAt() async {
    final v = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _paidAt ?? DateTime.now());
    if (v != null && mounted) setState(() => _paidAt = v);
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final comp = Rupiah.parse(_compensation.text) ?? 0;
    if (TransactionValidator.returnShippingCompensation(comp) != null) return;
    Navigator.pop(
      context,
      widget.order.copyWith(
        orderId: _orderId.text.trim(),
        liveSessionId: _sessionId,
        transactionDate: _transactionDate,
        paymentStatus: _payment,
        orderStatus: _orderStatus,
        paidAt: TransactionValidator.normalizePaidAt(_payment, _paidAt),
        returnShippingCompensation: comp,
        paymentDescription: _description.text.trim().isEmpty ? null : _description.text.trim(),
      ),
    );
  }

  @override
  void dispose() {
    _orderId.dispose();
    _description.dispose();
    _compensation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Order'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _orderId, validator: TransactionValidator.orderId, decoration: const InputDecoration(labelText: 'ID Pesanan')),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: DropdownButtonFormField<int>(
                    initialValue: _sessionId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Live Session'),
                    items: widget.sessions.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                    onChanged: (v) => setState(() => _sessionId = v),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Transaksi'),
                  subtitle: Text('${_transactionDate.day}/${_transactionDate.month}/${_transactionDate.year}'),
                  trailing: OutlinedButton(onPressed: _pickTransactionDate, child: const Text('PILIH')),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: DropdownButtonFormField<PaymentStatus>(
                    initialValue: _payment,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status Pembayaran'),
                    items: PaymentStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() { _payment = v; if (v != PaymentStatus.paid) _paidAt = null; });
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Dibayar'),
                  subtitle: Text(_paidAt == null ? 'Belum dipilih' : '${_paidAt!.day}/${_paidAt!.month}/${_paidAt!.year}'),
                  trailing: OutlinedButton(onPressed: _payment == PaymentStatus.paid ? _pickPaidAt : null, child: const Text('PILIH')),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: DropdownButtonFormField<OrderStatus>(
                    initialValue: _orderStatus,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status Pesanan'),
                    items: OrderStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                    onChanged: (v) { if (v != null) setState(() => _orderStatus = v); },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(
                    controller: _compensation,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Kompensasi Ongkir Retur (Rp)'),
                    validator: (v) => TransactionValidator.returnShippingCompensation(Rupiah.parse(v ?? '')),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Keterangan Pembayaran')),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          FilledButton(onPressed: _save, child: const Text('SIMPAN')),
        ],
      );
}