import 'package:flutter_test/flutter_test.dart';
import 'package:tiktok_seller/app/tiktok_seller_app.dart';

void main() {
  testWidgets('shows the dashboard destination initially', (tester) async {
    await tester.pumpWidget(const TikTokSellerApp());

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Your sales overview will appear here in a future milestone.'), findsOneWidget);
  });
}
