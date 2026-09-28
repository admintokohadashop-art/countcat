import 'package:flutter/material.dart';

import '../../core/currency/rupiah.dart';
import '../../data/database/app_database.dart';
import '../../data/models/live_session.dart';
import '../../data/models/hpp_master.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/hpp_repository.dart';
import '../../data/models/statuses.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/live_session_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import 'transaction_validator.dart';

class NewSalePage extends StatefulWidget {
  const NewSalePage({
    super.key,
    this.accountRepository,
    this.liveSessionRepository,
    this.hppRepository,
    this.transactionRepository,
  });

  final AccountRepository? accountRepository;
  final LiveSessionRepository? liveSessionRepository;
  final HppRepository? hppRepository;
  final TransactionRepository? transactionRepository;

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final _formKey = GlobalKey<FormState>();
  final _product = TextEditingController();
  final _order = TextEditingController();
  final _qty = TextEditingController();
  final _unitPrice = TextEditingController();
  final _description = TextEditingController();
  final _income = TextEditingController();

  late final LiveSessionRepository _sessions;
  late final HppRepository _hppRepo;
  late final AccountRepository _accounts;
  late final TransactionRepository _transactions;

  List<LiveSession> _availableSessions = [];
  List<HppMaster> _hppItems = [];
  int? _liveSessionId;
  int? _hppId;
  var _payment = PaymentStatus.pending;
  var _orderStatus = OrderStatus.newOrder;
  DateTime? _paidAt;
  var _loading = true;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _sessions = widget.liveSessionRepository ?? LiveSessionRepository(AppDatabase.instance);
    _hppRepo = widget.hppRepository ?? HppRepository(AppDatabase.instance);
    _accounts = widget.accountRepository ?? AccountRepository(AppDatabase.instance);
    _transactions = widget.transactionRepository ?? TransactionRepository(AppDatabase.instance);
    _unitPrice.addListener(_refresh);
    _qty.addListener(_refresh);
    _income.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
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

  int get _qtyValue => int.tryParse(_qty.text) ?? 0;
  int get _unitPriceValue => Rupiah.parse(_unitPrice.text) ?? 0;
  int get _incomeValue => Rupiah.parse(_income.text) ?? 0;
  int get _gmvValue => _unitPriceValue * _qtyValue;

  HppMaster? get _selectedHpp {
    for (final h in _hppItems) {
      if (h.id == _hppId) return h;
    }
    return null;
  }

  int get _profitValue {
    final hpp = _selectedHpp;
    if (hpp == null) return 0;
    return _incomeValue - (hpp.unitAmount * _qtyValue);
  }

  Future<void> _pickPaidDate() async {
    final selected = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDate: _paidAt ?? DateTime.now());
    if (selected != null && mounted) setState(() => _paidAt = selected);
  }

  Future<void> _submit() async {
    final unitPrice = Rupiah.parse(_unitPrice.text);
    final income = Rupiah.parse(_income.text);
    final paidError = TransactionValidator.paidAt(_payment, _paidAt);
    final unitPriceError = TransactionValidator.unitPrice(unitPrice);
    final selectedHpp = _selectedHpp;
    if (selectedHpp == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('HPP wajib dipilih.')));
      return;
    }
    final incomeError = TransactionValidator.rupiah(income, 'Income');
    if (!(_formKey.currentState?.validate() ?? false) || unitPriceError != null || incomeError != null || paidError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(unitPriceError ?? incomeError ?? paidError ?? 'Periksa isian.')));
      return;
    }
    setState(() => _saving = true);
    final qty = int.parse(_qty.text);
    final now = DateTime.now().toUtc();
    final transaction = Transaction(
      liveSessionId: _liveSessionId,
      hppId: selectedHpp.id,
      hppUnitAmount: selectedHpp.unitAmount,
      unitPrice: unitPrice!,
      productCode: _product.text.trim(),
      orderId: _order.text.trim(),
      quantity: qty,
      gmvAmount: unitPrice * qty,
      paymentDescription: _description.text.trim().isEmpty ? null : _description.text.trim(),
      paymentStatus: _payment,
      paidAt: TransactionValidator.normalizePaidAt(_payment, _paidAt),
      netIncomeAmount: income!,
      orderStatus: _orderStatus,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _transactions.insertTransaction(transaction);
      if (!mounted) return;
      _product.clear();
      _order.clear();
      _qty.clear();
      _unitPrice.clear();
      _description.clear();
      _income.clear();
      setState(() {
        _payment = PaymentStatus.pending;
        _orderStatus = OrderStatus.newOrder;
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
    _unitPrice.removeListener(_refresh);
    _qty.removeListener(_refresh);
    _income.removeListener(_refresh);
    for (final controller in [_product, _order, _qty, _unitPrice, _description, _income]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Form(
      key: _formKey,
      child: ListView(padding: const EdgeInsets.all(24), children: [
        Text('New Sale', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _liveSessionId,
          decoration: const InputDecoration(labelText: 'Live Session', border: OutlineInputBorder()),
          items: _availableSessions.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
          onChanged: (value) async {
            setState(() => _liveSessionId = value);
            await _sessions.setSelectedSessionId(value);
          },
        ),
        _field(_product, 'Kode Barang', TransactionValidator.productCode),
        _field(_order, 'ID Pesanan', TransactionValidator.orderId),
        _field(_qty, 'Qty', TransactionValidator.quantity, number: true),
        _field(_unitPrice, 'Harga Jual', (value) => TransactionValidator.unitPrice(Rupiah.parse(value ?? '')), number: true),
        _readOnlyValue('GMV', Rupiah.format(_gmvValue)),
        _field(_income, 'Income', (value) => TransactionValidator.rupiah(Rupiah.parse(value ?? ''), 'Income'), number: true),
        _control(DropdownButtonFormField<int>(
          initialValue: _hppId,
          validator: (v) => v == null ? 'HPP wajib dipilih.' : null,
          decoration: const InputDecoration(labelText: 'HPP', border: OutlineInputBorder()),
          items: _hppItems.map((h) => DropdownMenuItem(value: h.id, child: Text('${h.name} — ${Rupiah.format(h.unitAmount)}'))).toList(),
          onChanged: (v) => setState(() => _hppId = v),
        )),
        _readOnlyValue('Profit', Rupiah.format(_profitValue)),
        _field(_description, 'Keterangan Pembayaran', null),
        _control(DropdownButtonFormField<PaymentStatus>(
          initialValue: _payment,
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
          decoration: const InputDecoration(labelText: 'Status Pesanan', border: OutlineInputBorder()),
          items: OrderStatus.values.map((status) => DropdownMenuItem(value: status, child: Text(status.label))).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _orderStatus = value);
          },
        )),
        const SizedBox(height: 20),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'MENYIMPAN...' : 'SUBMIT')),
      ]),
    );
  }

  Widget _field(TextEditingController controller, String label, String? Function(String?)? validator, {bool number = false}) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TextFormField(controller: controller, validator: validator, keyboardType: number ? TextInputType.number : null, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
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