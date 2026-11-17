import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/theme.dart';

String money(num value, [String currency = 'GNF']) {
  final s = value.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '${value < 0 ? '−' : ''}$b $currency';
}

void toast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(fontWeight: FontWeight.w700)),
    backgroundColor: error ? Y.alerte : Y.nuit,
  ));
}

void toastError(BuildContext context, Object e) =>
    toast(context, e is ApiException ? e.message : 'Une erreur est survenue. Réessayez.', error: true);

Future<void> dial(String? phone) async {
  if (phone == null || phone.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));
}

Future<void> openExternal(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Bouton principal avec indicateur de chargement.
class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon, this.outlined = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    if (outlined) return OutlinedButton(onPressed: busy ? null : onPressed, child: child);
    return FilledButton(onPressed: busy ? null : onPressed, child: child);
  }
}

/// Carte blanche arrondie (équivalent de .surface sur le site).
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.border});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: Y.craie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Y.rCard),
        side: border == null ? BorderSide.none : BorderSide(color: border!, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Pastille de statut de course, aux couleurs du site.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, required this.label});
  final String? status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = StatusColors.of(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(StatusColors.icon(status), size: 14, color: c.text),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(color: Y.braiseVoile, shape: BoxShape.circle),
            child: Icon(icon, color: Y.braiseBtn, size: 30),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: Y.ardoise, height: 1.4)),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ]),
      );
}

/// Écran d'erreur réseau avec bouton « Réessayer ».
class RetryView extends StatelessWidget {
  const RetryView({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Connexion impossible',
          message: message,
          action: SizedBox(width: 200, child: FilledButton(onPressed: onRetry, child: const Text('Réessayer'))),
        ),
      );
}

/// Pastille ronde avec initiales ou photo.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initials, this.photo, this.size = 48, this.dark = true});
  final String initials;
  final String? photo;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: dark ? Y.nuit : Y.braiseVoile, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: photo != null && photo!.isNotEmpty
          ? Image.network(photo!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, __, ___) => _letters())
          : _letters(),
    );
  }

  Widget _letters() => Text(initials, style: TextStyle(color: dark ? Colors.white : Y.braiseBtn, fontWeight: FontWeight.w700, fontSize: size * .36));
}

/// Ligne départ → arrivée avec repères colorés.
class RouteLines extends StatelessWidget {
  const RouteLines({super.key, required this.from, required this.to, this.dense = false});
  final String from;
  final String to;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: dense ? 14 : 15, height: 1.3);
    Widget dot(Color c, {bool square = false}) => Container(
          width: 10, height: 10, margin: const EdgeInsets.only(top: 5),
          decoration: BoxDecoration(color: c, shape: square ? BoxShape.rectangle : BoxShape.circle, borderRadius: square ? BorderRadius.circular(2) : null),
        );
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        dot(Y.feuille), const SizedBox(width: 12),
        Expanded(child: Text(from, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, height: dense ? 10 : 14, color: Y.trait)),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        dot(Y.braise, square: true), const SizedBox(width: 12),
        Expanded(child: Text(to, style: style.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
    ]);
  }
}

/// Champ de recherche arrondi utilisé dans les listes.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller});
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, color: Y.ardoise),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      );
}
