import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/location.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'ui.dart';

const _rouge = Color(0xFFC8102E);

const _motifs = {
  'danger': 'Je suis en danger',
  'agression': 'Agression ou menace',
  'accident': 'Accident',
  'sante': 'Malaise / santé',
  'autre': 'Autre urgence',
};

/// Bouton « Urgence » : alerte immédiate au back-office Yawi avec la position GPS.
class SosButton extends StatelessWidget {
  const SosButton({super.key});

  @override
  Widget build(BuildContext context) => Material(
        color: _rouge,
        shape: const StadiumBorder(),
        elevation: 6,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => SosFlow.start(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sos_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text('Urgence', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class SosFlow {
  static Future<void> start(BuildContext context) async {
    final api = context.read<Session>().api;
    // Une alerte est déjà ouverte : on rouvre son écran.
    try {
      final cur = await api.get('/sos');
      if (cur['alert'] != null && context.mounted) {
        await SosScreen.open(context, Map<String, dynamic>.from(cur['alert'] as Map));
        return;
      }
    } catch (_) {}
    if (!context.mounted) return;

    String motif = 'danger';
    final message = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Vous êtes en danger ?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('L\'équipe Yawi reçoit immédiatement une alerte avec votre position et vous rappelle.', style: TextStyle(color: Y.ardoise, height: 1.4)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _motifs.entries)
                ChoiceChip(label: Text(e.value), selected: motif == e.key, showCheckmark: false, onSelected: (_) => set(() => motif = e.key)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: message, maxLines: 2, maxLength: 500, decoration: const InputDecoration(hintText: 'Précisions (facultatif)', counterText: '')),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _rouge, minimumSize: const Size.fromHeight(58)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.sos_rounded),
              label: const Text('Envoyer l\'alerte', style: TextStyle(fontSize: 17)),
            ),
          ]),
        ),
      ),
    );
    if (go != true || !context.mounted) return;

    HapticFeedback.heavyImpact();
    final pos = await Geo.current();
    try {
      final alert = await api.post('/sos', {
        'reason': motif,
        'message': message.text.trim(),
        'lat': pos.point?.latitude,
        'lng': pos.point?.longitude,
      });
      if (context.mounted) await SosScreen.open(context, alert);
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Envoi impossible. Appelez directement Yawi.', error: true);
        final tel = context.read<Session>().contact['emergency'] ?? context.read<Session>().contact['phone'];
        if (tel != null) dial(tel.toString());
      }
    }
  }
}

/// Écran de l'alerte en cours : état de la prise en charge, appel Yawi, position transmise en continu.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.alert});
  final Map<String, dynamic> alert;

  static Future<void> open(BuildContext context, Map<String, dynamic> alert) =>
      Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SosScreen(alert: alert)));

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late Map<String, dynamic> _a = widget.alert;
  StreamSubscription<Position>? _gps;
  Timer? _poll;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Api get _api => context.read<Session>().api;
  String get _ref => _a['reference'].toString();

  @override
  void initState() {
    super.initState();
    _gps = Geo.stream().listen((p) {
      if (DateTime.now().difference(_last).inSeconds < 12) return;
      _last = DateTime.now();
      _send(p.latitude, p.longitude);
    }, onError: (_) {});
    _poll = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final r = await _api.get('/sos');
        if (!mounted) return;
        if (r['alert'] == null) {
          Navigator.pop(context);
        } else {
          setState(() => _a = Map<String, dynamic>.from(r['alert'] as Map));
        }
      } catch (_) {}
    });
  }

  Future<void> _send(double lat, double lng) async {
    try {
      final a = await _api.post('/sos/$_ref/position', {'lat': lat, 'lng': lng});
      if (mounted) setState(() => _a = a);
    } catch (_) {}
  }

  @override
  void dispose() {
    _gps?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler l\'alerte ?'),
        content: const Text('L\'équipe Yawi sera informée qu\'il s\'agit d\'une fausse alerte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/sos/$_ref/cancel');
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ack = _a['acknowledged'] == true;
    final tel = _a['yawi_phone']?.toString();
    return Scaffold(
      backgroundColor: ack ? Y.feuille : _rouge,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white), tooltip: 'Réduire')),
            const Spacer(),
            Icon(ack ? Icons.verified_user_rounded : Icons.sos_rounded, color: Colors.white, size: 96),
            const SizedBox(height: 20),
            Text(_a['status_label']?.toString() ?? 'Alerte envoyée', textAlign: TextAlign.center, style: const TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 22, height: 1.3)),
            const SizedBox(height: 12),
            Text(
              ack ? '${_a['handler'] ?? 'Un agent'} vous contacte. Gardez votre téléphone près de vous.' : 'Restez en lieu sûr si vous le pouvez. Votre position est transmise tant que l\'alerte est ouverte.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.45),
            ),
            const Spacer(),
            if (tel != null && tel.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Y.nuit, minimumSize: const Size.fromHeight(58)),
                onPressed: () => dial(tel),
                icon: const Icon(Icons.call),
                label: Text('Appeler Yawi · $tel', style: const TextStyle(fontSize: 17)),
              ),
            const SizedBox(height: 12),
            TextButton(onPressed: _cancel, style: TextButton.styleFrom(foregroundColor: Colors.white), child: const Text('C\'était une fausse alerte')),
            Text('Réf. $_ref', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
