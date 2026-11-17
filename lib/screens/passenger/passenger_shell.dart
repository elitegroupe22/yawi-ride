import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/alerts.dart';
import '../account/account.dart';
import 'home.dart';
import 'ride_tracking.dart';
import 'rides.dart';
import 'wallet.dart';

/// Navigation du passager : Accueil, Courses, Portefeuille, Compte.
class PassengerShell extends StatefulWidget {
  const PassengerShell({super.key});

  @override
  State<PassengerShell> createState() => _PassengerShellState();
}

class _PassengerShellState extends State<PassengerShell> {
  int _tab = 0;
  StreamSubscription<String>? _opened;
  final _ridesKey = GlobalKey<RidesScreenState>();
  final _walletKey = GlobalKey<WalletScreenState>();

  @override
  void initState() {
    super.initState();
    _opened = Alerts.instance.opened.stream.listen(_route);
  }

  /// Notification touchée : ouvre la course ou le portefeuille concerné.
  void _route(String url) {
    final ride = RegExp(r'/rides/([A-Za-z0-9-]+)').firstMatch(url);
    if (ride != null) {
      RideScreen.open(context, ride.group(1)!);
    } else if (url.contains('/wallet') || url.contains('/paiements')) {
      setState(() => _tab = 2);
      _walletKey.currentState?.load();
    }
  }

  @override
  void dispose() {
    _opened?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        HomeScreen(onShowRides: () => setState(() => _tab = 1)),
        RidesScreen(key: _ridesKey),
        WalletScreen(key: _walletKey),
        const AccountScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _ridesKey.currentState?.load();
          if (i == 2) _walletKey.currentState?.load();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Accueil'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Courses'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Portefeuille'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Compte'),
        ],
      ),
    );
  }
}
