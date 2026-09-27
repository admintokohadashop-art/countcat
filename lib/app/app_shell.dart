import 'package:flutter/material.dart';

import '../data/database/app_database.dart';
import '../data/models/account.dart';
import '../data/repositories/account_repository.dart';
import '../features/settings/settings_page.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class AppShell extends StatefulWidget {
  const AppShell({required this.destinations, super.key});

  final List<AppDestination> destinations;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _desktopBreakpoint = 720.0;
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDesktopLayout = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final selected = widget.destinations[_selectedIndex];

    return Scaffold(
      appBar: AppBar(title: Text(selected.label)),
      body: isDesktopLayout
          ? Row(
              children: [
                Column(children: [
                  Expanded(child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: _selectDestination,
                    destinations: [
                      for (final destination in widget.destinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon), selectedIcon: Icon(destination.selectedIcon), label: Text(destination.label),
                        ),
                    ],
                  )),
                  const _ActiveAccountIdentity(),
                ]),
                const VerticalDivider(width: 1),
                Expanded(child: selected.page),
              ],
            )
          : selected.page,
      bottomNavigationBar: isDesktopLayout
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (final destination in widget.destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }

  void _selectDestination(int index) => setState(() => _selectedIndex = index);
}

class _ActiveAccountIdentity extends StatelessWidget {
  const _ActiveAccountIdentity();
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AccountRepository.activeAccountChanged,
        builder: (context, _, __) => FutureBuilder<Account?>(
        future: AccountRepository(AppDatabase.instance).activeAccount(),
        builder: (context, snapshot) {
          final account = snapshot.data;
          if (account == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ProfileAvatar(account.photoPath, radius: 25),
              const SizedBox(height: 6),
              SizedBox(width: 110, child: Text(account.name, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis)),
            ]),
          );
        },
      ));
}
