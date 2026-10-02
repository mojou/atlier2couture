import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/supa.dart';

String txt(dynamic v) => (v as String?)?.trim() ?? '';

PdfColor couleurAtelier(Map<String, dynamic> atelier) {
  try {
    return PdfColor.fromHex((atelier['couleur'] as String?) ?? '#7B2D8E');
  } catch (_) {
    return PdfColor.fromHex('#7B2D8E');
  }
}

/// Mélange la couleur avec du blanc : t = 0 donne du blanc, t = 1 la couleur pleine.
PdfColor teinte(PdfColor c, double t) =>
    PdfColor(1 - (1 - c.red) * t, 1 - (1 - c.green) * t, 1 - (1 - c.blue) * t);

/// Chemin du fichier dans le bucket « logos » à partir de son URL publique.
String? cheminLogo(String url) {
  const repere = '/object/public/logos/';
  final i = url.indexOf(repere);
  if (i < 0) return null;
  var chemin = url.substring(i + repere.length);
  final q = chemin.indexOf('?');
  if (q >= 0) chemin = chemin.substring(0, q);
  return Uri.decodeComponent(chemin);
}

/// Logo de l'atelier : téléchargé par le SDK Supabase (authentifié), puis
/// par l'URL publique en secours. Renvoie null si aucun logo n'est lisible.
Future<pw.ImageProvider?> chargerLogo(Map<String, dynamic> atelier) async {
  final url = atelier['logo_url'] as String?;
  if (url == null || url.isEmpty) return null;
  final chemin = cheminLogo(url);
  if (chemin != null) {
    try {
      final octets = await supa.storage.from('logos').download(chemin);
      return pw.MemoryImage(octets);
    } catch (e) {
      debugPrint('Logo : téléchargement Supabase impossible ($e)');
    }
  }
  try {
    return await networkImage(url);
  } catch (e) {
    debugPrint('Logo : chargement par URL impossible ($e)');
    return null;
  }
}
