import 'package:flutter_test/flutter_test.dart';
import 'package:yawi/core/theme.dart';
import 'package:yawi/widgets/ui.dart';

void main() {
  test('montants en francs guinéens avec espaces fines', () {
    expect(money(25000), '25 000 GNF');
    expect(money(1500000), '1 500 000 GNF');
    expect(money(-3000), '−3 000 GNF');
    expect(money(0), '0 GNF');
  });

  test('chaque statut de course a sa couleur', () {
    for (final s in ['requested', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled', 'expired']) {
      expect(StatusColors.of(s).text, isNotNull);
    }
    expect(StatusColors.of('completed').border, isNot(StatusColors.of('cancelled').border));
  });
}
