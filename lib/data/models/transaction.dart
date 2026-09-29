import 'statuses.dart';

class Transaction {
  const Transaction({
    this.id,
    this.accountId,
    this.liveSessionId,
    this.hppId,
    this.hppUnitAmount = 0,
    this.unitPrice = 0,
    required this.transactionDate,
    required this.productCode,
    required this.orderId,
    required this.quantity,
    required this.gmvAmount,
    this.paymentDescription,
    required this.paymentStatus,
    this.paidAt,
    required this.netIncomeAmount,
    this.returnShippingCompensation = 0,
    required this.orderStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id, accountId, liveSessionId, hppId;
  final int hppUnitAmount, unitPrice, quantity, gmvAmount, netIncomeAmount;
  /// Kompensasi ongkir retur. Satu order = satu nilai. 0 = belum diinput.
  final int returnShippingCompensation;
  /// Tanggal bisnis transaksi. Selalu dinormalkan ke local midnight.
  final DateTime transactionDate;
  final String productCode, orderId;
  final String? paymentDescription;
  final PaymentStatus paymentStatus;
  /// Setelah dibaca dari DB, selalu local time. Saat disimpan, dikonversi ke UTC
  /// oleh [toMap] sehingga wall-clock day tidak bergeser.
  final DateTime? paidAt;
  final OrderStatus orderStatus;
  final DateTime createdAt, updatedAt;

  factory Transaction.fromMap(Map<String, Object?> m) => Transaction(
        id: m['id'] as int?,
        accountId: m['account_id'] as int?,
        liveSessionId: m['live_session_id'] as int?,
        hppId: m['hpp_id'] as int?,
        hppUnitAmount: m['hpp_unit_amount'] as int? ?? 0,
        unitPrice: m['unit_price'] as int? ?? 0,
        transactionDate: m['transaction_date'] != null
            ? _parseLocalDate(m['transaction_date'])
            : _parseUtcToLocalDate(m['created_at']),
        productCode: m['product_code'] as String,
        orderId: m['order_id'] as String,
        quantity: m['quantity'] as int,
        gmvAmount: m['gmv_amount'] as int,
        paymentDescription: m['payment_description'] as String?,
        paymentStatus: PaymentStatus.fromValue(m['payment_status'] as String),
        paidAt: m['paid_at'] == null
            ? null
            : DateTime.parse(m['paid_at'] as String).toLocal(),
        netIncomeAmount: m['net_income_amount'] as int,
        returnShippingCompensation: m['return_shipping_compensation'] as int? ?? 0,
        orderStatus: OrderStatus.fromValue(m['order_status'] as String),
        createdAt: DateTime.parse(m['created_at'] as String),
        updatedAt: DateTime.parse(m['updated_at'] as String),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'live_session_id': liveSessionId,
        'hpp_id': hppId,
        'hpp_unit_amount': hppUnitAmount,
        'unit_price': unitPrice,
        'transaction_date': formatLocalDate(transactionDate),
        'product_code': productCode,
        'order_id': orderId,
        'quantity': quantity,
        'gmv_amount': gmvAmount,
        'payment_description': paymentDescription,
        'payment_status': paymentStatus.value,
        'paid_at': paidAt?.toUtc().toIso8601String(),
        'net_income_amount': netIncomeAmount,
        'return_shipping_compensation': returnShippingCompensation,
        'order_status': orderStatus.value,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  Transaction copyWith({
    int? id,
    Object? accountId = _unset,
    Object? liveSessionId = _unset,
    Object? hppId = _unset,
    int? hppUnitAmount,
    int? unitPrice,
    DateTime? transactionDate,
    String? productCode,
    String? orderId,
    int? quantity,
    int? gmvAmount,
    Object? paymentDescription = _unset,
    PaymentStatus? paymentStatus,
    Object? paidAt = _unset,
    int? netIncomeAmount,
    int? returnShippingCompensation,
    OrderStatus? orderStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Transaction(
        id: id ?? this.id,
        accountId: identical(accountId, _unset) ? this.accountId : accountId as int?,
        liveSessionId: identical(liveSessionId, _unset) ? this.liveSessionId : liveSessionId as int?,
        hppId: identical(hppId, _unset) ? this.hppId : hppId as int?,
        hppUnitAmount: hppUnitAmount ?? this.hppUnitAmount,
        unitPrice: unitPrice ?? this.unitPrice,
        transactionDate: transactionDate ?? this.transactionDate,
        productCode: productCode ?? this.productCode,
        orderId: orderId ?? this.orderId,
        quantity: quantity ?? this.quantity,
        gmvAmount: gmvAmount ?? this.gmvAmount,
        paymentDescription: identical(paymentDescription, _unset) ? this.paymentDescription : paymentDescription as String?,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paidAt: identical(paidAt, _unset) ? this.paidAt : paidAt as DateTime?,
        netIncomeAmount: netIncomeAmount ?? this.netIncomeAmount,
        returnShippingCompensation: returnShippingCompensation ?? this.returnShippingCompensation,
        orderStatus: orderStatus ?? this.orderStatus,
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

  static DateTime _parseUtcToLocalDate(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        final local = parsed.toLocal();
        return DateTime(local.year, local.month, local.day);
      }
    }
    return DateTime(1970, 1, 1);
  }

  static const _unset = Object();
}