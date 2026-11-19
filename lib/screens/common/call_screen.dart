import 'package:flutter/material.dart';

import '../../core/calls.dart';
import '../../core/theme.dart';

/// Écran d'appel par internet : nom, état, durée, micro, haut-parleur, raccrocher.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  static bool _open = false;

  static void show(NavigatorState nav) {
    if (_open) return;
    _open = true;
    nav.push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const CallScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    )).whenComplete(() {
      _open = false;
      Calls.instance.dismiss();
    });
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final calls = Calls.instance;

  @override
  void initState() {
    super.initState();
    calls.addListener(_changed);
  }

  @override
  void dispose() {
    calls.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (calls.phase == CallPhase.ended) {
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted && calls.phase == CallPhase.ended) Navigator.of(context).maybePop();
      });
    }
  }

  String get _status => switch (calls.phase) {
        CallPhase.connecting => 'Connexion…',
        CallPhase.ringing => 'Ça sonne…',
        CallPhase.incoming => 'Appel entrant',
        CallPhase.talking => _fmt(calls.elapsed),
        CallPhase.ended => calls.endReason ?? 'Appel terminé',
        CallPhase.idle => '',
      };

  static String _fmt(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  String get _initials {
    final parts = calls.otherName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
    return parts.isEmpty ? '…' : parts.map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final live = calls.busy;
    return PopScope(
      canPop: !live,
      child: Scaffold(
        backgroundColor: Y.nuit,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.lock_outline, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                const Expanded(child: Text('Appel Yawi par internet · numéro masqué', style: TextStyle(color: Colors.white60, fontSize: 13))),
              ]),
              const Spacer(),
              _Avatar(initials: _initials, pulsing: calls.phase == CallPhase.ringing || calls.phase == CallPhase.connecting),
              const SizedBox(height: 24),
              Text(calls.otherName.isEmpty ? 'Appel' : calls.otherName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
              if (calls.otherDetail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(calls.otherDetail, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ),
              const SizedBox(height: 14),
              Text(_status,
                  style: TextStyle(
                    color: calls.phase == CallPhase.ended ? Y.braiseClair : Colors.white,
                    fontSize: 18,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const Spacer(flex: 2),
              if (live)
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _RoundButton(
                    icon: calls.muted ? Icons.mic_off : Icons.mic_none,
                    label: calls.muted ? 'Micro coupé' : 'Micro',
                    active: calls.muted,
                    onTap: calls.toggleMute,
                  ),
                  _RoundButton(
                    icon: Icons.call_end,
                    label: 'Raccrocher',
                    big: true,
                    color: Y.alerte,
                    onTap: () => calls.hangUp(),
                  ),
                  _RoundButton(
                    icon: calls.speaker ? Icons.volume_up : Icons.volume_down_outlined,
                    label: 'Haut-parleur',
                    active: calls.speaker,
                    onTap: calls.toggleSpeaker,
                  ),
                ])
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Y.nuit, minimumSize: const Size.fromHeight(54)),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Fermer'),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatefulWidget {
  const _Avatar({required this.initials, required this.pulsing});
  final String initials;
  final bool pulsing;

  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didUpdateWidget(_Avatar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.pulsing && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      height: 168,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Stack(alignment: Alignment.center, children: [
          if (widget.pulsing)
            Container(
              width: 120 + 48 * _c.value,
              height: 120 + 48 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .18 * (1 - _c.value))),
            ),
          child!,
        ]),
        child: Container(
          width: 120,
          height: 120,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Y.nuit3),
          child: Text(widget.initials, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.active = false, this.big = false, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool big;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final size = big ? 76.0 : 62.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: label,
        toggled: big ? null : active,
        child: Material(
          color: color ?? (active ? Colors.white : Y.nuit3),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, size: big ? 34 : 28, color: active && color == null ? Y.nuit : Colors.white)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
    ]);
  }
}
