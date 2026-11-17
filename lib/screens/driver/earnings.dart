import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<Session>().api.get('/driver/earnings');
      if (mounted) setState(() {
        _data = res;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final summary = ((d?['summary'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final rides = ((d?['rides'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes gains')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: d == null
            ? ListView(children: [if (_error != null) RetryView(message: _error!, onRetry: _load) else const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))])
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Y.nuit, borderRadius: BorderRadius.circular(Y.rCard)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Solde chauffeur', style: TextStyle(color: Color(0xFFC9D2DE))),
                    const SizedBox(height: 4),
                    Text(d['wallet_label'].toString(), style: const TextStyle(fontFamily: Y.display, fontSize: 24, color: Colors.white)),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  for (final s in summary) ...[
                    Expanded(
                      child: Panel(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s['label'].toString(), style: const TextStyle(fontSize: 12, color: Y.ardoise)),
                          const SizedBox(height: 4),
                          Text(s['earnings_label'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${s['rides']} course(s)', style: const TextStyle(fontSize: 12, color: Y.ardoise)),
                        ]),
                      ),
                    ),
                    if (s != summary.last) const SizedBox(width: 8),
                  ],
                ]),
                const SectionTitle('Dernières courses'),
                if (rides.isEmpty) const EmptyState(icon: Icons.local_taxi_outlined, title: 'Pas encore de course', message: 'Passez en ligne pour recevoir des demandes.'),
                for (final r in rides)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          StatusPill(status: r['status']?.toString(), label: r['status_label'].toString()),
                          const Spacer(),
                          Text(r['earnings_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 10),
                        RouteLines(from: r['pickup'].toString(), to: r['dropoff'].toString(), dense: true),
                        const SizedBox(height: 6),
                        Text('${r['date_label']} · ${r['service']}', style: const TextStyle(color: Y.ardoise, fontSize: 13)),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }
}
