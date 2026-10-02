import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact.dart';
import 'widgets.dart';

/// Coordonnées de l'administrateur de la plateforme (support).
const supportWhatsApp = '+237 676 14 33 53';
const supportEmail = 'germbob96@gmail.com';

Future<void> ecrireAuSupport(BuildContext context, {String sujet = ''}) =>
    ouvrirWhatsApp(context, supportWhatsApp, 'Bonjour, je vous contacte depuis Atelier Couture. $sujet'.trim());

Future<void> emailAuSupport(BuildContext context, {String sujet = 'Atelier Couture'}) async {
  final ok = await launchUrl(Uri(scheme: 'mailto', path: supportEmail, query: 'subject=${Uri.encodeComponent(sujet)}'));
  if (!ok && context.mounted) snack(context, 'Écrivez-nous à $supportEmail');
}

/// Bloc « Contacter l'administrateur » : WhatsApp, appel et e-mail.
class BlocSupport extends StatelessWidget {
  const BlocSupport({super.key, this.sujet = '', this.titre = 'Contacter l\'administrateur'});

  final String sujet;
  final String titre;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titre, style: t.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('WhatsApp : $supportWhatsApp\nE-mail : $supportEmail', style: t.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
              onPressed: () => ecrireAuSupport(context, sujet: sujet),
              icon: const Icon(Icons.chat),
              label: const Text('WhatsApp'),
            ),
            OutlinedButton.icon(
              onPressed: () => appeler(context, supportWhatsApp),
              icon: const Icon(Icons.call),
              label: const Text('Appeler'),
            ),
            OutlinedButton.icon(
              onPressed: () => emailAuSupport(context, sujet: sujet.isEmpty ? 'Atelier Couture' : sujet),
              icon: const Icon(Icons.email_outlined),
              label: const Text('E-mail'),
            ),
          ]),
        ]),
      ),
    );
  }
}
