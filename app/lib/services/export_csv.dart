import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Construit un CSV lisible directement par Excel en français :
/// séparateur « ; », guillemets si besoin, en-tête UTF-8 (BOM) pour les accents.
Uint8List construireCsv(List<String> entetes, List<List<Object?>> lignes) {
  String cellule(Object? v) {
    if (v == null) return '';
    final s = v is double ? v.toString().replaceAll('.', ',') : v.toString();
    if (s.contains(RegExp(r'[;"\n\r]'))) return '"${s.replaceAll('"', '""')}"';
    return s;
  }

  final b = StringBuffer()..writeln(entetes.map(cellule).join(';'));
  for (final l in lignes) {
    b.writeln(l.map(cellule).join(';'));
  }
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
}

/// Partage (téléphone) ou télécharge (navigateur) le fichier.
Future<void> partagerFichier(Uint8List octets, String nom, {String type = 'text/csv'}) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(octets, mimeType: type, name: nom)],
    fileNameOverrides: [nom],
    subject: nom,
  ));
}
