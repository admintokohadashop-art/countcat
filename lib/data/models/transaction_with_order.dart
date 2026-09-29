import 'order.dart';
import 'transaction.dart';

/// Read-side view-model carrying both item-level (`Transaction`) and its
/// parent order-level (`Order`) data. Used by Reports, Returns, and the
/// Dashboard once FASE B wired the join through the repositories.
class TransactionWithOrder {
  const TransactionWithOrder({required this.item, required this.order});

  final Transaction item;
  final Order order;

  /// Builds the view-model from a joined row (aliased SQL, or an item map
  /// merged with its parent order map). Keys are expected to match the
  /// columns produced by `Transaction.toMap()` / `Order.toMap()`.
  factory TransactionWithOrder.fromMap(Map<String, Object?> m) => TransactionWithOrder(
        item: Transaction.fromMap(m),
        order: Order.fromMap(m),
      );

  /// Transitional single-item wrapper: constructs a synthetic parent [Order]
  /// from the item's mirror order-level fields. Under 1 order = 1 item
  /// semantics (pre-M7 data), the derived order is identical to the real
  /// parent order. Callers that already have the true parent order should
  /// construct `TransactionWithOrder` directly instead of using this factory.
  factory TransactionWithOrder.fromTransaction(Transaction t) => TransactionWithOrder(
        item: t,
        order: Order(
          id: t.orderFk,
          accountId: t.accountId ?? 0,
          orderId: t.orderId,
          liveSessionId: t.liveSessionId,
          transactionDate: t.transactionDate,
          paymentStatus: t.paymentStatus,
          orderStatus: t.orderStatus,
          paidAt: t.paidAt,
          returnShippingCompensation: t.returnShippingCompensation,
          paymentDescription: t.paymentDescription,
          createdAt: t.createdAt,
          updatedAt: t.updatedAt,
        ),
      );
}