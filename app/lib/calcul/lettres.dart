/// Écrit un montant entier en toutes lettres (français), pour la mention
/// « Arrêtée la présente facture à la somme de … ».
String enLettres(int n) {
  if (n == 0) return 'zéro';
  if (n < 0) return 'moins ${enLettres(-n)}';

  final milliards = n ~/ 1000000000;
  final millions = (n ~/ 1000000) % 1000;
  final milliers = (n ~/ 1000) % 1000;
  final reste = n % 1000;

  final parts = <String>[];
  if (milliards > 0) parts.add('${_sous1000(milliards)} milliard${milliards > 1 ? 's' : ''}');
  if (millions > 0) parts.add('${_sous1000(millions)} million${millions > 1 ? 's' : ''}');
  if (milliers > 0) {
    // « mille » est invariable et « cent » / « vingt » perdent leur s devant lui.
    parts.add(milliers == 1
        ? 'mille'
        : '${_sous1000(milliers)} mille'.replaceAll('cents mille', 'cent mille').replaceAll('vingts mille', 'vingt mille'));
  }
  if (reste > 0) parts.add(_sous1000(reste));
  return parts.join(' ');
}

const _unites = [
  'zéro', 'un', 'deux', 'trois', 'quatre', 'cinq', 'six', 'sept', 'huit', 'neuf', 'dix',
  'onze', 'douze', 'treize', 'quatorze', 'quinze', 'seize',
];

const _dizaines = {2: 'vingt', 3: 'trente', 4: 'quarante', 5: 'cinquante', 6: 'soixante'};

String _sous100(int n) {
  if (n < 17) return _unites[n];
  if (n < 20) return 'dix-${_unites[n - 10]}';
  final d = n ~/ 10;
  final u = n % 10;
  if (d <= 6) {
    if (u == 0) return _dizaines[d]!;
    if (u == 1) return '${_dizaines[d]} et un';
    return '${_dizaines[d]}-${_unites[u]}';
  }
  if (d == 7) return u == 1 ? 'soixante et onze' : 'soixante-${_sous100(10 + u)}';
  if (n == 80) return 'quatre-vingts';
  return 'quatre-vingt-${_sous100(n - 80)}';
}

String _sous1000(int n) {
  final c = n ~/ 100;
  final r = n % 100;
  var s = '';
  if (c == 1) {
    s = 'cent';
  } else if (c > 1) {
    s = '${_unites[c]} cent${r == 0 ? 's' : ''}';
  }
  if (r > 0) s = s.isEmpty ? _sous100(r) : '$s ${_sous100(r)}';
  return s;
}
