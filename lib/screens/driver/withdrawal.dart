import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Retrait des gains : solde disponible, demande en cours, historique et formulaire de demande.
class WithdrawalCard extends StatefulWidget {
  const WithdrawalCard({super.key, this.onChanged, this.fallbackBalance, @visibleForTesting this.initial});

  /// Appelé après une demande ou une annulation (pour rafraîchir le solde de l'écran parent).
  final VoidCallback? onChanged;

  /// Solde affiché tant que les informations de retrait ne sont pas chargées.
  final String? fallbackBalance;

  /// Données fournies directement (aperçus et tests) : pas d'appel réseau.
  final Map<String, dynamic>? initial;

  @override
  State<WithdrawalCard> createState() => WithdrawalCardState();
}

class WithdrawalCardState extends State<WithdrawalCard> {
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _d = widget.initial;
    } else {
      reload();
    }
  }

  Future<void> reload() async {
    try {
      final res = await context.read<Session>().api.get('/driver/withdrawals');
      if (mounted) setState(() => _d = res);
    } on ApiException catch (_) {
      // Facultatif : sans ces informations, l'écran garde le solde simple.
    }
  }

  Future<void> _cancel(String reference) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        content: const Text('Le montant redevient disponible immédiatement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Garder')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Annuler la demande', style: TextStyle(color: Y.alerte))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final res = await context.read<Session>().api.post('/driver/withdrawals/$reference/cancel');
      if (!mounted) return;
      setState(() => _d = res);
      toast(context, res['message']?.toString() ?? 'Demande annulée.');
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    final d = _d;
    if (d == null) return;
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WithdrawalSheet(summary: d),
    );
    if (message != null && mounted) {
      toast(context, message);
      await reload();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) return _BalanceHero(balance: widget.fallbackBalance ?? '');

    final balance = (d['balance'] as num?)?.toDouble() ?? 0;
    final available = (d['available'] as num?)?.toDouble() ?? 0;
    final minimum = (d['minimum'] as num?)?.toDouble() ?? 0;
    final pending = d['pending'] == null ? null : Map<String, dynamic>.from(d['pending'] as Map);
    final reserved = pending == null ? 0.0 : ((pending['amount'] as num?)?.toDouble() ?? 0);
    final canRequest = pending == null && available > 0 && available >= minimum;
    final history = ((d['requests'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((w) => w['status'] != 'pending')
        .take(5)
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _BalanceHero(
        balance: money(balance),
        footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: .12)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _HeroFigure(label: 'Disponible au retrait', value: money(available))),
            if (reserved > 0) Expanded(child: _HeroFigure(label: 'Réservé', value: money(reserved), muted: true)),
          ]),
          const SizedBox(height: 16),
          if (canRequest)
            FilledButton.icon(
              onPressed: _busy ? null : _request,
              style: FilledButton.styleFrom(backgroundColor: Y.braiseBtn, foregroundColor: Colors.white),
              icon: const Icon(Icons.payments_outlined, size: 20),
              label: const Text('Demander un retrait'),
            )
          else
            Text(
              pending != null
                  ? 'Une demande est en cours : vous pourrez en faire une autre après son versement.'
                  : 'Retrait possible à partir de ${money(minimum)} disponibles.',
              style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 13),
            ),
        ]),
      ),
      if (pending != null) ...[
        const SizedBox(height: 12),
        _PendingCard(w: pending, busy: _busy, onCancel: () => _cancel(pending['reference'].toString())),
      ],
      if (history.isNotEmpty) ...[
        const SectionTitle('Retraits précédents'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final w in history) ...[
              _HistoryRow(w: w),
              if (w != history.last) const Divider(height: 1),
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// Solde du chauffeur (bandeau bleu nuit), avec en pied le disponible et le bouton de retrait.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, this.footer});
  final String balance;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Y.nuit, borderRadius: BorderRadius.circular(Y.rCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Solde chauffeur', style: TextStyle(color: Color(0xFFC9D2DE))),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(balance, style: const TextStyle(fontFamily: Y.display, fontSize: 28, color: Colors.white)),
        ),
        if (footer != null) footer!,
      ]),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value, this.muted = false});
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 12)),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value, style: TextStyle(color: muted ? const Color(0xFFFFC9A8) : Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
    ]);
  }
}

/// Demande en cours : montant, étapes, destination de l'argent, annulation.
class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.w, required this.busy, required this.onCancel});
  final Map<String, dynamic> w;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final method = w['method']?.toString() ?? '';
    final rows = <(IconData, String, String)>[
      (Icons.account_balance_wallet_outlined, 'Moyen', w['method_label'].toString()),
      if (w['payee_phone'] != null) (Icons.phone_iphone, 'Numéro', w['payee_phone'].toString()),
      if (method == 'bank' && w['bank_name'] != null) (Icons.account_balance_outlined, 'Banque', w['bank_name'].toString()),
      if (method == 'bank' && w['bank_account'] != null) (Icons.numbers, 'Compte', w['bank_account'].toString()),
      if (w['payee_name'] != null) (Icons.person_outline, 'Au nom de', w['payee_name'].toString()),
      if (w['payee_phone'] == null && w['payee_name'] == null && w['bank_name'] == null) (Icons.place_outlined, 'Destination', w['destination'].toString()),
      (Icons.event_outlined, 'Demandé le', w['created_at'].toString()),
      (Icons.tag, 'Référence', w['reference'].toString()),
    ];

    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Retrait en cours', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          _StatusChip(status: 'pending', label: w['status_label']?.toString() ?? 'En attente'),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(w['amount_label'].toString(), style: const TextStyle(fontFamily: Y.display, fontSize: 24, color: Y.nuit)),
        ),
        const SizedBox(height: 14),
        const _Steps(current: 1),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(color: Y.brume, borderRadius: BorderRadius.circular(Y.rCtrl)),
          child: Column(children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(r.$1, size: 18, color: Y.ardoise),
                  const SizedBox(width: 10),
                  SizedBox(width: 92, child: Text(r.$2, style: const TextStyle(color: Y.ardoise, fontSize: 13))),
                  Expanded(child: Text(r.$3, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        const Text('Yawi vous prévient par notification dès que l\'argent est envoyé.', style: TextStyle(color: Y.ardoise, fontSize: 13)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy ? null : onCancel,
          style: OutlinedButton.styleFrom(foregroundColor: Y.alerte, side: const BorderSide(color: Color(0xFFF2C4CB))),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Annuler la demande'),
        ),
      ]),
    );
  }
}

/// Avancement : demande envoyée → versement par Yawi → argent reçu.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});
  final int current; // 0 envoyée, 1 versement en cours, 2 reçu

  @override
  Widget build(BuildContext context) {
    const labels = ['Demande\nenvoyée', 'Versement\npar Yawi', 'Argent\nreçu'];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < labels.length; i++) ...[
        Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (i <= current ? Y.braise : Y.trait))),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < current ? Y.feuille : (i == current ? Y.braise : Y.craie),
                  border: Border.all(color: i <= current ? Colors.transparent : Y.trait, width: 2),
                ),
                child: i < current
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : (i == current ? const Icon(Icons.more_horiz, size: 15, color: Colors.white) : null),
              ),
              Expanded(child: Container(height: 3, color: i == labels.length - 1 ? Colors.transparent : (i < current ? Y.braise : Y.trait))),
            ]),
            const SizedBox(height: 6),
            Text(labels[i], textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.2, color: i <= current ? Y.nuit : Y.ardoise, fontWeight: i == current ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ],
    ]);
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.w});
  final Map<String, dynamic> w;

  @override
  Widget build(BuildContext context) {
    final sub = [w['method_label'], w['processed_at'] ?? w['created_at'], if (w['transaction_ref'] != null) 'réf. ${w['transaction_ref']}'].whereType<Object>().join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w['amount_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: Y.ardoise, fontSize: 12.5)),
            if (w['status'] == 'rejected' && w['admin_note'] != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Motif : ${w['admin_note']}', style: const TextStyle(color: Y.alerte, fontSize: 12.5))),
          ]),
        ),
        const SizedBox(width: 8),
        _StatusChip(status: w['status'].toString(), label: w['status_label'].toString()),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.label});
  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'paid' => (Y.feuilleVoile, const Color(0xFF0A6B44)),
      'rejected' => (const Color(0xFFFDE8EB), const Color(0xFFA50E26)),
      'pending' => (const Color(0xFFFFF4D6), const Color(0xFF7A5300)),
      _ => (Y.brume, Y.ardoise),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}

class _WithdrawalSheet extends StatefulWidget {
  const _WithdrawalSheet({required this.summary});
  final Map<String, dynamic> summary;

  @override
  State<_WithdrawalSheet> createState() => _WithdrawalSheetState();
}

class _WithdrawalSheetState extends State<_WithdrawalSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _phone;
  late final TextEditingController _name;
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _note = TextEditingController();
  String _method = 'orange_money';
  bool _busy = false;
  String? _error; // dans la fenêtre : un message toast passerait dessous

  double get _available => (widget.summary['available'] as num?)?.toDouble() ?? 0;
  double get _minimum => (widget.summary['minimum'] as num?)?.toDouble() ?? 0;

  @override
  void initState() {
    super.initState();
    final payee = Map<String, dynamic>.from((widget.summary['payee'] as Map?) ?? {});
    _amount = TextEditingController(text: _available.floor().toString());
    _phone = TextEditingController(text: payee['phone']?.toString() ?? '');
    _name = TextEditingController(text: payee['name']?.toString() ?? '');
  }

  bool get _mobile => _method == 'orange_money' || _method == 'mtn_momo';

  Future<void> _send() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    String? err;
    if (amount < _minimum) err = 'Le retrait minimum est de ${money(_minimum)}.';
    if (amount > _available) err = 'Montant supérieur à votre solde disponible (${money(_available)}).';
    if (_mobile && _phone.text.trim().length < 8) err = 'Indiquez le numéro qui recevra l\'argent.';
    if (_method == 'bank' && (_bank.text.trim().isEmpty || _account.text.trim().isEmpty)) err = 'Indiquez la banque et le numéro de compte.';
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<Session>().api.post('/driver/withdrawals', {
        'amount': amount,
        'method': _method,
        'payee_name': _name.text.trim(),
        if (_mobile) 'payee_phone': _phone.text.trim(),
        if (_method == 'bank') 'bank_name': _bank.text.trim(),
        if (_method == 'bank') 'bank_account': _account.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (mounted) Navigator.pop(context, res['message']?.toString() ?? 'Demande envoyée.');
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'La demande n\'a pas pu être envoyée. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = ((widget.summary['methods'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 8),
          const Text('Demande de retrait', style: TextStyle(fontFamily: Y.display, fontSize: 20)),
          const SizedBox(height: 4),
          Text('Disponible : ${money(_available)}', style: const TextStyle(color: Y.ardoise)),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Montant (GNF)'),
          ),
          const SizedBox(height: 14),
          const Text('Recevoir par', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in methods)
              ChoiceChip(
                label: Text(m['label'].toString()),
                selected: _method == m['key'],
                onSelected: (_) => setState(() => _method = m['key'].toString()),
              ),
          ]),
          const SizedBox(height: 14),
          if (_mobile) ...[
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Numéro qui reçoit l\'argent')),
            const SizedBox(height: 12),
          ],
          if (_method == 'bank') ...[
            TextField(controller: _bank, decoration: const InputDecoration(labelText: 'Banque')),
            const SizedBox(height: 12),
            TextField(controller: _account, decoration: const InputDecoration(labelText: 'Numéro de compte')),
            const SizedBox(height: 12),
          ],
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Au nom de')),
          const SizedBox(height: 12),
          TextField(controller: _note, maxLength: 500, decoration: const InputDecoration(labelText: 'Message pour Yawi (facultatif)', counterText: '')),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF8E1B1B), fontWeight: FontWeight.w600))),
              ]),
            ),
          const SizedBox(height: 16),
          BusyButton(label: 'Envoyer la demande', busy: _busy, onPressed: _send),
          const SizedBox(height: 8),
          const Text('Le montant est réservé jusqu\'au versement. Vous êtes prévenu par notification.', textAlign: TextAlign.center, style: TextStyle(color: Y.ardoise, fontSize: 12)),
        ]),
      ),
    );
  }
}
