import 'statuses.dart';

class Transaction {
  static const _unset = Object();
  const Transaction({this.id, this.liveSessionId, required this.productCode, required this.orderId, required this.quantity, required this.gmvAmount, this.paymentDescription, required this.paymentStatus, this.paidAt, required this.netIncomeAmount, required this.orderStatus, required this.createdAt, required this.updatedAt});
  final int? id;
  final int? liveSessionId;
  final String productCode;
  final String orderId;
  final int quantity;
  final int gmvAmount;
  final String? paymentDescription;
  final PaymentStatus paymentStatus;
  final DateTime? paidAt;
  final int netIncomeAmount;
  final OrderStatus orderStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Transaction.fromMap(Map<String, Object?> map) => Transaction(id: map['id'] as int?, liveSessionId: map['live_session_id'] as int?, productCode: map['product_code'] as String, orderId: map['order_id'] as String, quantity: map['quantity'] as int, gmvAmount: map['gmv_amount'] as int, paymentDescription: map['payment_description'] as String?, paymentStatus: PaymentStatus.fromValue(map['payment_status'] as String), paidAt: map['paid_at'] == null ? null : DateTime.parse(map['paid_at'] as String), netIncomeAmount: map['net_income_amount'] as int, orderStatus: OrderStatus.fromValue(map['order_status'] as String), createdAt: DateTime.parse(map['created_at'] as String), updatedAt: DateTime.parse(map['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'live_session_id': liveSessionId, 'product_code': productCode, 'order_id': orderId, 'quantity': quantity, 'gmv_amount': gmvAmount, 'payment_description': paymentDescription, 'payment_status': paymentStatus.value, 'paid_at': paidAt?.toIso8601String(), 'net_income_amount': netIncomeAmount, 'order_status': orderStatus.value, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
  Transaction copyWith({int? id, Object? liveSessionId = _unset, String? productCode, String? orderId, int? quantity, int? gmvAmount, Object? paymentDescription = _unset, PaymentStatus? paymentStatus, Object? paidAt = _unset, int? netIncomeAmount, OrderStatus? orderStatus, DateTime? createdAt, DateTime? updatedAt}) => Transaction(id: id ?? this.id, liveSessionId: identical(liveSessionId, _unset) ? this.liveSessionId : liveSessionId as int?, productCode: productCode ?? this.productCode, orderId: orderId ?? this.orderId, quantity: quantity ?? this.quantity, gmvAmount: gmvAmount ?? this.gmvAmount, paymentDescription: identical(paymentDescription, _unset) ? this.paymentDescription : paymentDescription as String?, paymentStatus: paymentStatus ?? this.paymentStatus, paidAt: identical(paidAt, _unset) ? this.paidAt : paidAt as DateTime?, netIncomeAmount: netIncomeAmount ?? this.netIncomeAmount, orderStatus: orderStatus ?? this.orderStatus, createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt);
}
