import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Résultat d'un pointage, affiché en bas de l'écran de scan.
enum ScanOutcome { boarded, dropped, already, offline, refused, warning }

class ScanResult {
  ScanResult(this.outcome, this.title, this.message, {this.photo, this.initials = '?', this.subtitle});
  final ScanOutcome outcome;
  final String title;
  final String message;
  final String? photo;
  final String initials;
  final String? subtitle;
  final DateTime at = DateTime.now();
}

/// Extrait le code de la carte de ce que lit la caméra : adresse /carte/CODE-v-signature, « YAWI-NV:CODE » ou code seul.
String badgeOf(String raw) {
  final m = RegExp(r'/carte/([A-Za-z0-9]+)-').firstMatch(raw);
  if (m != null) return m.group(1)!.toUpperCase();
  return raw.replaceFirst(RegExp(r'^YAWI-NV:', caseSensitive: false), '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

/// File d'attente des scans faits sans réseau : envoyés dès que la connexion revient, avec l'heure réelle du scan.
class ScanQueue {
  ScanQueue(this.trip);
  final String trip;
  String get _key => 'scans_en_attente_$trip';

  Future<List<Map<String, dynamic>>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> add(String code) async {
    final list = await all();
    if (list.any((e) => badgeOf(e['code'].toString()) == badgeOf(code))) return; // déjà en attente
    list.add({'code': code, 'scanned_at': DateTime.now().toUtc().toIso8601String()});
    await _save(list);
  }

  Future<void> _save(List<Map<String, dynamic>> list) async {
    final p = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      await p.remove(_key);
    } else {
      await p.setString(_key, jsonEncode(list));
    }
  }

  /// Envoie la file. Renvoie les scans refusés par le serveur (carte falsifiée, pas dans la navette…).
  Future<({int sent, List<String> refused, bool stillOffline})> flush(Api api) async {
    final list = await all();
    final rest = <Map<String, dynamic>>[];
    final refused = <String>[];
    var sent = 0;
    var offline = false;
    for (final item in list) {
      if (offline) {
        rest.add(item);
        continue;
      }
      try {
        await api.post('/driver/shuttles/$trip/scan', {'code': item['code'], 'scanned_at': item['scanned_at']});
        sent++;
      } on ApiException catch (e) {
        if (e.offline) {
          offline = true;
          rest.add(item);
        } else {
          refused.add(e.message);
          sent++;
        }
      }
    }
    await _save(rest);
    return (sent: sent, refused: refused, stillOffline: offline);
  }
}

/// Pointage en rafale : la caméra reste ouverte, chaque carte est pointée dès qu'elle passe devant.
/// Son et vibration différents selon le résultat, photo du titulaire pour le contrôle visuel, file hors connexion.
class ShuttleScanScreen extends StatefulWidget {
  const ShuttleScanScreen({super.key, required this.trip, this.onChanged});

  /// Données du trajet (driverPayload) : liste des passagers, utilisée aussi hors connexion.
  final Map<String, dynamic> trip;
  final ValueChanged<Map<String, dynamic>>? onChanged;

  static Future<void> open(BuildContext context, Map<String, dynamic> trip, {ValueChanged<Map<String, dynamic>>? onChanged}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShuttleScanScreen(trip: trip, onChanged: onChanged)));

  @override
  State<ShuttleScanScreen> createState() => _ShuttleScanScreenState();
}

class _ShuttleScanScreenState extends State<ShuttleScanScreen> with WidgetsBindingObserver {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.normal);
  final _player = AudioPlayer(playerId: 'yawi-pointage');
  final _tts = FlutterTts();
  late Map<String, dynamic> _trip = widget.trip;
  late final ScanQueue _queue = ScanQueue(widget.trip['reference'].toString());
  final Map<String, DateTime> _recent = {}; // code → dernier passage (évite les doubles lectures)
  final Set<String> _offlineBoarded = {};
  ScanResult? _last;
  bool _busy = false;
  bool _voice = true;
  int _pending = 0;
  Timer? _sync;

  String get _ref => _trip['reference'].toString();
  bool get _aller => _trip['direction'] == 'aller';
  List<Map<String, dynamic>> get _stops => ((_trip['stops'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.setLanguage('fr-FR');
    _tts.setSpeechRate(0.55);
    _refreshPending();
    _sync = Timer.periodic(const Duration(seconds: 12), (_) => _flush());
    _flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _camera.start();
      _flush();
    } else if (state == AppLifecycleState.paused) {
      _camera.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sync?.cancel();
    _camera.dispose();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _refreshPending() async {
    final n = (await _queue.all()).length;
    if (mounted) setState(() => _pending = n);
  }

  Future<void> _flush() async {
    if (_pending == 0 && (await _queue.all()).isEmpty) return;
    if (!mounted) return;
    final res = await _queue.flush(context.read<Session>().api);
    await _refreshPending();
    if (res.sent > 0) await _reloadTrip();
    for (final msg in res.refused) {
      _feedback(ScanOutcome.refused);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.gpp_bad_outlined, color: Y.alerte, size: 40),
            title: const Text('Carte refusée après vérification'),
            content: Text(msg),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Compris'))],
          ),
        );
      }
    }
  }

  Future<void> _reloadTrip() async {
    try {
      final t = await context.read<Session>().api.get('/driver/shuttles/$_ref');
      if (!mounted) return;
      setState(() {
        _trip = t;
        _offlineBoarded.clear();
      });
      widget.onChanged?.call(t);
    } catch (_) {}
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v == null || v.isEmpty) continue;
      final key = badgeOf(v);
      final seen = _recent[key];
      if (seen != null && DateTime.now().difference(seen).inSeconds < 4) continue; // même carte encore devant la caméra
      _recent[key] = DateTime.now();
      _submit(v);
      break;
    }
  }

  Future<void> _submit(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await context.read<Session>().api.post('/driver/shuttles/$_ref/scan', {'code': code});
      final p = Map<String, dynamic>.from((res['passenger'] as Map?) ?? {});
      final action = res['action']?.toString();
      final outcome = switch (action) { 'dropped' => ScanOutcome.dropped, 'already' => ScanOutcome.already, _ => ScanOutcome.boarded };
      if (res['trip'] is Map) {
        _trip = Map<String, dynamic>.from(res['trip'] as Map);
        widget.onChanged?.call(_trip);
      }
      _show(ScanResult(
        outcome,
        p['name']?.toString() ?? 'Passager',
        switch (outcome) { ScanOutcome.dropped => 'Déposé(e)', ScanOutcome.already => 'Déjà pointé(e)', _ => 'À bord' },
        photo: p['photo']?.toString(),
        initials: p['initials']?.toString() ?? '?',
        subtitle: [p['company'], p['department']].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      ));
      if (outcome != ScanOutcome.already) _say('${_firstName(p['name']?.toString())}, ${outcome == ScanOutcome.dropped ? 'déposé' : 'à bord'}');
    } on ApiException catch (e) {
      if (e.offline) {
        await _offline(code);
      } else {
        final reason = e.body['reason']?.toString();
        final p = e.body['passenger'] is Map ? Map<String, dynamic>.from(e.body['passenger'] as Map) : <String, dynamic>{};
        final grave = reason == 'forged' || reason == 'unknown';
        _show(ScanResult(
          grave ? ScanOutcome.refused : ScanOutcome.warning,
          switch (reason) {
            'forged' => 'Carte non authentique',
            'unknown' => 'Carte inconnue',
            'replaced' => 'Ancienne carte',
            'inactive' => 'Carte suspendue',
            'not_on_trip' => 'Pas dans cette navette',
            _ => p['name']?.toString() ?? 'Pointage impossible',
          },
          e.message,
          photo: p['photo']?.toString(),
          initials: p['initials']?.toString() ?? '!',
          subtitle: p['name']?.toString(),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sans réseau : on reconnaît la personne grâce à la liste du trajet, et le scan part dès le retour du réseau.
  Future<void> _offline(String code) async {
    await _queue.add(code);
    await _refreshPending();
    final badge = badgeOf(code);
    final stop = _stops.where((s) => s['badge']?.toString() == badge).firstOrNull;
    if (stop != null) {
      setState(() => _offlineBoarded.add(badge));
      _show(ScanResult(ScanOutcome.offline, stop['name'].toString(), 'Pointé hors connexion · vérification au retour du réseau',
          photo: stop['photo']?.toString(), initials: stop['initials']?.toString() ?? '?'));
      _say('${_firstName(stop['name']?.toString())}, enregistré');
    } else {
      _show(ScanResult(ScanOutcome.warning, 'Carte non reconnue', 'Hors connexion : cette carte n\'est pas dans la liste du trajet. Elle sera vérifiée au retour du réseau.'));
    }
  }

  String _firstName(String? n) => (n ?? '').split(' ').first;

  void _show(ScanResult r) {
    _feedback(r.outcome);
    if (mounted) setState(() => _last = r);
  }

  Future<void> _feedback(ScanOutcome o) async {
    switch (o) {
      case ScanOutcome.boarded || ScanOutcome.dropped || ScanOutcome.offline:
        HapticFeedback.lightImpact();
        await _player.play(AssetSource('sounds/valide.wav'));
      case ScanOutcome.already:
        HapticFeedback.selectionClick();
      case ScanOutcome.warning:
        HapticFeedback.mediumImpact();
        await _player.play(AssetSource('sounds/attention.wav'));
      case ScanOutcome.refused:
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
        Future.delayed(const Duration(milliseconds: 500), HapticFeedback.heavyImpact);
        await _player.play(AssetSource('sounds/refus.wav'));
    }
  }

  Future<void> _say(String text) async {
    if (!_voice) return;
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Saisir le code de la carte'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'Code imprimé sous le QR (8 caractères)'),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Pointer')),
        ],
      ),
    );
    if (code != null && code.trim().length >= 4) _submit(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final counts = Map<String, dynamic>.from((_trip['counts'] as Map?) ?? {});
    final total = (counts['total'] as num?)?.toInt() ?? 0;
    final done = _aller
        ? ((counts['boarded'] as num?)?.toInt() ?? 0) + ((counts['dropped'] as num?)?.toInt() ?? 0)
        : (counts['dropped'] as num?)?.toInt() ?? 0;
    final boardedReturn = (counts['boarded'] as num?)?.toInt() ?? 0;
    final shown = done + _offlineBoarded.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: MobileScanner(controller: _camera, onDetect: _onDetect)),
        // Fenêtre de visée
        Center(child: _Viseur(active: _busy)),
        // Barre du haut
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Column(children: [
              Row(children: [
                _RoundButton(icon: Icons.arrow_back, onTap: () => Navigator.pop(context), tooltip: 'Retour'),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Pointage · ${_trip['direction_label'] ?? ''} ${_trip['scheduled_at'] ?? ''}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(_trip['company']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 13)),
                  ]),
                ),
                _RoundButton(icon: _voice ? Icons.record_voice_over : Icons.voice_over_off, onTap: () => setState(() => _voice = !_voice), tooltip: 'Annonce vocale'),
                const SizedBox(width: 6),
                ValueListenableBuilder(
                  valueListenable: _camera,
                  builder: (_, state, __) => _RoundButton(
                    icon: state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                    onTap: _camera.toggleTorch,
                    tooltip: 'Lampe',
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // Compteur
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Text('$shown / $total', style: const TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_aller ? 'à bord' : 'déposés${boardedReturn > 0 ? ' · $boardedReturn à bord' : ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(value: total == 0 ? 0 : (shown / total).clamp(0, 1), minHeight: 6, backgroundColor: Colors.white24, color: Y.feuille),
                      ),
                    ]),
                  ),
                  if (_pending > 0) ...[
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Scans en attente de réseau',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFFC94D), borderRadius: BorderRadius.circular(99)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.cloud_off, size: 14, color: Y.nuit),
                          const SizedBox(width: 4),
                          Text('$_pending', style: const TextStyle(color: Y.nuit, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
        ),
        // Résultat + saisie manuelle
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (c, a) => SlideTransition(position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: c)),
                  child: _last == null
                      ? const _Hint(key: ValueKey('hint'))
                      : ScanResultCard(key: ValueKey(_last!.at), r: _last!),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _manual,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), backgroundColor: Colors.black38),
                      icon: const Icon(Icons.keyboard_outlined),
                      label: const Text('Saisir le code'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: .5),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: Colors.white))),
        ),
      );
}

class _Viseur extends StatelessWidget {
  const _Viseur({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * .66;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CornersPainter(active ? Y.braiseClair : Colors.white)),
    );
  }
}

class _CornersPainter extends CustomPainter {
  _CornersPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 34.0;
    for (final (x, y, dx, dy) in [(0.0, 0.0, 1.0, 1.0), (s.width, 0.0, -1.0, 1.0), (0.0, s.height, 1.0, -1.0), (s.width, s.height, -1.0, -1.0)]) {
      canvas.drawLine(Offset(x, y), Offset(x + l * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + l * dy), p);
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}

class _Hint extends StatelessWidget {
  const _Hint({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(Y.rCard)),
        child: const Text('Présentez la carte devant la caméra. Les passagers se pointent les uns après les autres, sans toucher l\'écran.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
      );
}

/// Carte de résultat : couleur selon l'issue, grande photo pour comparer avec la personne.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({super.key, required this.r});
  final ScanResult r;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (r.outcome) {
      ScanOutcome.boarded => (Y.feuille, Colors.white, Icons.check_circle),
      ScanOutcome.dropped => (const Color(0xFF1E6FD9), Colors.white, Icons.where_to_vote),
      ScanOutcome.already => (const Color(0xFF3A4A5F), Colors.white, Icons.done_all),
      ScanOutcome.offline => (const Color(0xFF3A4A5F), Colors.white, Icons.cloud_off),
      ScanOutcome.warning => (const Color(0xFFFFC94D), Y.nuit, Icons.warning_amber_rounded),
      ScanOutcome.refused => (Y.alerte, Colors.white, Icons.gpp_bad),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Y.rCard), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 18, offset: Offset(0, 6))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Photo du titulaire (contrôle visuel)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 72,
            height: 90,
            color: Colors.white24,
            alignment: Alignment.center,
            child: r.photo != null
                ? Image.network(r.photo!, fit: BoxFit.cover, width: 72, height: 90, errorBuilder: (_, __, ___) => _letters(fg))
                : _letters(fg),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 6),
              Expanded(child: Text(r.message.length < 40 ? r.message : '', style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15))),
            ]),
            const SizedBox(height: 4),
            Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 20, height: 1.1)),
            if (r.subtitle != null && r.subtitle!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(r.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .85)))),
            if (r.message.length >= 40) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.message, style: TextStyle(color: fg, fontSize: 13.5, height: 1.25))),
            if (r.photo != null && (r.outcome == ScanOutcome.boarded || r.outcome == ScanOutcome.offline))
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Vérifiez que la photo correspond à la personne.', style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 12.5))),
          ]),
        ),
      ]),
    );
  }

  Widget _letters(Color fg) => Text(r.initials, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 24));
}
