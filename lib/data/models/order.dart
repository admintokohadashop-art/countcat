import 'statuses.dart';

/// Order-level (receipt-level) entity introduced in Milestone 7-A.
///
/// A single order corresponds to one `order_id`/receipt and may contain
/// multiple item rows (each a `Transaction`). Order-level data lives here
/// and is not duplicated on items.
class Order {
  const Order({
    this.id,
    required this.accountId,
    required this.orderId,
    this.liveSessionId,
    required this.transactionDate,
    required this.paymentStatus,
    required this.orderStatus,
    this.paidAt,
    this.returnShippingCompensation = 0,
    this.paymentDescription,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int accountId;
  final String orderId;
  final int? liveSessionId;
  /// Local business date (midnight). Persisted as `YYYY-MM-DD`.
  final DateTime transactionDate;
  final PaymentStatus paymentStatus;
  final OrderStatus orderStatus;
  /// Local time after read; stored as UTC ISO-8601.
  final DateTime? paidAt;
  final int returnShippingCompensation;
  final String? paymentDescription;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Order.fromMap(Map<String, Object?> m) => Order(
        id: m['id'] as int?,
        accountId: m['account_id'] as int,
        orderId: m['order_id'] as String,
        liveSessionId: m['live_session_id'] as int?,
        transactionDate: _parseLocalDate(m['transaction_date']),
        paymentStatus: PaymentStatus.fromValue(m['payment_status'] as String),
        orderStatus: OrderStatus.fromValue(m['order_status'] as String),
        paidAt: m['paid_at'] == null ? null : DateTime.parse(m['paid_at'] as String).toLocal(),
        returnShippingCompensation: m['return_shipping_compensation'] as int? ?? 0,
        paymentDescription: m['payment_description'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'order_id': orderId,
        'live_session_id': liveSessionId,
        'transaction_date': formatLocalDate(transactionDate),
        'payment_status': paymentStatus.value,
        'order_status': orderStatus.value,
        'paid_at': paidAt?.toUtc().toIso8601String(),
        'return_shipping_compensation': returnShippingCompensation,
        'payment_description': paymentDescription,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Order copyWith({
    int? id,
    int? accountId,
    String? orderId,
    Object? liveSessionId = _unset,
    DateTime? transactionDate,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    Object? paidAt = _unset,
    int? returnShippingCompensation,
    Object? paymentDescription = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Order(
        id: id ?? this.id,
        accountId: accountId ?? this.accountId,
        orderId: orderId ?? this.orderId,
        liveSessionId: identical(liveSessionId, _unset) ? this.liveSessionId : liveSessionId as int?,
        transactionDate: transactionDate ?? this.transactionDate,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        orderStatus: orderStatus ?? this.orderStatus,
        paidAt: identical(paidAt, _unset) ? this.paidAt : paidAt as DateTime?,
        returnShippingCompensation: returnShippingCompensation ?? this.returnShippingCompensation,
        paymentDescription: identical(paymentDescription, _unset) ? this.paymentDescription : paymentDescription as String?,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  static String formatLocalDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static DateTime _parseLocalDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      final parts = raw.split('-');
      if (parts.length >= 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final dayPart = parts[2].split('T').first.split(' ').first;
        final d = int.tryParse(dayPart);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    }
    return DateTime(1970, 1, 1);
  }

  static const _unset = Object();
}