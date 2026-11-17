import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/web_page.dart';

/// Compte : informations (lecture), modification, mot de passe, support, pages légales, déconnexion, suppression.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final u = session.user;
    final legal = Map<String, dynamic>.from(session.config['legal'] as Map? ?? {});
    final contact = session.contact;

    Widget row(IconData icon, String label, String? value) => ListTile(
          leading: Icon(icon, color: Y.ardoise),
          title: Text(label, style: const TextStyle(fontSize: 13, color: Y.ardoise)),
          subtitle: Text(value == null || value.isEmpty ? 'Non renseigné' : value, style: const TextStyle(fontSize: 16, color: Y.nuit, fontWeight: FontWeight.w700)),
        );

    Widget link(IconData icon, String label, VoidCallback onTap, {Color? color}) => ListTile(
          leading: Icon(icon, color: color ?? Y.nuit),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: color ?? Y.nuit)),
          trailing: const Icon(Icons.chevron_right, color: Y.ardoise),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Mon compte')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Panel(
          child: Row(children: [
            Avatar(initials: u['initials']?.toString() ?? '?', photo: session.driver['photo']?.toString(), size: 60),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u['name']?.toString() ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE0A100)),
                Text(' ${(u['rating'] as num? ?? 5).toStringAsFixed(1)}  ·  ${session.isDriver ? 'Chauffeur' : 'Passager'}', style: const TextStyle(color: Y.ardoise)),
              ]),
            ])),
          ]),
        ),
        const SectionTitle('Mes informations'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            row(Icons.badge_outlined, 'Nom', u['name']?.toString()),
            row(Icons.phone_outlined, 'Téléphone', u['phone']?.toString()),
            row(Icons.mail_outline, 'E-mail', u['email']?.toString()),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Modifier'),
                )),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PasswordScreen())),
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Mot de passe'),
                )),
              ]),
            ),
          ]),
        ),
        const SectionTitle('Aide'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            link(Icons.support_agent, 'Contacter le support', () => WebPage.open(context, title: 'Support', path: '/support')),
            if ((contact['phone'] ?? '').toString().isNotEmpty) link(Icons.call_outlined, 'Appeler Yawi · ${contact['phone']}', () => dial(contact['phone'].toString())),
            if ((contact['whatsapp'] ?? '').toString().isNotEmpty)
              link(Icons.chat_outlined, 'WhatsApp', () => openExternal('https://wa.me/${contact['whatsapp'].toString().replaceAll(RegExp(r'[^0-9]'), '')}')),
            link(Icons.description_outlined, 'Conditions d\'utilisation', () => WebPage.open(context, title: 'Conditions', url: legal['terms']?.toString(), signedIn: false)),
            link(Icons.privacy_tip_outlined, 'Confidentialité', () => WebPage.open(context, title: 'Confidentialité', url: legal['privacy']?.toString(), signedIn: false)),
          ]),
        ),
        const SizedBox(height: 20),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            link(Icons.logout, 'Se déconnecter', () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Se déconnecter ?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rester')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Se déconnecter')),
                  ],
                ),
              );
              if (ok == true && context.mounted) context.read<Session>().logout();
            }),
            link(Icons.delete_outline, 'Supprimer mon compte', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())), color: Y.alerte),
          ]),
        ),
        const SizedBox(height: 18),
        const Center(child: Text('Yawi ${AppConfig.version}', style: TextStyle(color: Y.ardoise, fontSize: 12))),
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name, _phone, _email;
  bool _busy = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final u = context.read<Session>().user;
    _name = TextEditingController(text: u['name']?.toString());
    _phone = TextEditingController(text: u['phone']?.toString());
    _email = TextEditingController(text: u['email']?.toString());
  }

  Future<void> _save() async {
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await session.api.put('/profile', {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim().isEmpty ? null : _email.text.trim()});
      session.updateUser(res['user']);
      if (mounted) {
        toast(context, res['message']?.toString() ?? 'Enregistré.');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _err(String f) {
    final m = _error?.field(f);
    return m == null || m.isEmpty ? null : m;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Modifier mes informations')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Nom complet', errorText: _err('name'))),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Téléphone', errorText: _err('phone'))),
          const SizedBox(height: 12),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'E-mail (facultatif)', errorText: _err('email'))),
          if (_error != null && _error!.errors.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!.message, style: const TextStyle(color: Y.alerte))),
          const SizedBox(height: 22),
          BusyButton(label: 'Enregistrer', busy: _busy, onPressed: _save),
        ]),
      );
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  ApiException? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<Session>().api.put('/profile/password', {
        'current_password': _current.text, 'password': _new.text, 'password_confirmation': _confirm.text,
      });
      if (mounted) {
        toast(context, res['message']?.toString() ?? 'Mot de passe modifié.');
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _err(String f) {
    final m = _error?.field(f);
    return m == null || m.isEmpty ? null : m;
  }

  @override
  Widget build(BuildContext context) {
    final hasPassword = context.read<Session>().user['has_password'] != false;
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (hasPassword) ...[
          TextField(controller: _current, obscureText: true, decoration: InputDecoration(labelText: 'Mot de passe actuel', errorText: _err('current_password'))),
          const SizedBox(height: 12),
        ],
        TextField(controller: _new, obscureText: true, decoration: InputDecoration(labelText: 'Nouveau mot de passe', helperText: '8 caractères minimum', errorText: _err('password'))),
        const SizedBox(height: 12),
        TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmer le nouveau mot de passe')),
        const SizedBox(height: 22),
        BusyButton(label: 'Changer le mot de passe', busy: _busy, onPressed: _save),
      ]),
    );
  }
}

/// Suppression du compte (exigence Google Play) : confirmation écrite et mot de passe.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  bool _lossOk = false;
  bool _busy = false;
  ApiException? _error;

  Future<void> _delete() async {
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.api.delete('/profile', {'confirmation': _confirm.text.trim(), 'password': _password.text, 'solde_perdu': _lossOk});
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await session.forget();
    } on ApiException catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _err(String f) {
    final m = _error?.field(f);
    return m == null || m.isEmpty ? null : m;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final wallet = (session.user['wallet'] as num?)?.toDouble() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Supprimer mon compte')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Panel(
          border: Y.alerte,
          child: Text(
            'La suppression est définitive : vos informations personnelles sont effacées et vous ne pourrez plus vous connecter. '
            'Les traces comptables des courses sont conservées de façon anonyme, comme la loi l\'exige.',
            style: TextStyle(height: 1.45),
          ),
        ),
        const SizedBox(height: 18),
        if (wallet > 0)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _lossOk,
            onChanged: (v) => setState(() => _lossOk = v ?? false),
            title: Text('Je comprends que mon solde de ${money(wallet)} sera perdu.'),
            subtitle: _err('solde_perdu') != null ? Text(_err('solde_perdu')!, style: const TextStyle(color: Y.alerte)) : null,
          ),
        if (session.user['has_password'] != false) ...[
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: 'Mot de passe', errorText: _err('password'))),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _confirm,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: 'Tapez SUPPRIMER pour confirmer', errorText: _err('confirmation')),
        ),
        if (_error != null && _error!.errors.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!.message, style: const TextStyle(color: Y.alerte, fontWeight: FontWeight.w700))),
        const SizedBox(height: 22),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Y.alerte),
          onPressed: _busy ? null : _delete,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Supprimer définitivement'),
        ),
      ]),
    );
  }
}
