import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets.dart';

String _chiffres(String? tel) => (tel ?? '').replaceAll(RegExp(r'[^0-9]'), '');

Future<void> ouvrirWhatsApp(BuildContext context, String? tel, String message) async {
  final chiffres = _chiffres(tel);
  if (chiffres.isEmpty) {
    snack(context, 'Numéro de téléphone manquant pour ce client', erreur: true);
    return;
  }
  final uri = Uri.parse('https://wa.me/$chiffres?text=${Uri.encodeComponent(message)}');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) snack(context, 'Impossible d\'ouvrir WhatsApp', erreur: true);
}

Future<void> appeler(BuildContext context, String? tel) async {
  if (_chiffres(tel).isEmpty) {
    snack(context, 'Numéro de téléphone manquant', erreur: true);
    return;
  }
  await launchUrl(Uri(scheme: 'tel', path: tel!.replaceAll(' ', '')));
}
