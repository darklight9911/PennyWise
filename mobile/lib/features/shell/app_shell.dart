import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/app_icon.dart';
import '../../core/widgets/responsive_layout.dart';

/// Adaptive shell: bottom bar on phones and a side rail on wider viewports.
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

  static const _railDestinations = [
    NavigationRailDestination(
      icon: AppIcon(HugeIcons.strokeRoundedHome01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedHome01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: Text('Home'),
    ),
    NavigationRailDestination(
      icon: AppIcon(HugeIcons.strokeRoundedInvoice01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedInvoice01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: Text('Transactions'),
    ),
    NavigationRailDestination(
      icon: AppIcon(HugeIcons.strokeRoundedPieChart),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedPieChart,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: Text('Reports'),
    ),
    NavigationRailDestination(
      icon: AppIcon(HugeIcons.strokeRoundedSettings01),
      selectedIcon: AppIcon(
        HugeIcons.strokeRoundedSettings01,
        strokeWidth: AppIcon.selectedStroke,
      ),
      label: Text('Settings'),
    ),
  ];

  void _onSelect(int index) => navigationShell.goBranch(
    index,
    // Tapping the current tab again returns to its first page.
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    if (ResponsiveLayout.useRail(context)) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onSelect,
                destinations: _railDestinations,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    final scaled = MediaQuery.textScalerOf(context).scale(14) > 18;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        height: scaled ? 80 : 64,
        selectedIndex: navigationShell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: _onSelect,
      ),
    );
  }
}
