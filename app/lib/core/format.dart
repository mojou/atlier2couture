import 'package:intl/intl.dart';

import 'session.dart';

/// Les formats français utilisent des espaces insécables que la police
/// par défaut des PDF ne sait pas dessiner : on les remplace.
String _nettoyer(String s) => s.replaceAll(' ', ' ').replaceAll(' ', ' ');

String argent(num? v) {
  final s = Session.instance;
  final f = NumberFormat.decimalPatternDigits(locale: 'fr_FR', decimalDigits: s.decimales);
  return _nettoyer('${f.format(v ?? 0)} ${s.devise}');
}

String nombre(num? v, {int max = 2}) {
  final f = NumberFormat.decimalPattern('fr_FR')..maximumFractionDigits = max;
  return _nettoyer(f.format(v ?? 0));
}

/// Valeur éditable dans un champ texte (pas de séparateur de milliers).
String nombreChamp(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll('.', ',');
}

String quantiteTissu(num? v) => '${nombre(v)} ${Session.instance.unite}';

String dateCourte(DateTime? d) => d == null ? '—' : DateFormat('dd/MM/yyyy', 'fr_FR').format(d);
String heure(DateTime d) => DateFormat('HH:mm', 'fr_FR').format(d);
String dateHeure(DateTime d) => DateFormat("dd/MM/yyyy 'à' HH:mm", 'fr_FR').format(d);
String jourLong(DateTime d) => DateFormat('EEEE d MMMM', 'fr_FR').format(d);
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime? lireDate(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

double? lireNombre(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

double num0(dynamic v) => (v as num?)?.toDouble() ?? 0;

DateTime aujourdhui() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}
