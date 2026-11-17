import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Retrait des gains : solde disponible, demande en cours, historique et formulaire de demande.
class WithdrawalCard extends StatefulWidget {
  const WithdrawalCard({super.key, this.onChanged});

  /// Appelé après une demande ou une annulation (pour rafraîchir le solde de l'écran parent).
  final VoidCallback? onChanged;

  @override
  State<WithdrawalCard> createState() => WithdrawalCardState();
}

class WithdrawalCardState extends State<WithdrawalCard> {
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final res = await context.read<Session>().api.get('/driver/withdrawals');
      if (mounted) setState(() => _d = res);
    } on ApiException catch (_) {
      // Carte facultative : l'écran des gains reste utilisable sans elle.
    }
  }

  Future<void> _cancel(String reference) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Annuler la demande ?'),
        content: const Text('Le montant redevient disponible immédiatement.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Annuler la demande')),
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
    if (d == null) return const SizedBox.shrink();
    final available = (d['available'] as num?)?.toDouble() ?? 0;
    final minimum = (d['minimum'] as num?)?.toDouble() ?? 0;
    final pending = d['pending'] == null ? null : Map<String, dynamic>.from(d['pending'] as Map);
    final history = ((d['requests'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((w) => w['status'] != 'pending').take(5).toList();

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Retirer mes gains', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (pending == null && available > 0 && available >= minimum)
            FilledButton.icon(onPressed: _busy ? null : _request, icon: const Icon(Icons.payments_outlined, size: 18), label: const Text('Retirer')),
        ]),
        const SizedBox(height: 4),
        Text('Disponible : ${money(available)} · minimum ${money(minimum)}', style: const TextStyle(color: Y.ardoise)),
        if (pending != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF4D6), borderRadius: BorderRadius.circular(Y.rCtrl)),
            child: Row(children: [
              const Icon(Icons.hourglass_top_rounded, color: Color(0xFF7A5300)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${pending['amount_label']} en attente de versement\n${pending['destination']}',
                    style: const TextStyle(color: Color(0xFF7A5300), fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: _busy ? null : () => _cancel(pending['reference'].toString()), child: const Text('Annuler')),
            ]),
          ),
        ] else if (available < minimum)
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Le retrait sera possible dès que le minimum sera atteint.', style: TextStyle(color: Y.ardoise, fontSize: 13))),
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Divider(height: 1),
          for (final w in history)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${w['amount_label']} · ${w['method_label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${w['created_at']}${w['transaction_ref'] != null ? ' · réf. ${w['transaction_ref']}' : ''}', style: const TextStyle(color: Y.ardoise, fontSize: 12)),
                    if (w['status'] == 'rejected' && w['admin_note'] != null)
                      Text('Motif : ${w['admin_note']}', style: const TextStyle(color: Y.alerte, fontSize: 12)),
                  ]),
                ),
                _StatusChip(status: w['status'].toString(), label: w['status_label'].toString()),
              ]),
            ),
        ],
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
