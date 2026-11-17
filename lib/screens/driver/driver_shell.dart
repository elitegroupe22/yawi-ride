import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../account/account.dart';
import 'dashboard.dart';
import 'earnings.dart';
import 'onboarding.dart';

/// Navigation du chauffeur. Tant que le dossier n'est pas validé, l'onglet principal est le dossier.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final approved = context.watch<Session>().driverApproved;
    final pages = [
      approved ? const DriverDashboard() : const OnboardingScreen(),
      if (approved) const EarningsScreen(),
      const AccountScreen(),
    ];
    final tab = _tab.clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          approved
              ? const NavigationDestination(icon: Icon(Icons.local_taxi_outlined), selectedIcon: Icon(Icons.local_taxi), label: 'Conduite')
              : const NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Mon dossier'),
          if (approved) const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Gains'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Compte'),
        ],
      ),
    );
  }
}
