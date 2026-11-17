import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/app_icon.dart';

/// Bottom navigation that keeps each tab's state while switching.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: AppIcon(HugeIcons.strokeRoundedHome01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedHome01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: 'Home',
    ),
    NavigationDestination(
      icon: AppIcon(HugeIcons.strokeRoundedInvoice01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedInvoice01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: 'Transactions',
    ),
    NavigationDestination(
      icon: AppIcon(HugeIcons.strokeRoundedPieChart),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedPieChart,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: 'Reports',
    ),
    NavigationDestination(
      icon: AppIcon(HugeIcons.strokeRoundedSettings01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedSettings01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: 'Settings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          // Tapping the current tab again returns to its first page.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
