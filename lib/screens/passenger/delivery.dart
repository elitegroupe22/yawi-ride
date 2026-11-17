import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/place_search.dart';
import 'booking.dart' show serviceIcon;

/// Envoi d'un colis : adresses, destinataire, type de colis, service, qui paie.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, this.pickup, required this.dropoff});
  final Place? pickup;
  final Place dropoff;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  Place? _from;
  late Place _to;
  late final TextEditingController _senderName;
  late final TextEditingController _senderPhone;
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  final _pickupNote = TextEditingController();
  final _dropoffNote = TextEditingController();
  String _parcel = 'small';
  bool _fragile = false;
  String _payer = 'sender';
  String _payment = 'cash';
  List<Map<String, dynamic>> _services = [];
  int? _service;
  bool _estimating = false;
  bool _sending = false;
  ApiException? _error;

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    final u = context.read<Session>().user;
    _senderName = TextEditingController(text: u['name']?.toString() ?? '');
    _senderPhone = TextEditingController(text: u['phone']?.toString() ?? '');
    _from = widget.pickup;
    _to = widget.dropoff;
    WidgetsBinding.instance.addPostFrameCallback((_) => _estimate());
  }

  Future<void> _estimate() async {
    if (_from == null) return;
    setState(() => _estimating = true);
    try {
      final res = await _api.post('/estimate', {
        'pickup_lat': _from!.lat, 'pickup_lng': _from!.lng, 'dropoff_lat': _to.lat, 'dropoff_lng': _to.lng,
        'parcel_type': _parcel, 'parcel_fragile': _fragile,
      });
      if (!mounted) return;
      setState(() {
        _services = ((res['services'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((s) => s['allowed'] != false).toList();
        if (!_services.any((s) => s['id'] == _service)) {
          _service = _services.isEmpty ? null : (_services.firstWhere((s) => (s['drivers'] ?? 0) > 0, orElse: () => _services.first))['id'] as int;
        }
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _pick(bool from) async {
    final p = await PlaceSearchScreen.pick(context, title: from ? 'Lieu de collecte' : 'Lieu de livraison');
    if (p == null) return;
    setState(() => from ? _from = p : _to = p);
    _estimate();
  }

  Future<void> _send() async {
    if (_from == null || _service == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await _api.post('/deliveries', {
        'pickup_address': _from!.address, 'pickup_lat': _from!.lat, 'pickup_lng': _from!.lng,
        'dropoff_address': _to.address, 'dropoff_lat': _to.lat, 'dropoff_lng': _to.lng,
        'pickup_instructions': _pickupNote.text.trim(),
        'dropoff_instructions': _dropoffNote.text.trim(),
        'sender_name': _senderName.text.trim(), 'sender_phone': _senderPhone.text.trim(),
        'recipient_name': _recipientName.text.trim(), 'recipient_phone': _recipientPhone.text.trim(),
        'parcel_type': _parcel, 'parcel_fragile': _fragile, 'parcel_description': _description.text.trim(),
        'service_type_id': _service, 'payer': _payer,
        'payment_method': _payer == 'recipient' ? 'cash' : _payment,
      });
      if (mounted) Navigator.of(context).pop(res['reference'].toString());
    } on ApiException catch (e) {
      setState(() => _error = e);
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String? _err(String f) {
    final m = _error?.field(f);
    return m == null || m.isEmpty ? null : m;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final parcels = ((session.config['parcels'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final selected = _services.where((s) => s['id'] == _service).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un colis')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Panel(child: Column(children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.trip_origin, color: Y.feuille),
            title: const Text('Collecte', style: TextStyle(fontSize: 12, color: Y.ardoise)),
            subtitle: Text(_from?.address ?? 'Choisir le lieu de collecte', style: const TextStyle(fontWeight: FontWeight.w700, color: Y.nuit)),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _pick(true),
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on, color: Y.braise),
            title: const Text('Livraison', style: TextStyle(fontSize: 12, color: Y.ardoise)),
            subtitle: Text(_to.address, style: const TextStyle(fontWeight: FontWeight.w700, color: Y.nuit)),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: () => _pick(false),
          ),
        ])),
        const SectionTitle('Le colis'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in parcels)
            ChoiceChip(
              label: Text(p['label'].toString()),
              selected: _parcel == p['key'],
              onSelected: (_) {
                setState(() => _parcel = p['key'].toString());
                _estimate();
              },
            ),
        ]),
        const SizedBox(height: 6),
        Text(parcels.where((p) => p['key'] == _parcel).firstOrNull?['hint']?.toString() ?? '', style: const TextStyle(color: Y.ardoise, fontSize: 13)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _fragile,
          onChanged: (v) {
            setState(() => _fragile = v);
            _estimate();
          },
          title: const Text('Fragile', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Le livreur en prendra un soin particulier.'),
        ),
        TextField(controller: _description, decoration: const InputDecoration(labelText: 'Description (facultatif)', hintText: 'Ex. : carton de chaussures')),
        const SectionTitle('Expéditeur'),
        TextField(controller: _senderName, decoration: InputDecoration(labelText: 'Nom', errorText: _err('sender_name'))),
        const SizedBox(height: 10),
        TextField(controller: _senderPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Téléphone', errorText: _err('sender_phone'))),
        const SizedBox(height: 10),
        TextField(controller: _pickupNote, decoration: const InputDecoration(labelText: 'Indications pour la collecte (facultatif)')),
        const SectionTitle('Destinataire'),
        TextField(controller: _recipientName, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Nom du destinataire', errorText: _err('recipient_name'))),
        const SizedBox(height: 10),
        TextField(
          controller: _recipientPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: 'Téléphone du destinataire', helperText: 'Il recevra un code de livraison à donner au livreur.', errorText: _err('recipient_phone')),
        ),
        const SizedBox(height: 10),
        TextField(controller: _dropoffNote, decoration: const InputDecoration(labelText: 'Indications pour la livraison (facultatif)')),
        const SectionTitle('Service'),
        if (_estimating && _services.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else
          for (final s in _services) ...[
            Panel(
              border: s['id'] == _service ? Y.nuit : Y.trait,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onTap: () => setState(() => _service = s['id'] as int),
              child: Row(children: [
                Icon(serviceIcon(s['icon']?.toString()), color: Y.nuit),
                const SizedBox(width: 12),
                Expanded(child: Text(s['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(s['fare_label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        const SectionTitle('Qui paie ?'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sender', label: Text('Moi')),
            ButtonSegment(value: 'recipient', label: Text('Le destinataire')),
          ],
          selected: {_payer},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _payer = s.first),
        ),
        if (_payer == 'sender') ...[
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: [
              const ButtonSegment(value: 'cash', icon: Icon(Icons.payments_outlined), label: Text('Espèces')),
              ButtonSegment(value: 'wallet', icon: const Icon(Icons.account_balance_wallet_outlined), label: Text(money((session.user['wallet'] as num?) ?? 0))),
            ],
            selected: {_payment},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _payment = s.first),
          ),
        ] else
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('Le destinataire paie en espèces à la livraison.', style: TextStyle(color: Y.ardoise))),
        const SizedBox(height: 24),
        BusyButton(
          label: selected == null ? 'Envoyer le colis' : 'Envoyer · ${selected['fare_label']}',
          busy: _sending,
          onPressed: selected == null || _from == null ? null : _send,
        ),
      ]),
    );
  }
}
