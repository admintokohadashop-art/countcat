import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/data/models/live_session.dart';
import 'package:tiktok_seller/data/models/monthly_report.dart';
import 'package:tiktok_seller/data/models/order.dart';
import 'package:tiktok_seller/data/models/statuses.dart';
import 'package:tiktok_seller/data/models/transaction.dart';
import 'package:tiktok_seller/data/models/transaction_with_order.dart';
import 'package:tiktok_seller/data/repositories/live_session_repository.dart';
import 'package:tiktok_seller/data/repositories/monthly_report_repository.dart';
import 'package:tiktok_seller/data/repositories/order_repository.dart';
import 'package:tiktok_seller/data/repositories/transaction_repository.dart';
import 'package:tiktok_seller/features/reports/reports_page.dart';
import 'package:tiktok_seller/features/returns/returns_page.dart';

Order _order({
  int? id,
  int accountId = 1,
  required String orderId,
  OrderStatus orderStatus = OrderStatus.returned,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  int compensation = 0,
}) {
  final now = DateTime(2026, 9, 15, 10);
  return Order(
    id: id,
    accountId: accountId,
    orderId: orderId,
    transactionDate: DateTime(2026, 9, 15),
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    paidAt: now,
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
  required String orderId,
  int qty = 1,
  int price = 1000,
  int hpp = 0,
  int? income,
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
  }) async => _items;
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
  final List<Order> updates = [];
  @override
  Future<int> create(Order order) async => 1;
  @override
  Future<int> createWithItems(Order order, List<Transaction> items) async => 1;
  @override
  Future<Order?> get(int id) async => null;
  @override
  Future<List<Order>> list({
    int? liveSessionId,
    DateTime? periodStart,
    DateTime? periodEnd,
    String search = '',
  }) async => const [];
  @override
  Future<void> update(Order order) async {
    updates.add(order);
  }
  @override
  Future<void> delete(int id) async {}
}

class _FakeMonthlyReportRepository implements MonthlyReportRepository {
  @override
  Future<List<MonthlyReport>> listReports() async => const [];
  @override
  Future<void> save(MonthlyReport report) async {}
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

void main() {
  group('Returns — vertical scrollbar', () {
    testWidgets('exposes a visible interactive vertical scrollbar', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final items = <TransactionWithOrder>[];
      for (var i = 0; i < 30; i++) {
        final o = _order(id: i + 1, orderId: 'ORD-$i', compensation: 1000);
        items.add(TransactionWithOrder(
          item: _item(id: i + 1, orderFk: i + 1, orderId: 'ORD-$i'),
          order: o,
        ));
      }
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReturnsPage(
            transactionRepository: _FakeTransactionRepository(items),
            orderRepository: _FakeOrderRepository(),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      final sb = tester.widget<Scrollbar>(find.byKey(const ValueKey('returns_scrollbar')));
      expect(sb.thumbVisibility, isTrue);
      expect(sb.interactive, isTrue);
      expect(sb.controller, isNotNull);
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.controller, same(sb.controller));
    });
  });

  group('Reports — Month Detail scrollbars', () {
    testWidgets('exposes both horizontal and vertical scrollbars with controllers', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MonthDetailPage(
          month: const ReportMonth(2026, 9),
          transactionRepository: _FakeTransactionRepository(const []),
          orderRepository: _FakeOrderRepository(),
          monthlyReportRepository: _FakeMonthlyReportRepository(),
          liveSessionRepository: _FakeLiveSessionRepository(),
        ),
      ));
      await tester.pump();
      await tester.pump();

      final h = tester.widget<Scrollbar>(find.byKey(const ValueKey('reports_table_horizontal_scrollbar')));
      final v = tester.widget<Scrollbar>(find.byKey(const ValueKey('reports_table_vertical_scrollbar')));
      expect(h.thumbVisibility, isTrue);
      expect(h.interactive, isTrue);
      expect(h.controller, isNotNull);
      expect(v.thumbVisibility, isTrue);
      expect(v.interactive, isTrue);
      expect(v.controller, isNotNull);
      expect(h.controller, isNot(same(v.controller)));
    });
  });

  group('Reports — Monthly Summary scrollbar', () {
    testWidgets('exposes a visible interactive vertical scrollbar for the month list', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final o = _order(id: 1, orderId: 'ORD-1');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ReportsPage(
            transactionRepository: _FakeTransactionRepository([
              TransactionWithOrder(
                item: _item(orderFk: 1, orderId: 'ORD-1'),
                order: o,
              ),
            ]),
            orderRepository: _FakeOrderRepository(),
            monthlyReportRepository: _FakeMonthlyReportRepository(),
            liveSessionRepository: _FakeLiveSessionRepository(),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      final sb = tester.widget<Scrollbar>(find.byKey(const ValueKey('reports_months_scrollbar')));
      expect(sb.thumbVisibility, isTrue);
      expect(sb.interactive, isTrue);
      expect(sb.controller, isNotNull);
    });
  });
}