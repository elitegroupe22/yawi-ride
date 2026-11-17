import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'ride_tracking.dart';

/// Historique des courses et colis, avec filtre et recherche instantanée.
class RidesScreen extends StatefulWidget {
  const RidesScreen({super.key});

  @override
  State<RidesScreen> createState() => RidesScreenState();
}

class RidesScreenState extends State<RidesScreen> {
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  String _filter = '';
  String _q = '';
  int _page = 1;
  int _last = 1;
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    load();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_loading && _page < _last) _fetch(_page + 1);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> load() => _fetch(1);

  Future<void> _fetch(int page) async {
    setState(() => _loading = true);
    try {
      final res = await context.read<Session>().api.get('/rides', query: {'page': page, if (_filter.isNotEmpty) 'filtre': _filter, if (_q.isNotEmpty) 'q': _q});
      if (!mounted) return;
      final data = ((res['data'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _items = page == 1 ? data : [..._items, ...data];
        _page = res['meta']?['page'] ?? page;
        _last = res['meta']?['last_page'] ?? page;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes courses')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SearchField(
            hint: 'Référence, adresse…',
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _q = v.trim();
                load();
              });
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final f in const [('', 'Tout'), ('courses', 'Courses'), ('colis', 'Colis')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _filter = f.$1);
                    load();
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: _error != null && _items.isEmpty
                ? ListView(children: [RetryView(message: _error!, onRetry: load)])
                : _items.isEmpty && !_loading
                    ? ListView(children: [
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: _q.isNotEmpty ? 'Aucun résultat' : 'Aucune course pour le moment',
                          message: _q.isNotEmpty ? 'Essayez une autre recherche.' : 'Vos courses et livraisons apparaîtront ici.',
                        ),
                      ])
                    : ListView.separated(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _items.length + (_loading ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          if (i >= _items.length) return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
                          final r = _items[i];
                          return _RideTile(ride: r, onTap: () async {
                            await RideScreen.open(context, r['reference'].toString());
                            load();
                          });
                        },
                      ),
          ),
        ),
      ]),
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride, required this.onTap});
  final Map<String, dynamic> ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = ride['status']?.toString();
    final delivery = ride['kind'] == 'delivery';
    return Panel(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, decoration: BoxDecoration(color: StatusColors.of(status).border, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(delivery ? Icons.inventory_2_outlined : Icons.local_taxi_outlined, size: 18, color: Y.ardoise),
              const SizedBox(width: 6),
              Text(ride['date_label'].toString(), style: const TextStyle(color: Y.ardoise, fontSize: 13)),
              const Spacer(),
              Text(ride['fare_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            RouteLines(from: ride['pickup'].toString(), to: ride['dropoff'].toString(), dense: true),
            const SizedBox(height: 10),
            Row(children: [
              StatusPill(status: status, label: ride['status_label'].toString()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [ride['service'], if (ride['driver'] != null) ride['driver'], if (delivery && ride['recipient'] != null) 'pour ${ride['recipient']}'].join(' · '),
                  style: const TextStyle(color: Y.ardoise, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ])),
        ]),
      ),
    );
  }
}
