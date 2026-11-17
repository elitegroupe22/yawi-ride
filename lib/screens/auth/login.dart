import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Saisissez votre numéro (ou e-mail) et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().login(_login.text.trim(), _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pas de réinitialisation automatique : le support vérifie l'identité puis réinitialise.
  void _forgot() {
    final c = context.read<Session>().contact;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Mot de passe oublié', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Contactez le support Yawi depuis le numéro de votre compte : nous vérifions votre identité puis réinitialisons votre mot de passe.',
                style: TextStyle(height: 1.4)),
            const SizedBox(height: 18),
            if ((c['phone'] ?? '').toString().isNotEmpty)
              FilledButton.icon(onPressed: () => dial(c['phone'].toString()), icon: const Icon(Icons.call), label: Text('Appeler ${c['phone']}')),
            if ((c['whatsapp'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => openExternal('https://wa.me/${c['whatsapp'].toString().replaceAll(RegExp(r'[^0-9]'), '')}'),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Écrire sur WhatsApp'),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          const Text('Bon retour', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Connectez-vous avec votre numéro de téléphone ou votre e-mail.', style: TextStyle(color: Color(0xFF5A6678), fontSize: 15)),
          const SizedBox(height: 28),
          TextField(
            controller: _login,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.telephoneNumber, AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Téléphone ou e-mail', hintText: '620 00 00 00', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Afficher' : 'Masquer',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Color(0xFFC8102E), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 24),
          BusyButton(label: 'Se connecter', busy: _busy, onPressed: _submit),
          const SizedBox(height: 8),
          TextButton(onPressed: _forgot, child: const Text('Mot de passe oublié ?')),
        ]),
      ),
    );
  }
}
