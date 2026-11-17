import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import 'login.dart';
import 'register.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tagline = context.watch<Session>().config['app']?['tagline']?.toString();
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      backgroundColor: Y.nuit,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 28),
            Align(alignment: Alignment.centerLeft, child: Image.asset('assets/images/logo-white.png', height: 44)),
            const Spacer(),
            // Le tracé de la course (départ → arrivée) sert d'illustration
            const _Trajet(),
            const SizedBox(height: 32),
            const Text(
              'Où allez-vous\naujourd\'hui ?',
              style: TextStyle(fontFamily: Y.display, color: Colors.white, fontSize: 30, height: 1.25),
            ),
            const SizedBox(height: 12),
            Text(
              tagline?.isNotEmpty == true ? tagline! : 'Courses et livraisons à Conakry, payées en espèces ou avec votre portefeuille.',
              style: const TextStyle(color: Color(0xFFC9D2DE), fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 32),
            FilledButton(onPressed: () => go(const RegisterScreen(role: 'passenger')), child: const Text('Créer un compte passager')),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Y.nuit3, width: 1.5)),
              onPressed: () => go(const RegisterScreen(role: 'driver')),
              child: const Text('Devenir chauffeur Yawi'),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Y.braiseClair, minimumSize: const Size.fromHeight(48)),
              onPressed: () => go(const LoginScreen()),
              child: const Text('J\'ai déjà un compte · Se connecter'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Petit tracé départ → arrivée dessiné à la main, rappel de la carte.
class _Trajet extends StatelessWidget {
  const _Trajet();

  @override
  Widget build(BuildContext context) => SizedBox(height: 120, child: CustomPaint(painter: _TrajetPainter(), size: Size.infinite));
}

class _TrajetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(12, size.height - 18)
      ..cubicTo(size.width * .30, size.height - 10, size.width * .25, 30, size.width * .55, 40)
      ..cubicTo(size.width * .80, 48, size.width * .72, 14, size.width - 24, 18);
    final dash = Paint()
      ..color = const Color(0xFF34465D)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 16) {
        canvas.drawPath(m.extractPath(d, d + 8), dash);
      }
    }
    canvas.drawCircle(Offset(12, size.height - 18), 9, Paint()..color = Y.feuille);
    canvas.drawCircle(Offset(12, size.height - 18), 9, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);
    final end = Offset(size.width - 24, 18);
    canvas.drawCircle(end, 14, Paint()..color = Y.braise);
    canvas.drawCircle(end, 5, Paint()..color = Y.nuit);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
