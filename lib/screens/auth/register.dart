import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../common/web_page.dart';

/// Inscription réduite au strict nécessaire ; le dossier chauffeur se complète ensuite.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.role});
  final String role;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _terms = false;
  bool _busy = false;
  bool _hidden = true;
  ApiException? _error;

  bool get _driver => widget.role == 'driver';

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    var phone = _phone.text.replaceAll(RegExp(r'[\s.-]'), '');
    if (phone.isNotEmpty && !phone.startsWith('+') && !phone.startsWith('224')) phone = '+224$phone';
    try {
      await context.read<Session>().register({
        'role': widget.role,
        'name': _name.text.trim(),
        'phone': phone,
        'password': _password.text,
        'terms': _terms,
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
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
    final legal = Map<String, dynamic>.from(context.read<Session>().config['legal'] as Map? ?? {});
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          Text(_driver ? 'Devenir chauffeur' : 'Créer votre compte', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            _driver
                ? 'Trois informations pour commencer. Vous compléterez ensuite votre dossier (pièces et engin) depuis l\'application.'
                : 'Trois informations et vous pouvez commander votre première course.',
            style: const TextStyle(color: Y.ardoise, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: 'Nom complet', prefixIcon: const Icon(Icons.badge_outlined), errorText: _err('name')),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Téléphone',
              hintText: '620 00 00 00',
              prefixIcon: const Icon(Icons.phone_outlined),
              prefixText: '+224 ',
              errorText: _err('phone'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              helperText: '8 caractères minimum',
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: _err('password'),
              suffixIcon: IconButton(
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: _terms, onChanged: (v) => setState(() => _terms = v ?? false), activeColor: Y.braiseBtn),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(TextSpan(style: const TextStyle(color: Y.ardoise, height: 1.4), children: [
                  const TextSpan(text: 'J\'accepte les '),
                  TextSpan(
                    text: 'conditions d\'utilisation',
                    style: const TextStyle(color: Y.braiseBtn, fontWeight: FontWeight.w700),
                    recognizer: TapGestureRecognizer()..onTap = () => WebPage.open(context, title: 'Conditions', url: legal['terms']?.toString(), signedIn: false),
                  ),
                  const TextSpan(text: ' et la '),
                  TextSpan(
                    text: 'politique de confidentialité',
                    style: const TextStyle(color: Y.braiseBtn, fontWeight: FontWeight.w700),
                    recognizer: TapGestureRecognizer()..onTap = () => WebPage.open(context, title: 'Confidentialité', url: legal['privacy']?.toString(), signedIn: false),
                  ),
                  const TextSpan(text: '.'),
                ])),
              ),
            ),
          ]),
          if (_err('terms') != null) Text(_err('terms')!, style: const TextStyle(color: Y.alerte, fontWeight: FontWeight.w700)),
          if (_error != null && _error!.errors.isEmpty) ...[
            const SizedBox(height: 8),
            Text(_error!.message, style: const TextStyle(color: Y.alerte, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 22),
          BusyButton(label: 'Créer mon compte', busy: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
