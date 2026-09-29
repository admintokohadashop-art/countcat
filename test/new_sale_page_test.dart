import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/hpp_master.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/hpp_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/sales/new_sale_page.dart';

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<List<Account>> listAccounts() async => const [];
  @override
  Future<Account?> activeAccount() async {
    final now = DateTime(2026);
    return Account(id: 1, name: 'Main', description: '', createdAt: now, updatedAt: now);
  }
  @override
  Future<void> setActiveAccountId(int? id) async {}
  @override
  Future<Account> create({required String name, String description = '', String? photoPath}) async => throw UnimplementedError();
  @override
  Future<void> update(Account account) async {}
  @override
  Future<void> delete(Account account) async {}
}

class _FakeLiveSessionRepository implements LiveSessionRepository {
  @override
  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async => throw UnimplementedError();
  @override
  Future<List<LiveSession>> listSessions() async => const [];
  @override
  Future<int?> getSelectedSessionId() async => null;
  @override
  Future<void> setSelectedSessionId(int? sessionId) async {}
  @override
  Future<LiveSession?> getSelectedSession() async => null;
  @override
  Future<void> updateSession({required int id, required String name, required DateTime startedAt}) async {}
  @override
  Future<bool> hasTransactions(int sessionId) async => false;
  @override
  Future<void> deleteSession(int sessionId) async {}
}

class _FakeHppRepository implements HppRepository {
  _FakeHppRepository(this._items);
  final List<HppMaster> _items;
  @override
  Future<List<HppMaster>> list(int accountId, {bool activeOnly = true}) async => _items;
  @override
  Future<HppMaster?> find(int? id) async {
    for (final h in _items) {
      if (h.id == id) return h;
    }
    return null;
  }
  @override
  Future<HppMaster> create({required int accountId, required String name, required int unitAmount}) async => throw UnimplementedError();
  @override
  Future<void> update(HppMaster h) async {}
  @override
  Future<void> deactivate(int id, int accountId) async {}
}

class _FakeTransactionRepository implements TransactionRepository {
  @override
  Future<int> insertTransaction(Transaction transaction) async => 1;
  @override
  Future<List<Transaction>> listTransactions({String search = '', int? liveSessionId, PaymentStatus? paymentStatus, OrderStatus? orderStatus, DateTime? periodStart, DateTime? periodEnd}) async => const [];
  @override
  Future<void> deleteTransaction(int id) async {}
  @override
  Future<void> updateTransaction(Transaction transaction) async {}
  @override
  Future<List<TransactionWithOrder>> listItemsJoined({String search = '', int? liveSessionId, PaymentStatus? paymentStatus, OrderStatus? orderStatus, DateTime? periodStart, DateTime? periodEnd}) async => const [];
  @override
  Future<void> updateItem(Transaction item) async {}
  @override
  Future<void> deleteItem(int id) async {}
}

class _FakeOrderRepository implements OrderRepository {
  Order? lastOrder;
  List<Transaction> lastItems = const [];

  @override
  Future<int> createWithItems(Order order, List<Transaction> items) async {
    lastOrder = order;
    lastItems = List.unmodifiable(items);
    return 1;
  }
  @override
  Future<int> create(Order order) async => 1;
  @override
  Future<Order?> get(int id) async => null;
  @override
  Future<List<Order>> list({int? liveSessionId, DateTime? periodStart, DateTime? periodEnd, String search = ''}) async => const [];
  @override
  Future<void> update(Order order) async {}
  @override
  Future<void> delete(int id) async {}
}

HppMaster _hpp({int id = 10, int amount = 20000, String name = 'Cardigan'}) {
  final now = DateTime(2026);
  return HppMaster(id: id, accountId: 1, name: name, unitAmount: amount, isActive: true, createdAt: now, updatedAt: now);
}

Future<_FakeOrderRepository> _pumpPage(
  WidgetTester tester, {
  required _FakeHppRepository hppRepo,
}) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final orderRepo = _FakeOrderRepository();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: NewSalePage(
        accountRepository: _FakeAccountRepository(),
        liveSessionRepository: _FakeLiveSessionRepository(),
        hppRepository: hppRepo,
        transactionRepository: _FakeTransactionRepository(),
        orderRepository: orderRepo,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
  return orderRepo;
}

Future<void> _enter(WidgetTester tester, String label, String text, {int index = 0}) async {
  final fields = find.widgetWithText(TextFormField, label);
  await tester.enterText(fields.at(index), text);
  await tester.pump();
}

Future<void> _selectItemHpp(WidgetTester tester, int itemIndex, int hppId) async {
  final hppDropdowns = find.ancestor(
    of: find.text('HPP'),
    matching: find.byType(DropdownButtonFormField<int>),
  );
  final state = tester.state<FormFieldState<int>>(hppDropdowns.at(itemIndex));
  state.didChange(hppId);
  await tester.pump();
}

Future<void> _selectPayment(WidgetTester tester, PaymentStatus status) async {
  final finder = find
      .ancestor(of: find.text('Status Pembayaran'), matching: find.byType(DropdownButtonFormField<PaymentStatus>))
      .first;
  final state = tester.state<FormFieldState<PaymentStatus>>(finder);
  state.didChange(status);
  await tester.pump();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('SUBMIT'));
  await tester.pump();
  await tester.tap(find.text('SUBMIT'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Finder _readOnlyField(String label) =>
    find.byWidgetPredicate((w) => w is InputDecorator && w.decoration.labelText == label);

Finder _textFormFieldByLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));

/// Fills a fully-populated item block at [index].
Future<void> _fillItem(
  WidgetTester tester,
  int index, {
  required String productCode,
  required String qty,
  required String unitPrice,
  required String income,
  required int hppId,
}) async {
  await _enter(tester, 'Kode Barang', productCode, index: index);
  await _enter(tester, 'Qty', qty, index: index);
  await _enter(tester, 'Harga Jual', unitPrice, index: index);
  await _enter(tester, 'Income', income, index: index);
  await _selectItemHpp(tester, index, hppId);
}

Future<void> _tapAddItem(WidgetTester tester) async {
  await tester.ensureVisible(find.text('TAMBAH BARANG'));
  await tester.pump();
  await tester.tap(find.text('TAMBAH BARANG'));
  await tester.pump();
}

void main() {
  testWidgets('starts with exactly one item block', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsNothing);
    expect(find.text('TAMBAH BARANG'), findsOneWidget);
  });

  testWidgets('+ TAMBAH BARANG adds a second empty item block', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _enter(tester, 'Kode Barang', 'A');
    await _tapAddItem(tester);
    expect(find.text('ITEM 2'), findsOneWidget);
    final productFields = find.widgetWithText(TextFormField, 'Kode Barang');
    final controllers = tester.widgetList<TextFormField>(productFields).map((f) => f.controller?.text).toList();
    expect(controllers[0], 'A');
    expect(controllers[1], isEmpty);
  });

  testWidgets('adding three items produces ITEM 1..3 blocks', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _tapAddItem(tester);
    await _tapAddItem(tester);
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsOneWidget);
    expect(find.text('ITEM 3'), findsOneWidget);
  });

  testWidgets('GMV and Profit are computed independently per item', (tester) async {
    await _pumpPage(
      tester,
      hppRepo: _FakeHppRepository([_hpp(id: 10, amount: 20000), _hpp(id: 11, amount: 25000, name: 'Blouse')]),
    );
    await _fillItem(tester, 0, productCode: 'A', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _tapAddItem(tester);
    await _fillItem(tester, 1, productCode: 'B', qty: '1', unitPrice: '30000', income: '20000', hppId: 11);
    expect(find.text('Rp100.000'), findsOneWidget);
    expect(find.text('Rp30.000'), findsOneWidget);
    expect(find.text('Rp6.000'), findsOneWidget);
    expect(find.text('Rp-5.000'), findsOneWidget);
  });

  testWidgets('submit with incomplete second item shows item-specific error', (tester) async {
    final orderRepo = await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _fillItem(tester, 0, productCode: 'SKU', qty: '1', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _tapAddItem(tester);
    await _submit(tester);
    expect(find.text('Item 2 tidak lengkap.'), findsOneWidget);
    expect(orderRepo.lastItems, isEmpty);
  });

  testWidgets('one-item submit stores unitPrice and derived gmvAmount on the item', (tester) async {
    final orderRepo = await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp(amount: 20000)]));
    await _fillItem(tester, 0, productCode: 'SKU', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _submit(tester);
    expect(orderRepo.lastOrder, isNotNull);
    expect(orderRepo.lastOrder!.orderId, 'ORD');
    expect(orderRepo.lastItems, hasLength(1));
    final item = orderRepo.lastItems.single;
    expect(item.unitPrice, 50000);
    expect(item.quantity, 2);
    expect(item.gmvAmount, 100000);
    expect(item.netIncomeAmount, 46000);
    expect(item.hppUnitAmount, 20000);
  });

  testWidgets('two-item submit produces two items on the same order', (tester) async {
    final orderRepo = await _pumpPage(
      tester,
      hppRepo: _FakeHppRepository([_hpp(id: 10, amount: 20000), _hpp(id: 11, amount: 25000, name: 'Blouse')]),
    );
    await _fillItem(tester, 0, productCode: 'A', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD-MULTI');
    await _tapAddItem(tester);
    await _fillItem(tester, 1, productCode: 'B', qty: '1', unitPrice: '80000', income: '75000', hppId: 11);
    await _submit(tester);
    expect(orderRepo.lastOrder, isNotNull);
    expect(orderRepo.lastOrder!.orderId, 'ORD-MULTI');
    expect(orderRepo.lastItems, hasLength(2));
    expect(orderRepo.lastItems[0].productCode, 'A');
    expect(orderRepo.lastItems[0].unitPrice, 50000);
    expect(orderRepo.lastItems[0].hppUnitAmount, 20000);
    expect(orderRepo.lastItems[1].productCode, 'B');
    expect(orderRepo.lastItems[1].unitPrice, 80000);
    expect(orderRepo.lastItems[1].hppUnitAmount, 25000);
  });

  testWidgets('Tanggal Transaksi is stored on the order', (tester) async {
    final orderRepo = await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _fillItem(tester, 0, productCode: 'SKU', qty: '1', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _submit(tester);
    final now = DateTime.now();
    final order = orderRepo.lastOrder!;
    expect(order.transactionDate.year, now.year);
    expect(order.transactionDate.month, now.month);
    expect(order.transactionDate.day, now.day);
  });

  testWidgets('missing HPP on the first item blocks submit', (tester) async {
    final orderRepo = await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '1');
    await _enter(tester, 'Harga Jual', '50000');
    await _enter(tester, 'Income', '46000');
    await _submit(tester);
    expect(orderRepo.lastItems, isEmpty);
    expect(find.text('HPP wajib dipilih.'), findsWidgets);
  });

  testWidgets('paid-date button is disabled for pending and enabled for paid', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    final pilihFinder = find.widgetWithText(OutlinedButton, 'PILIH').last;
    expect(pilihFinder, findsOneWidget);
    var button = tester.widget<OutlinedButton>(pilihFinder);
    expect(button.onPressed, isNull);
    await _selectPayment(tester, PaymentStatus.paid);
    button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'PILIH').last);
    expect(button.onPressed, isNotNull);
  });

  // ─────────── reset behavior regression suite ───────────

  testWidgets('one-item successful submit resets to a single empty item', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _fillItem(tester, 0, productCode: 'SKU', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsNothing);
    await _submit(tester);
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsNothing);
    final unitPriceField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Harga Jual').first);
    expect(unitPriceField.controller?.text, isEmpty);
  });

  testWidgets('two-item successful submit resets to a single empty item', (tester) async {
    await _pumpPage(
      tester,
      hppRepo: _FakeHppRepository([_hpp(id: 10, amount: 20000), _hpp(id: 11, amount: 25000, name: 'Blouse')]),
    );
    await _fillItem(tester, 0, productCode: 'A', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _tapAddItem(tester);
    await _fillItem(tester, 1, productCode: 'B', qty: '1', unitPrice: '80000', income: '75000', hppId: 11);
    expect(find.text('ITEM 2'), findsOneWidget);
    await _submit(tester);
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsNothing);
    final unitPriceField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Harga Jual').first);
    expect(unitPriceField.controller?.text, isEmpty);
  });

  testWidgets('three-item successful submit resets to a single empty item', (tester) async {
    await _pumpPage(
      tester,
      hppRepo: _FakeHppRepository([
        _hpp(id: 10, amount: 20000),
        _hpp(id: 11, amount: 25000, name: 'Blouse'),
        _hpp(id: 12, amount: 30000, name: 'Dress'),
      ]),
    );
    await _fillItem(tester, 0, productCode: 'A', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _tapAddItem(tester);
    await _fillItem(tester, 1, productCode: 'B', qty: '1', unitPrice: '80000', income: '75000', hppId: 11);
    await _tapAddItem(tester);
    await _fillItem(tester, 2, productCode: 'C', qty: '3', unitPrice: '30000', income: '25000', hppId: 12);
    expect(find.text('ITEM 3'), findsOneWidget);
    await _submit(tester);
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsNothing);
    expect(find.text('ITEM 3'), findsNothing);
    final unitPriceField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Harga Jual').first);
    expect(unitPriceField.controller?.text, isEmpty);
  });

  testWidgets('failed submit does not reset the form or remove item blocks', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _fillItem(tester, 0, productCode: 'A', qty: '2', unitPrice: '50000', income: '46000', hppId: 10);
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _tapAddItem(tester);
    expect(find.text('ITEM 2'), findsOneWidget);
    // ITEM 2 is empty → submit must fail and MUST NOT reset.
    await _submit(tester);
    expect(find.text('Item 2 tidak lengkap.'), findsOneWidget);
    expect(find.text('ITEM 1'), findsOneWidget);
    expect(find.text('ITEM 2'), findsOneWidget);
    final productField = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Kode Barang').first);
    expect(productField.controller?.text, 'A');
  });

  testWidgets('unit price = 0 blocks submit and shows inline error on item 1', (tester) async {
    final orderRepo = await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    await _enter(tester, 'Kode Barang', 'SKU');
    await _enter(tester, 'ID Pesanan', 'ORD');
    await _enter(tester, 'Qty', '1');
    await _enter(tester, 'Harga Jual', '0');
    await _enter(tester, 'Income', '1000');
    await _selectItemHpp(tester, 0, 10);
    await _submit(tester);
    expect(orderRepo.lastItems, isEmpty);
    final hargaJualField = _textFormFieldByLabel('Harga Jual').first;
    expect(
      find.descendant(of: hargaJualField, matching: find.text('Harga Jual harus lebih dari 0.')),
      findsOneWidget,
    );
  });

  testWidgets('GMV read-only field contains no editable text', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    final gmvField = _readOnlyField('GMV');
    expect(gmvField, findsOneWidget);
    expect(find.descendant(of: gmvField, matching: find.byType(EditableText)), findsNothing);
  });

  testWidgets('Profit read-only field contains no editable text', (tester) async {
    await _pumpPage(tester, hppRepo: _FakeHppRepository([_hpp()]));
    final profitField = _readOnlyField('Profit');
    expect(profitField, findsOneWidget);
    expect(find.descendant(of: profitField, matching: find.byType(EditableText)), findsNothing);
  });
}