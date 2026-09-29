import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/hpp_master.dart';
import '../../data/models/live_session.dart';
import '../../data/models/order.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/hpp_repository.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transaction_validator.dart';

DateTime _todayLocalDate() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class NewSalePage extends StatefulWidget {
  const NewSalePage({
    super.key,
    this.accountRepository,
    this.liveSessionRepository,
    this.hppRepository,
    this.transactionRepository,
    this.orderRepository,
  });

  final AccountRepository? accountRepository;
  final LiveSessionRepository? liveSessionRepository;
  final HppRepository? hppRepository;

  /// Kept for backward compatibility with earlier milestones. The Phase D
  /// submission path goes through [orderRepository].
  final TransactionRepository? transactionRepository;
  final OrderRepository? orderRepository;

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

/// Per-item form state. Each item owns its own controllers and HPP selection.
class _ItemForm {
  _ItemForm({required VoidCallback onChanged})
      : product = TextEditingController(),
        qty = TextEditingController(),
        unitPrice = TextEditingController(),
        income = TextEditingController() {
    product.addListener(onChanged);
    qty.addListener(onChanged);
    unitPrice.addListener(onChanged);
    income.addListener(onChanged);
  }

  final TextEditingController product;
  final TextEditingController qty;
  final TextEditingController unitPrice;
  final TextEditingController income;
  int? hppId;

  int get qtyValue => int.tryParse(qty.text) ?? 0;
  int get unitPriceValue => Rupiah.parse(unitPrice.text) ?? 0;
  int get incomeValue => Rupiah.parse(income.text) ?? 0;
  int get gmvValue => unitPriceValue * qtyValue;
  int profitValue(int hppUnit) => incomeValue - (hppUnit * qtyValue);

  void clear() {
    product.clear();
    qty.clear();
    unitPrice.clear();
    income.clear();
    hppId = null;
  }

  void dispose() {
    product.dispose();
    qty.dispose();
    unitPrice.dispose();
    income.dispose();
  }
}

class _NewSalePageState extends State<NewSalePage> {
  final _orderFormKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _order = TextEditingController();
  final _description = TextEditingController();

  final List<_ItemForm> _items = [];
  final List<GlobalKey<FormState>> _itemKeys = [];

  late final LiveSessionRepository _sessions;
  late final HppRepository _hppRepo;
  late final AccountRepository _accounts;
  late final OrderRepository _orders;

  List<LiveSession> _availableSessions = [];
  List<HppMaster> _hppItems = [];
  int? _liveSessionId;
  var _payment = PaymentStatus.pending;
  var _orderStatus = OrderStatus.newOrder;
  DateTime _transactionDate = _todayLocalDate();
  DateTime? _paidAt;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _sessions = widget.liveSessionRepository ?? LiveSessionRepository(AppDatabase.instance);
    _hppRepo = widget.hppRepository ?? HppRepository(AppDatabase.instance);
    _accounts = widget.accountRepository ?? AccountRepository(AppDatabase.instance);
    _orders = widget.orderRepository ?? OrderRepository(AppDatabase.instance);
    _addItemInternal();
    _load();
  }

  void _addItemInternal() {
    _items.add(_ItemForm(onChanged: _refresh));
    _itemKeys.add(GlobalKey<FormState>());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _addItem() {
    setState(_addItemInternal);
  }

  Future<void> _load() async {
    final account = await _accounts.activeAccount();
    final sessions = await _sessions.listSessions();
    final hpp = account == null ? <HppMaster>[] : await _hppRepo.list(account.id!);
    var selected = await _sessions.getSelectedSessionId();
    if (!sessions.any((session) => session.id == selected)) {
      selected = sessions.isEmpty ? null : sessions.first.id;
    }
    if (selected != null) await _sessions.setSelectedSessionId(selected);
    if (!mounted) return;
    setState(() {
      _availableSessions = sessions;
      _hppItems = hpp;
      _liveSessionId = selected;
      _loading = false;
    });
  }

  HppMaster? _hppById(int? id) {
    if (id == null) return null;
    for (final h in _hppItems) {
      if (h.id == id) return h;
    }
    return null;
  }

  Future<void> _pickTransactionDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _transactionDate,
    );
    if (selected != null && mounted) {
      setState(() => _transactionDate = DateTime(selected.year, selected.month, selected.day));
    }
  }

  Future<void> _pickPaidDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _paidAt ?? DateTime.now(),
    );
    if (selected != null && mounted) setState(() => _paidAt = selected);
  }

  Future<void> _submit() async {
    final orderValid = _orderFormKey.currentState?.validate() ?? false;
    var firstInvalidItem = -1;
    for (var i = 0; i < _items.length; i++) {
      final ok = _itemKeys[i].currentState?.validate() ?? false;
      if (!ok && firstInvalidItem == -1) firstInvalidItem = i;
    }
    final paidError = TransactionValidator.paidAt(_payment, _paidAt);

    if (!orderValid || firstInvalidItem != -1 || paidError != null) {
      final message = !orderValid
          ? 'Periksa isian pada bagian atas.'
          : firstInvalidItem != -1
              ? 'Item ${firstInvalidItem + 1} tidak lengkap.'
              : paidError!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final txDate = DateTime(_transactionDate.year, _transactionDate.month, _transactionDate.day);
    final normalizedPaidAt = TransactionValidator.normalizePaidAt(_payment, _paidAt);
    final orderIdText = _order.text.trim();
    final description = _description.text.trim().isEmpty ? null : _description.text.trim();

    final items = <Transaction>[];
    for (final it in _items) {
      final hpp = _hppById(it.hppId)!;
      final qty = it.qtyValue;
      final unitPrice = it.unitPriceValue;
      items.add(Transaction(
        hppId: hpp.id,
        hppUnitAmount: hpp.unitAmount,
        unitPrice: unitPrice,
        transactionDate: txDate,
        productCode: it.product.text.trim(),
        orderId: orderIdText,
        quantity: qty,
        gmvAmount: unitPrice * qty,
        paymentDescription: description,
        paymentStatus: _payment,
        paidAt: normalizedPaidAt,
        netIncomeAmount: it.incomeValue,
        orderStatus: _orderStatus,
        createdAt: now,
        updatedAt: now,
      ));
    }

    final order = Order(
      accountId: 0,
      orderId: orderIdText,
      liveSessionId: _liveSessionId,
      transactionDate: txDate,
      paymentStatus: _payment,
      orderStatus: _orderStatus,
      paidAt: normalizedPaidAt,
      returnShippingCompensation: 0,
      paymentDescription: description,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await _orders.createWithItems(order, items);
      if (!mounted) return;
      // Reset to a fresh single-item form.
      _order.clear();
      _description.clear();
      if (_items.length > 1) {
        for (var i = 1; i < _items.length; i++) {
          _items[i].dispose();
        }
        _items.removeRange(1, _items.length);
        _itemKeys.removeRange(1, _itemKeys.length);
      }
      _items.first.clear();
      setState(() {
        _payment = PaymentStatus.pending;
        _orderStatus = OrderStatus.newOrder;
        _transactionDate = _todayLocalDate();
        _paidAt = null;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi berhasil disimpan.')));
    } on DuplicateOrderIdException {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID Pesanan sudah ada.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menyimpan transaksi.')));
      }
    }
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    _order.dispose();
    _description.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _orderFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New Sale', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _liveSessionId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Live Session', border: OutlineInputBorder()),
                items: _availableSessions.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (value) async {
                  setState(() => _liveSessionId = value);
                  await _sessions.setSelectedSessionId(value);
                },
              ),
              _control(ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tanggal Transaksi'),
                subtitle: Text('${_transactionDate.day}/${_transactionDate.month}/${_transactionDate.year}'),
                trailing: OutlinedButton(onPressed: _pickTransactionDate, child: const Text('PILIH')),
              )),
              _field(_order, 'ID Pesanan', TransactionValidator.orderId),
              const SizedBox(height: 8),
              for (var i = 0; i < _items.length; i++) _buildItemBlock(i),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('TAMBAH BARANG'),
                ),
              ),
              _field(_description, 'Keterangan Pembayaran', null),
              _control(DropdownButtonFormField<PaymentStatus>(
                initialValue: _payment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status Pembayaran', border: OutlineInputBorder()),
                items: PaymentStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _payment = value;
                    if (value != PaymentStatus.paid) _paidAt = null;
                  });
                },
              )),
              _control(ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tanggal Dibayar'),
                subtitle: Text(_paidAt == null ? 'Belum dipilih' : '${_paidAt!.day}/${_paidAt!.month}/${_paidAt!.year}'),
                trailing: OutlinedButton(onPressed: _payment == PaymentStatus.paid ? _pickPaidDate : null, child: const Text('PILIH')),
              )),
              _control(DropdownButtonFormField<OrderStatus>(
                initialValue: _orderStatus,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status Pesanan', border: OutlineInputBorder()),
                items: OrderStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _orderStatus = value);
                },
              )),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'MENYIMPAN...' : 'SUBMIT')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemBlock(int index) {
    final it = _items[index];
    final hpp = _hppById(it.hppId);
    final profit = hpp == null ? 0 : it.profitValue(hpp.unitAmount);
    return Form(
      key: _itemKeys[index],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('ITEM ${index + 1}', style: Theme.of(context).textTheme.titleMedium),
            ),
            const Expanded(child: Divider()),
          ]),
          _field(it.product, 'Kode Barang', TransactionValidator.productCode),
          _field(it.qty, 'Qty', TransactionValidator.quantity, number: true),
          _field(it.unitPrice, 'Harga Jual', (v) => TransactionValidator.unitPrice(Rupiah.parse(v ?? '')), number: true),
          _readOnlyValue('GMV', Rupiah.format(it.gmvValue)),
          _field(it.income, 'Income', (v) => TransactionValidator.rupiah(Rupiah.parse(v ?? ''), 'Income'), number: true),
          _control(DropdownButtonFormField<int>(
            initialValue: it.hppId,
            isExpanded: true,
            validator: (v) => v == null ? 'HPP wajib dipilih.' : null,
            decoration: const InputDecoration(labelText: 'HPP', border: OutlineInputBorder()),
            items: _hppItems.map((h) => DropdownMenuItem(value: h.id, child: Text('${h.name} — ${Rupiah.format(h.unitAmount)}'))).toList(),
            onChanged: (v) => setState(() => it.hppId = v),
          )),
          _readOnlyValue('Profit', Rupiah.format(profit)),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String? Function(String?)? validator, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: number ? TextInputType.number : null,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Widget _control(Widget child) => Padding(padding: const EdgeInsets.only(top: 16), child: child);

  Widget _readOnlyValue(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          child: Text(value),
        ),
      );
}