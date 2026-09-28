import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/live_session.dart';
import '../../data/models/monthly_report.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../data/repositories/monthly_report_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../sales/transaction_validator.dart';
import 'report_totals.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    this.transactionRepository,
    this.monthlyReportRepository,
    this.liveSessionRepository,
  });

  final TransactionRepository? transactionRepository;
  final MonthlyReportRepository? monthlyReportRepository;
  final LiveSessionRepository? liveSessionRepository;

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
      _transactions.listTransactions(),
      _monthlyReports.listReports(),
    ]);
    final months = <ReportMonth>{};
    for (final item in values[0] as List<Transaction>) {
      final date = item.transactionDate;
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

class MonthDetailPage extends StatefulWidget {
  const MonthDetailPage({
    required this.month,
    super.key,
    this.transactionRepository,
    this.monthlyReportRepository,
    this.liveSessionRepository,
  });
  final ReportMonth month;
  final TransactionRepository? transactionRepository;
  final MonthlyReportRepository? monthlyReportRepository;
  final LiveSessionRepository? liveSessionRepository;
  @override
  State<MonthDetailPage> createState() => _MonthDetailPageState();
}

class _MonthDetailPageState extends State<MonthDetailPage> {
  final _search = TextEditingController();
  final _horizontalTableController = ScrollController();
  late final TransactionRepository _transactions;
  late final LiveSessionRepository _sessions;
  late final MonthlyReportRepository _monthlyReports;
  List<Transaction> _items = [];
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
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _transactions.listTransactions(
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
      _items = results[0] as List<Transaction>;
      _liveSessions = results[1] as List<LiveSession>;
      _loading = false;
    });
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

  Future<void> _edit(Transaction transaction) async {
    final updated = await showDialog<Transaction>(context: context, builder: (_) => _TransactionEditDialog(transaction: transaction, sessions: _liveSessions));
    if (updated == null) return;
    try {
      await _transactions.updateTransaction(updated);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi diperbarui.')));
    } on DuplicateOrderIdException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID Pesanan sudah ada.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memperbarui transaksi.')));
    }
  }

  Future<void> _submitReport() async {
    final all = await _transactions.listTransactions(periodStart: widget.month.start, periodEnd: widget.month.end);
    final totals = ReportTotals.fromTransactions(all);
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

  Future<void> _delete(Transaction item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi?'),
        content: Text('ID Pesanan: ${item.orderId}\nKode Barang: ${item.productCode}\nTransaksi akan dihapus permanen dan tidak lagi dihitung di total laporan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('BATAL')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('HAPUS')),
        ],
      ),
    );
    if (confirmed != true || item.id == null) return;
    await _transactions.deleteTransaction(item.id!);
    await _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _horizontalTableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totals = ReportTotals.fromTransactions(_items);
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
                _Totals(totals: totals),
                const SizedBox(height: 16),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('Tidak ada transaksi.'))
                      : Scrollbar(
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
                              rows: [for (var index = 0; index < _items.length; index++) _row(index, _items[index])],
                            ),
                          ),
                        ),
                ),
                const _Footer(),
              ]),
      ),
    );
  }

  DataRow _row(int index, Transaction item) {
    final hpp = item.hppUnitAmount * item.quantity;
    return DataRow(cells: [
      DataCell(Text('${index + 1}')),
      DataCell(Text('${item.quantity}')),
      DataCell(Text(Rupiah.format(item.unitPrice))),
      DataCell(Text(Rupiah.format(item.gmvAmount))),
      DataCell(Text(item.productCode)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        Text(item.orderId),
        IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'Copy ID Pesanan',
          visualDensity: VisualDensity.compact,
          onPressed: () => _copyOrderId(item.orderId),
        ),
      ])),
      DataCell(Text(item.paymentDescription ?? '-')),
      DataCell(Text(item.paidAt == null ? '-' : '${item.paidAt!.day}/${item.paidAt!.month}/${item.paidAt!.year}')),
      DataCell(Text(Rupiah.format(item.netIncomeAmount))),
      DataCell(Text(Rupiah.format(hpp))),
      DataCell(Text(Rupiah.format(item.netIncomeAmount - hpp))),
      DataCell(Text(item.paymentStatus.label)),
      DataCell(Text(item.orderStatus.label)),
      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton(onPressed: () => _edit(item), child: const Text('Edit')),
        TextButton(onPressed: () => _delete(item), child: const Text('Delete')),
      ])),
    ]);
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

class _Totals extends StatelessWidget {
  const _Totals({required this.totals});
  final ReportTotals totals;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 16, runSpacing: 8, children: [
        Text('Total GMV: ${Rupiah.format(totals.gmv)}'),
        Text('Total Income: ${Rupiah.format(totals.netIncome)}'),
        Text('Total HPP: ${Rupiah.format(totals.hpp)}'),
        Text('Total Profit: ${Rupiah.format(totals.profit)}'),
      ]);
}

class _TransactionEditDialog extends StatefulWidget {
  const _TransactionEditDialog({required this.transaction, required this.sessions});
  final Transaction transaction;
  final List<LiveSession> sessions;
  @override
  State<_TransactionEditDialog> createState() => _TransactionEditDialogState();
}

class _TransactionEditDialogState extends State<_TransactionEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _product;
  late final TextEditingController _order;
  late final TextEditingController _qty;
  late final TextEditingController _unitPrice;
  late final TextEditingController _description;
  late final TextEditingController _income;
  late int? _sessionId;
  late PaymentStatus _payment;
  late OrderStatus _orderStatus;
  late DateTime _transactionDate;
  DateTime? _paidAt;

  @override
  void initState() {
    super.initState();
    final item = widget.transaction;
    _product = TextEditingController(text: item.productCode);
    _order = TextEditingController(text: item.orderId);
    _qty = TextEditingController(text: '${item.quantity}');
    _unitPrice = TextEditingController(text: item.unitPrice > 0 ? '${item.unitPrice}' : '');
    _description = TextEditingController(text: item.paymentDescription ?? '');
    _income = TextEditingController(text: '${item.netIncomeAmount}');
    _sessionId = item.liveSessionId;
    _payment = item.paymentStatus;
    _orderStatus = item.orderStatus;
    _transactionDate = DateTime(item.transactionDate.year, item.transactionDate.month, item.transactionDate.day);
    _paidAt = item.paidAt;
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
  int get _hppUnitValue => widget.transaction.hppUnitAmount;
  int get _profitValue => _incomeValue - (_hppUnitValue * _qtyValue);

  Future<void> _pickTransactionDate() async {
    final value = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _transactionDate);
    if (value != null && mounted) setState(() => _transactionDate = DateTime(value.year, value.month, value.day));
  }

  Future<void> _date() async {
    final value = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _paidAt ?? DateTime.now());
    if (value != null && mounted) setState(() => _paidAt = value);
  }

  void _save() {
    final unitPrice = Rupiah.parse(_unitPrice.text);
    final income = Rupiah.parse(_income.text);
    if (!(_form.currentState?.validate() ?? false) ||
        TransactionValidator.unitPrice(unitPrice) != null ||
        TransactionValidator.rupiah(income, 'Income') != null ||
        TransactionValidator.paidAt(_payment, _paidAt) != null) {
      return;
    }
    final qty = int.parse(_qty.text);
    Navigator.pop(
      context,
      widget.transaction.copyWith(
        liveSessionId: _sessionId,
        transactionDate: _transactionDate,
        unitPrice: unitPrice,
        gmvAmount: unitPrice! * qty,
        productCode: _product.text.trim(),
        orderId: _order.text.trim(),
        quantity: qty,
        paymentDescription: _description.text.trim().isEmpty ? null : _description.text.trim(),
        paymentStatus: _payment,
        paidAt: TransactionValidator.normalizePaidAt(_payment, _paidAt),
        netIncomeAmount: income,
        orderStatus: _orderStatus,
      ),
    );
  }

  @override
  void dispose() {
    _unitPrice.removeListener(_refresh);
    _qty.removeListener(_refresh);
    _income.removeListener(_refresh);
    for (final controller in [_product, _order, _qty, _unitPrice, _description, _income]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Transaksi'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  initialValue: _sessionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Live Session'),
                  items: widget.sessions.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
                  onChanged: (value) => setState(() => _sessionId = value),
                ),
                _field(_product, 'Kode Barang', TransactionValidator.productCode),
                _field(_order, 'ID Pesanan', TransactionValidator.orderId),
                _field(_qty, 'Qty', TransactionValidator.quantity),
                _control(ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Transaksi'),
                  subtitle: Text('${_transactionDate.day}/${_transactionDate.month}/${_transactionDate.year}'),
                  trailing: OutlinedButton(onPressed: _pickTransactionDate, child: const Text('PILIH')),
                )),
                _field(_unitPrice, 'Harga Jual', (value) => TransactionValidator.unitPrice(Rupiah.parse(value ?? ''))),
                _readOnly('GMV', Rupiah.format(_gmvValue)),
                _field(_income, 'Income', (value) => TransactionValidator.rupiah(Rupiah.parse(value ?? ''), 'Income')),
                _readOnly('HPP', Rupiah.format(_hppUnitValue)),
                _readOnly('Profit', Rupiah.format(_profitValue)),
                _field(_description, 'Keterangan Pembayaran', null),
                _control(DropdownButtonFormField<PaymentStatus>(
                  initialValue: _payment,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status Pembayaran'),
                  items: PaymentStatus.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() { _payment = value; if (value != PaymentStatus.paid) _paidAt = null; });
                  },
                )),
                _control(ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Dibayar'),
                  subtitle: Text(_paidAt == null ? 'Belum dipilih' : '${_paidAt!.day}/${_paidAt!.month}/${_paidAt!.year}'),
                  trailing: OutlinedButton(onPressed: _payment == PaymentStatus.paid ? _date : null, child: const Text('PILIH')),
                )),
                _control(DropdownButtonFormField<OrderStatus>(
                  initialValue: _orderStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status Pesanan'),
                  items: OrderStatus.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                  onChanged: (value) { if (value != null) setState(() => _orderStatus = value); },
                )),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
          FilledButton(onPressed: _save, child: const Text('SIMPAN')),
        ],
      );

  Widget _field(TextEditingController controller, String label, String? Function(String?)? validator) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(controller: controller, validator: validator, decoration: InputDecoration(labelText: label)),
      );

  Widget _control(Widget child) => Padding(padding: const EdgeInsets.only(top: 16), child: child);

  Widget _readOnly(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: InputDecorator(decoration: InputDecoration(labelText: label), child: Text(value)),
      );
}