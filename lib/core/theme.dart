import 'package:flutter/material.dart';

/// Charte Yawi : mêmes couleurs que le site (resources/css/yawi.css).
class Y {
  static const nuit = Color(0xFF1B2735);
  static const nuit2 = Color(0xFF26364A);
  static const nuit3 = Color(0xFF34465D);
  static const braise = Color(0xFFF94304);
  static const braiseBtn = Color(0xFFD93A00);
  static const braiseClair = Color(0xFFFF6A33);
  static const braiseVoile = Color(0xFFFFF0E8);
  static const brume = Color(0xFFEEF1F5);
  static const craie = Colors.white;
  static const trait = Color(0xFFDEE3EA);
  static const ardoise = Color(0xFF5A6678);
  static const feuille = Color(0xFF0F9D63);
  static const feuilleVoile = Color(0xFFE3F6EE);
  static const alerte = Color(0xFFC8102E);

  static const rCard = 20.0;
  static const rCtrl = 14.0;
  static const rSheet = 28.0;

  static const display = 'Boldonse';
  static const texte = 'Instrument Sans';

  static List<BoxShadow> get ombre => const [BoxShadow(color: Color(0x2E1B2735), blurRadius: 30, offset: Offset(0, 10))];
}

/// Couleurs d'une course selon son statut (identiques aux pastilles du site).
class StatusColors {
  const StatusColors(this.text, this.background, this.border);
  final Color text;
  final Color background;
  final Color border;

  static StatusColors of(String? status) => switch (status) {
        'requested' => const StatusColors(Color(0xFF8A5A00), Color(0xFFFFF4D6), Color(0xFFE0A100)),
        'accepted' => const StatusColors(Color(0xFF1D4FB8), Color(0xFFE5EEFF), Color(0xFF2F6FDB)),
        'arrived' => const StatusColors(Color(0xFF0B6E8A), Color(0xFFDFF4F8), Color(0xFF0B8FB3)),
        'in_progress' => const StatusColors(Color(0xFFA23000), Y.braiseVoile, Y.braise),
        'completed' => const StatusColors(Color(0xFF0A6B44), Color(0xFFE3F6EE), Color(0xFF0F9D63)),
        'cancelled' => const StatusColors(Color(0xFFA50E26), Color(0xFFFDE8EB), Color(0xFFD4213D)),
        _ => const StatusColors(Y.ardoise, Y.brume, Color(0xFF9AA4B2)),
      };

  static IconData icon(String? status) => switch (status) {
        'requested' => Icons.radar,
        'accepted' => Icons.directions_car_filled,
        'arrived' => Icons.place,
        'in_progress' => Icons.route,
        'completed' => Icons.check_circle,
        'cancelled' => Icons.cancel,
        _ => Icons.schedule,
      };
}

ThemeData yawiTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Y.braise,
    primary: Y.braiseBtn,
    onPrimary: Colors.white,
    secondary: Y.nuit,
    surface: Y.craie,
    error: Y.alerte,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: Y.texte, scaffoldBackgroundColor: Y.brume);
  final ctrl = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Y.rCtrl));

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Y.nuit, displayColor: Y.nuit),
    appBarTheme: const AppBarTheme(
      backgroundColor: Y.brume,
      foregroundColor: Y.nuit,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: Y.texte, fontSize: 20, fontWeight: FontWeight.w700, color: Y.nuit),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Y.braiseBtn,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Y.trait,
        minimumSize: const Size.fromHeight(54),
        shape: ctrl,
        textStyle: const TextStyle(fontFamily: Y.texte, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Y.nuit,
        minimumSize: const Size.fromHeight(54),
        side: const BorderSide(color: Y.trait, width: 1.5),
        shape: ctrl,
        textStyle: const TextStyle(fontFamily: Y.texte, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Y.braiseBtn, textStyle: const TextStyle(fontFamily: Y.texte, fontWeight: FontWeight.w700)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Y.craie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Y.rCtrl), borderSide: const BorderSide(color: Y.trait)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Y.rCtrl), borderSide: const BorderSide(color: Y.trait, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Y.rCtrl), borderSide: const BorderSide(color: Y.nuit, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Y.rCtrl), borderSide: const BorderSide(color: Y.alerte, width: 1.5)),
      labelStyle: const TextStyle(color: Y.ardoise),
      floatingLabelStyle: const TextStyle(color: Y.nuit, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Y.craie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Y.rCard)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Y.craie,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Y.rSheet))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Y.craie,
      indicatorColor: Y.braiseVoile,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: Y.texte,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w400,
            color: s.contains(WidgetState.selected) ? Y.nuit : Y.ardoise,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? Y.braiseBtn : Y.ardoise)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Y.craie,
      selectedColor: Y.nuit,
      side: const BorderSide(color: Y.trait),
      labelStyle: const TextStyle(fontFamily: Y.texte, fontWeight: FontWeight.w700, color: Y.nuit),
      secondaryLabelStyle: const TextStyle(fontFamily: Y.texte, fontWeight: FontWeight.w700, color: Colors.white),
      shape: const StadiumBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Y.nuit,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Y.rCtrl)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : Y.ardoise),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Y.feuille : Y.trait),
    ),
  );
}
