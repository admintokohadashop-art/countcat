import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/account.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/account_repository.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_page.dart';
import 'package:tiktok_seller/features/dashboard/dashboard_totals.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';
import 'package:tiktok_seller/features/sessions/live_sessions_page.dart';

Order _order({
  int? id,
  int accountId = 1,
  required String orderId,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  OrderStatus orderStatus = OrderStatus.closed,
  int compensation = 0,
  int? liveSessionId,
  DateTime? date,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Order(
    id: id,
    accountId: accountId,
    orderId: orderId,
    liveSessionId: liveSessionId,
    transactionDate: date ?? DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: paymentStatus == PaymentStatus.paid ? now : null,
    returnShippingCompensation: compensation,
    createdAt: now,
    updatedAt: now,
  );
}

Transaction _item({
  int? id,
  int? orderFk,
  int itemIndex = 0,
  String code = 'P',
  int qty = 1,
  int price = 1000,
  int hpp = 0,
  int? income,
  required String orderId,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Transaction(
    id: id,
    orderFk: orderFk,
    itemIndex: itemIndex,
    transactionDate: DateTime(2026, 9, 15),
    productCode: code,
    orderId: orderId,
    quantity: qty,
    unitPrice: price,
    gmvAmount: price * qty,
    hppUnitAmount: hpp,
    netIncomeAmount: income ?? price * qty,
    paymentStatus: PaymentStatus.paid,
    orderStatus: OrderStatus.closed,
    createdAt: now,
    updatedAt: now,
  );
}

TransactionWithOrder _join(Order order, Transaction item) =>
    TransactionWithOrder(item: item, order: order);

class _FakeTransactionRepository implements TransactionRepository {
  _FakeTransactionRepository(this._items);
  final List<TransactionWithOrder> _items;

  @override
  Future<List<TransactionWithOrder>> listItemsJoined({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    return _items.where((v) {
      if (periodStart != null && v.order.transactionDate.isBefore(periodStart)) return false;
      if (periodEnd != null && !v.order.transactionDate.isBefore(periodEnd)) return false;
      if (liveSessionId != null && v.order.liveSessionId != liveSessionId) return false;
      if (paymentStatus != null && v.order.paymentStatus != paymentStatus) return false;
      if (orderStatus != null && v.order.orderStatus != orderStatus) return false;
      if (search.isNotEmpty) {
        if (!v.order.orderId.contains(search) && !v.item.productCode.contains(search)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<int> insertTransaction(Transaction transaction) async => 1;

  @override
  Future<List<Transaction>> listTransactions({
    String search = '',
    int? liveSessionId,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async => const [];

  @override
  Future<void> deleteTransaction(int id) async {}

  @override
  Future<void> updateTransaction(Transaction transaction) async {}

  @override
  Future<void> updateItem(Transaction item) async {}

  @override
  Future<void> deleteItem(int id) async {}
}

class _FakeOrderRepository implements OrderRepository {
  _FakeOrderRepository(this._orders);
  final List<Order> _orders;
  final List<Order> updates = [];

  @override
  Future<int> create(Order order) async => 1;

  @override
  Future<int> createWithItems(Order order, List<Transaction> items) async => 1;

  @override
  Future<Order?> get(int id) async {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  Future<List<Order>> list({int? liveSessionId, DateTime? periodStart, DateTime? periodEnd, String search = ''}) async => _orders;

  @override
  Future<void> update(Order order) async {
    updates.add(order);
  }

  @override
  Future<void> delete(int id) async {}
}

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
  _FakeLiveSessionRepository([List<LiveSession>? initial])
      : _sessions = List.of(initial ?? const []);
  final List<LiveSession> _sessions;
  int? _selectedId;
  final List<LiveSession> updates = [];
  final List<int> deletions = [];
  bool? hasTransactionsResult;

  @override
  Future<LiveSession> createSession({required String name, DateTime? startedAt}) async {
    final s = LiveSession(
      id: _sessions.length + 1,
      name: name,
      startedAt: startedAt,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    _sessions.add(s);
    return s;
  }

  @override
  Future<List<LiveSession>> listSessions() async => List.of(_sessions);

  @override
  Future<int?> getSelectedSessionId() async => _selectedId;

  @override
  Future<void> setSelectedSessionId(int? sessionId) async {
    _selectedId = sessionId;
  }

  @override
  Future<LiveSession?> getSelectedSession() async {
    for (final s in _sessions) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  @override
  Future<void> updateSession({required int id, required String name, required DateTime startedAt}) async {
    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx >= 0) {
      updates.add(LiveSession(
        id: id,
        name: name,
        startedAt: startedAt,
        createdAt: _sessions[idx].createdAt,
        updatedAt: DateTime(2026),
      ));
    }
  }

  @override
  Future<bool> hasTransactions(int sessionId) async => hasTransactionsResult ?? false;

  @override
  Future<void> deleteSession(int sessionId) async {
    final used = await hasTransactions(sessionId);
    if (used) {
      throw SessionInUseException(sessionId, linkedOrderCount: 1);
    }
    _sessions.removeWhere((s) => s.id == sessionId);
    deletions.add(sessionId);
  }
}

LiveSession _session({int id = 1, String name = 'S', DateTime? startedAt}) => LiveSession(
      id: id,
      name: name,
      startedAt: startedAt ?? DateTime(2026, 9, 15, 19),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('Returns — order-level', () {
    testWidgets('one returned order with multiple items shows one card', (tester) async {
      tester.view.physicalSize = const Size(1600, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final order = _order(id: 1, orderId: 'ORD-R', orderStatus: OrderStatus.returned, compensation: 10000);
      final tx = _FakeTransactionRepository([
        _join(order, _item(orderFk: 1, orderId: 'ORD-R', itemIndex: 0, code: 'A', qty: 2)),
        _join(order, _item(orderFk: 1, orderId: 'ORD-R', itemIndex: 1, code: 'B', qty: 3)),
        _join(order, _item(orderFk: 1, orderId: 'ORD-R', itemIndex: 2, code: 'C', qty: 1)),
      ]);
      final orders = _FakeOrderRepository([order]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ReturnsPage(transactionRepository: tx, orderRepository: orders)),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('ID Pesanan: ORD-R'), findsOneWidget);
      expect(find.text('Total Qty Retur: 6'), findsOneWidget);
      expect(find.textContaining('Kompensasi: Rp10.000'), findsOneWidget);
      expect(find.text('Total Paket Retur: 1'), findsOneWidget);
      expect(find.text('Total Barang Retur: 6 barang'), findsOneWidget);
    });
  });

  group('Dashboard — multi-item', () {
    testWidgets('multi-item order sums items not orders', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final order = _order(id: 1, orderId: 'ORD-D');
      final tx = _FakeTransactionRepository([
        _join(order, _item(orderFk: 1, orderId: 'ORD-D', qty: 2, price: 50000, hpp: 20000, income: 80000)),
        _join(order, _item(orderFk: 1, orderId: 'ORD-D', itemIndex: 1, qty: 3, price: 30000, hpp: 10000, income: 70000)),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: DashboardPage(repository: _FakeAccountRepository(), transactionRepository: tx)),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('Barang Terjual'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Rp190.000'), findsOneWidget);
      expect(find.text('Rp150.000'), findsOneWidget);
      expect(find.text('Rp80.000'), findsOneWidget);
    });
  });

  group('Live Session edit/delete/search', () {
    testWidgets('edit session with valid name and startedAt updates session', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([_session(id: 1, name: 'Old')]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Edit Session').first);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Nama Session').last, 'New');
      await tester.tap(find.text('SIMPAN'));
      await tester.pump();
      await tester.pump();
      expect(repo.updates, hasLength(1));
      expect(repo.updates.single.id, 1); // session id unchanged
      expect(repo.updates.single.name, 'New');
      expect(repo.updates.single.startedAt, isNotNull);
    });

    testWidgets('cancel edit leaves data unchanged', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([_session(id: 1, name: 'Original')]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Edit Session').first);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Nama Session').last, 'Changed');
      await tester.tap(find.text('BATAL'));
      await tester.pump();
      await tester.pump();
      expect(repo.updates, isEmpty);
      expect(find.text('Original'), findsOneWidget);
    });

    testWidgets('edit with empty name does not call updateSession', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([_session(id: 1, name: 'Original')]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Edit Session').first);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Nama Session').last, '');
      await tester.tap(find.text('SIMPAN'));
      await tester.pump();
      await tester.pump();
      expect(repo.updates, isEmpty);
      expect(find.textContaining('wajib diisi'), findsOneWidget);
    });

    testWidgets('delete unused session succeeds', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([_session(id: 1, name: 'Solo')]);
      repo.hasTransactionsResult = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Hapus Session').first);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('HAPUS'));
      await tester.pump();
      await tester.pump();
      expect(repo.deletions, [1]);
    });

    testWidgets('delete used session is refused with snackbar', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([_session(id: 1, name: 'Busy')]);
      repo.hasTransactionsResult = true;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Hapus Session').first);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('HAPUS'));
      await tester.pump();
      await tester.pump();
      expect(repo.deletions, isEmpty);
      expect(find.textContaining('tidak dapat dihapus'), findsOneWidget);
    });

    testWidgets('search filters sessions case-insensitively', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = _FakeLiveSessionRepository([
        _session(id: 1, name: 'Evening Live'),
        _session(id: 2, name: 'Morning Live'),
      ]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LiveSessionsPage(repository: repo))));
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Cari Session'), 'evening');
      await tester.pump();
      expect(find.text('Evening Live'), findsWidgets);
      expect(find.text('Morning Live'), findsNothing);
    });
  });

  group('DashboardTotals — sanity after Phase F', () {
    test('fromJoined produces same numbers as fromTransactions for single item', () {
      final item = _item(orderId: 'A', qty: 2, price: 50000, hpp: 20000, income: 80000);
      final viaJoined = DashboardTotals.fromJoined([_join(_order(orderId: 'A'), item)]);
      expect(viaJoined.itemsSold, 2);
      expect(viaJoined.gmv, 100000);
      expect(viaJoined.activeIncome, 80000);
      expect(viaJoined.activeHpp, 40000);
    });
  });
}