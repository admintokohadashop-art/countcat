import 'package:flutter/material.dart';

import '../features/dashboard/dashboard_page.dart';
import '../features/reports/reports_page.dart';
import '../features/returns/returns_page.dart';
import '../features/sales/new_sale_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sessions/live_sessions_page.dart';
import 'app_shell.dart';

class TikTokSellerApp extends StatelessWidget {
  const TikTokSellerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TikTokSeller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEE1D52)),
        useMaterial3: true,
      ),
      home: AppShell(
        destinations: const [
          AppDestination(
            label: 'Dashboard',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            page: DashboardPage(),
          ),
          AppDestination(
            label: 'New Sale',
            icon: Icons.add_shopping_cart_outlined,
            selectedIcon: Icons.add_shopping_cart,
            page: NewSalePage(),
          ),
          AppDestination(
            label: 'Live Sessions',
            icon: Icons.live_tv_outlined,
            selectedIcon: Icons.live_tv,
            page: LiveSessionsPage(),
          ),
          AppDestination(
            label: 'Reports',
            icon: Icons.assessment_outlined,
            selectedIcon: Icons.assessment,
            page: ReportsPage(),
          ),
          AppDestination(
            label: 'Retur',
            icon: Icons.assignment_return_outlined,
            selectedIcon: Icons.assignment_return,
            page: ReturnsPage(),
          ),
          AppDestination(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            page: SettingsPage(),
          ),
        ],
      ),
    );
  }
}