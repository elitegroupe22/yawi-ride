import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/calls.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Joindre l'autre partie d'une course : appel Yawi par internet, appel normal ou relance avec sonnerie.
class CallOptions {
  static Future<void> show(
    BuildContext context, {
    required String reference,
    required String name,
    String? phone,
    VoidCallback? onNudge,
  }) async {
    final internet = context.read<Session>().config['features']?['calls'] == true;
    if (!internet && onNudge == null) {
      await dial(phone);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Joindre $name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (internet)
              _Option(
                icon: Icons.wifi_calling_3,
                color: Y.feuille,
                title: 'Appel Yawi',
                subtitle: 'Par internet, gratuit, numéro masqué',
                onTap: () async {
                  Navigator.pop(ctx);
                  final err = await Calls.instance.callRide(reference);
                  if (err != null && context.mounted) toast(context, err, error: true);
                },
              ),
            if (phone != null && phone.isNotEmpty)
              _Option(
                icon: Icons.call_outlined,
                color: Y.nuit,
                title: 'Appel normal',
                subtitle: 'Par le réseau téléphonique ($phone)',
                onTap: () {
                  Navigator.pop(ctx);
                  dial(phone);
                },
              ),
            if (onNudge != null)
              _Option(
                icon: Icons.notifications_active_outlined,
                color: Y.braiseBtn,
                title: 'Relancer avec sonnerie',
                subtitle: 'Son téléphone sonne jusqu\'à ce qu\'il confirme',
                onTap: () {
                  Navigator.pop(ctx);
                  onNudge();
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Y.brume,
          borderRadius: BorderRadius.circular(Y.rCtrl),
          child: InkWell(
            borderRadius: BorderRadius.circular(Y.rCtrl),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(radius: 22, backgroundColor: color, child: Icon(icon, color: Colors.white)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(color: Y.ardoise)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
