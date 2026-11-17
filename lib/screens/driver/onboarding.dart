import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/web_page.dart';

/// Dossier chauffeur : profil → pièces (KYC) → engin → validation par l'équipe Yawi.
/// La saisie se fait dans les écrans du site (envoi de photos et PDF), ouverts dans l'application.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      final res = await session.api.get('/driver/onboarding');
      if (!mounted) return;
      setState(() {
        _data = res;
        _error = null;
      });
      session.updateUser(res['user']); // bascule vers le tableau de bord dès la validation
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open(String title, String path) async {
    await WebPage.open(context, title: title, path: path);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      return Scaffold(appBar: AppBar(title: const Text('Mon dossier')), body: _error != null ? RetryView(message: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final steps = ((d['steps'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final docs = ((d['documents'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final paths = Map<String, dynamic>.from(d['paths'] as Map? ?? {});
    final driver = Map<String, dynamic>.from(d['user']?['driver'] as Map? ?? {});
    final done = steps.where((s) => s['done'] == true).length;
    final status = driver['status']?.toString();
    final pending = status == 'pending';
    final rejected = status == 'rejected' || status == 'suspended';
    final next = steps.where((s) => s['done'] != true).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon dossier chauffeur')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Y.nuit, borderRadius: BorderRadius.circular(Y.rCard)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                pending ? 'Dossier en cours de vérification' : (rejected ? 'Dossier à corriger' : 'Bienvenue, ${context.read<Session>().firstName}'),
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                pending
                    ? 'Notre équipe vérifie vos pièces, généralement sous 24 h. Vous recevrez une notification dès la validation.'
                    : 'Complétez les étapes ci-dessous pour recevoir vos premières courses.',
                style: const TextStyle(color: Color(0xFFC9D2DE), height: 1.4),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: steps.isEmpty ? 0 : done / steps.length, minHeight: 8, color: Y.braise, backgroundColor: Y.nuit3),
              ),
              const SizedBox(height: 6),
              Text('$done sur ${steps.length} étapes', style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 13)),
            ]),
          ),
          const SectionTitle('Étapes'),
          for (final s in steps) ...[
            Panel(
              border: s == next ? Y.braise : null,
              onTap: s['open'] == false ? null : () => _open(s['label'].toString(), _pathFor(s['key'].toString(), paths)),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: s['done'] == true ? Y.feuilleVoile : (s == next ? Y.braiseVoile : Y.brume),
                  child: Icon(
                    s['done'] == true ? Icons.check : _stepIcon(s['key'].toString()),
                    color: s['done'] == true ? Y.feuille : (s == next ? Y.braiseBtn : Y.ardoise),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(s['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                if (s['open'] != false) const Icon(Icons.chevron_right, color: Y.ardoise),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          if (docs.isNotEmpty) ...[
            const SectionTitle('Pièces justificatives'),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final doc in docs)
                  ListTile(
                    title: Text(doc['label'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: doc['reason'] != null ? Text(doc['reason'].toString(), style: const TextStyle(color: Y.alerte)) : (doc['required'] == true ? null : const Text('Facultatif')),
                    trailing: _docBadge(doc['status']?.toString()),
                    onTap: () => _open('Pièces', paths['documents'].toString()),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          if (next != null && !pending)
            FilledButton(onPressed: () => _open(next['label'].toString(), _pathFor(next['key'].toString(), paths)), child: Text('Continuer : ${next['label']}'))
          else
            OutlinedButton(onPressed: () => _open('Mon dossier', paths['overview'].toString()), child: const Text('Voir mon dossier')),
        ]),
      ),
    );
  }

  String _pathFor(String key, Map<String, dynamic> paths) {
    final path = switch (key) {
      'profile' || 'profil' => paths['profile'],
      'documents' || 'pieces' => paths['documents'],
      'vehicle' || 'engin' => paths['vehicle'],
      _ => paths['overview'],
    };
    return path.toString();
  }

  IconData _stepIcon(String key) => switch (key) {
        'profile' || 'profil' => Icons.person_outline,
        'documents' || 'pieces' => Icons.badge_outlined,
        'vehicle' || 'engin' => Icons.two_wheeler,
        _ => Icons.fact_check_outlined,
      };

  Widget _docBadge(String? status) {
    final (label, fg, bg) = switch (status) {
      'approved' => ('Validée', const Color(0xFF0A6B44), Y.feuilleVoile),
      'pending' => ('En vérification', const Color(0xFF8A5A00), const Color(0xFFFFF4D6)),
      'rejected' => ('Refusée', const Color(0xFFA50E26), const Color(0xFFFDE8EB)),
      _ => ('À envoyer', Y.ardoise, Y.brume),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}
