import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/web_page.dart';

/// Solde, rechargement ChapChap Pay (page de paiement dans l'application) et historique.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => WalletScreenState();
}

class WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final res = await context.read<Session>().api.get('/wallet');
      if (mounted) setState(() {
        _data = res;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _topUp() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TopUpSheet(),
    );
    if (result != null && mounted) {
      toast(context, result);
      load();
      context.read<Session>().refresh().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final payments = context.watch<Session>().payments;
    final d = _data;
    final tx = ((d?['transactions'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Portefeuille')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (_error != null && d == null) RetryView(message: _error!, onRetry: load),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Y.nuit, borderRadius: BorderRadius.circular(Y.rCard)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Solde disponible', style: TextStyle(color: Color(0xFFC9D2DE))),
              const SizedBox(height: 6),
              Text(d?['balance_label']?.toString() ?? '…', style: const TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 26)),
              const SizedBox(height: 18),
              if (payments['online'] == true)
                FilledButton.icon(onPressed: _topUp, icon: const Icon(Icons.add), label: const Text('Recharger'))
              else
                const Text('Rechargement en ligne bientôt disponible. Rechargez auprès d\'un agent Yawi.', style: TextStyle(color: Color(0xFFC9D2DE))),
            ]),
          ),
          if (d?['pending'] is Map) ...[
            const SizedBox(height: 12),
            Panel(
              border: const Color(0xFFE0A100),
              onTap: () async {
                await WebPage.open(context, title: 'Paiement', url: d['pending']['payment_url'].toString(), closeOn: '/paiements/');
                load();
              },
              child: Row(children: [
                const Icon(Icons.hourglass_top, color: Color(0xFF8A5A00)),
                const SizedBox(width: 10),
                Expanded(child: Text('Paiement de ${d!['pending']['amount_label']} en attente. Touchez pour le terminer.')),
              ]),
            ),
          ],
          const SectionTitle('Historique'),
          if (d != null && tx.isEmpty)
            const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'Aucun mouvement', message: 'Vos rechargements et paiements de courses apparaîtront ici.'),
          for (final t in tx)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: t['type'] == 'debit' ? Y.brume : Y.feuilleVoile,
                    child: Icon(t['type'] == 'debit' ? Icons.north_east : Icons.south_west, color: t['type'] == 'debit' ? Y.nuit : Y.feuille, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['label'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(t['date_label'].toString(), style: const TextStyle(color: Y.ardoise, fontSize: 13)),
                  ])),
                  Text(t['amount_label'].toString(), style: TextStyle(fontWeight: FontWeight.w700, color: t['type'] == 'debit' ? Y.nuit : Y.feuille)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet();

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final _amount = TextEditingController();
  String? _method;
  bool _busy = false;
  String? _status;
  String? _error; // affichée dans la fenêtre : un toast passerait sous la feuille modale

  Map<String, dynamic> get _cfg => context.read<Session>().payments;

  @override
  void initState() {
    super.initState();
    final quick = (_cfg['quick'] as List?) ?? [];
    if (quick.isNotEmpty) _amount.text = quick.first.toString();
    _method = _cfg['default_method']?.toString();
  }

  int get _value => int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  Future<void> _pay() async {
    final min = (_cfg['min'] as num?)?.toInt() ?? 1000;
    final max = (_cfg['max'] as num?)?.toInt() ?? 10000000;
    if (_value < min || _value > max) {
      toast(context, 'Montant entre ${money(min)} et ${money(max)}.', error: true);
      return;
    }
    final api = context.read<Session>().api;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      final res = await api.post('/wallet/topup', {'amount': _value, if (_method != null) 'method': _method});
      if (!mounted) return;
      await WebPage.open(context, title: 'Paiement sécurisé', url: res['payment_url'].toString(), closeOn: res['return_path'].toString());
      if (!mounted) return;
      // Le serveur interroge ChapChap Pay : on suit l'état quelques secondes
      setState(() => _status = 'Vérification du paiement…');
      for (var i = 0; i < 12; i++) {
        final st = await api.getUrl(res['status_url'].toString());
        if (st['final'] == true) {
          if (mounted) Navigator.pop(context, st['status'] == 'success' || st['status'] == 'completed' ? 'Rechargement confirmé.' : (st['message'] ?? st['label']).toString());
          return;
        }
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
      }
      if (mounted) Navigator.pop(context, 'Paiement en cours de confirmation. Votre solde sera mis à jour automatiquement.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = null;
          _error = e is ApiException ? e.message : 'Le rechargement n\'a pas pu démarrer. Réessayez.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quick = ((_cfg['quick'] as List?) ?? []).map((e) => (e as num).toInt()).toList();
    final methods = ((_cfg['methods'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final test = _cfg['test_mode'] == true;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Recharger mon portefeuille', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (test) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(10)),
              child: const Text('Mode test : aucun argent réel n\'est débité.', style: TextStyle(color: Color(0xFF8A5A00), fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontFamily: Y.display, fontSize: 24),
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(suffixText: 'GNF'),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (final q in quick)
              ChoiceChip(label: Text(money(q)), selected: _value == q, showCheckmark: false, onSelected: (_) => setState(() => _amount.text = '$q')),
          ]),
          if (methods.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Moyen de paiement', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _method,
              onChanged: (v) => setState(() => _method = v),
              child: Column(children: [
                for (final m in methods)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: m['key'].toString(),
                    title: Text(m['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ],
          if (_status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status!, textAlign: TextAlign.center, style: const TextStyle(color: Y.ardoise))),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF8E1B1B), fontWeight: FontWeight.w600))),
              ]),
            ),
          const SizedBox(height: 14),
          BusyButton(label: 'Payer ${money(_value)}', busy: _busy, onPressed: _value > 0 ? _pay : null),
        ]),
      ),
    );
  }
}
