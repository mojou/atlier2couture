import 'package:flutter/material.dart';

import '../core/constantes.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../services/alarmes.dart';
import '../core/format.dart';
import '../core/support.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config.dart';
import 'abonnement_screen.dart';
import 'caisse_screen.dart';
import 'exports_screen.dart';
import 'paie_screen.dart';
import 'admin_screen.dart';
import 'rappels_screen.dart';
import 'statistiques_screen.dart';
import 'atelier_form_screen.dart';
import 'calculateur_screen.dart';
import 'documents_screen.dart';
import 'membres_screen.dart';
import 'modeles_screen.dart';
import 'stock_screen.dart';

class PlusScreen extends StatefulWidget {
  const PlusScreen({super.key});

  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  String? _sonnerie;

  @override
  void initState() {
    super.initState();
    Alarmes.sonnerieDefaut().then((s) {
      if (mounted) setState(() => _sonnerie = s);
    });
  }

  /// Au retour, on redessine : la formule a pu changer (paiement).
  Future<void> _ouvrir(Widget ecran) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));
    if (mounted) setState(() {});
  }

  Future<void> _choisirSonnerie() async {
    final chemin = await Alarmes.choisirMusique();
    if (chemin == null) return;
    await Alarmes.definirSonnerieDefaut(chemin);
    await Alarmes.synchroniser();
    if (mounted) setState(() => _sonnerie = chemin);
  }

  /// Ouvre l'écran si la formule le permet, sinon propose de changer de formule.
  void _ouvrirSi(bool inclus, String message, Widget ecran) {
    if (inclus) {
      _ouvrir(ecran);
    } else {
      proposerFormule(context, message);
    }
  }

  Widget? _cadenas(bool inclus) =>
      inclus ? null : const Icon(Icons.lock_outline, size: 20);

  @override
  Widget build(BuildContext context) {
    final s = Session.instance;
    final o = s.offre;
    return Scaffold(
      appBar: AppBar(title: const Text('Plus')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.workspace_premium, color: Colors.amber),
          title: const Text('Mon abonnement'),
          subtitle: Text('Formule ${o.nom}'
              '${s.formule != 'gratuit' && s.formuleFin != null ? ' jusqu\'au ${dateCourte(s.formuleFin)}' : ' · passer à Standard ou Premium'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _ouvrir(const AbonnementScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.straighten),
          title: const Text('Calculateur de métrage'),
          subtitle: const Text(
              'Pièces zone par zone, plan de coupe, quantité à acheter'),
          onTap: () => _ouvrir(const CalculateurScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Devis et factures'),
          onTap: () => _ouvrir(const DocumentsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('Stock'),
          subtitle: const Text('Tissus, doublures, fils, boutons, fermetures…'),
          trailing: _cadenas(o.stock),
          onTap: () => _ouvrirSi(
              o.stock,
              'La gestion du stock est disponible à partir de la formule Standard.',
              const StockScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.style_outlined),
          title: const Text('Catalogue de modèles'),
          subtitle: const Text('Prix de façon par modèle'),
          onTap: () => _ouvrir(const ModelesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.insights_outlined),
          title: const Text('Statistiques avancées'),
          subtitle: const Text(
              'Chiffre d\'affaires par mois, meilleurs clients, modèles phares'),
          trailing: _cadenas(o.premium),
          onTap: () => _ouvrirSi(
              o.premium,
              'Les statistiques avancées sont incluses dans la formule Premium.',
              const StatistiquesScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.forum_outlined),
          title: const Text('Rappels WhatsApp groupés'),
          subtitle:
              const Text('Rendez-vous de demain, commandes prêtes, impayés'),
          trailing: _cadenas(o.premium),
          onTap: () => _ouvrirSi(
              o.premium,
              'Les rappels WhatsApp groupés sont inclus dans la formule Premium.',
              const RappelsScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Caisse et dépenses'),
          subtitle: const Text('Encaissements, dépenses et bénéfice du mois'),
          onTap: () => _ouvrir(const CaisseScreen()),
        ),
        if (s.estGestionnaire)
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Paie des couturiers'),
            subtitle: const Text('À la pièce ou au pourcentage de la façon'),
            onTap: () => _ouvrir(const PaieScreen()),
          ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Exporter mes données'),
          subtitle: const Text('Clients, commandes, factures… vers Excel'),
          onTap: () => _ouvrir(const ExportsScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.library_music_outlined),
          title: const Text('Sonnerie des rendez-vous'),
          subtitle: Text(!o.alarmes
              ? 'Alarmes musicales : à partir de la formule Standard'
              : Alarmes.supporte
                  ? Alarmes.nomFichier(_sonnerie)
                  : 'Les alarmes sonnent uniquement sur l\'application mobile'),
          onTap: !o.alarmes
              ? () => proposerFormule(context,
                  'Les alarmes musicales des rendez-vous sont disponibles à partir de la formule Standard.')
              : Alarmes.supporte
                  ? _choisirSonnerie
                  : null,
          trailing: !o.alarmes
              ? _cadenas(false)
              : Alarmes.supporte
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'tester') {
                          await Alarmes.demanderPermissions();
                          await Alarmes.tester();
                          if (context.mounted) {
                            snack(context,
                                'L\'alarme de test va sonner dans 5 secondes');
                          }
                        } else {
                          await Alarmes.definirSonnerieDefaut(null);
                          setState(() => _sonnerie = null);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'tester', child: Text('Tester la sonnerie')),
                        PopupMenuItem(
                            value: 'bip',
                            child: Text('Revenir au bip par défaut')),
                      ],
                    )
                  : null,
        ),
        const Divider(),
        if (s.superAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings,
                color: Colors.deepPurple),
            title: const Text('Administration de la plateforme'),
            subtitle: const Text(
                'Activer, suspendre ou supprimer les ateliers et les comptes'),
            onTap: () => _ouvrir(const AdminScreen()),
          ),
        if (s.estGestionnaire)
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('Paramètres de l\'atelier'),
            subtitle: const Text('Logo, coordonnées, devise, unité, TVA'),
            onTap: () => _ouvrir(AtelierFormScreen(atelier: s.atelier)),
          ),
        ListTile(
          leading: const Icon(Icons.groups_outlined),
          title: const Text('Équipe'),
          subtitle: Text('Votre rôle : ${roles[s.role] ?? s.role}'),
          onTap: () => _ouvrir(const MembresScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Contacter le support'),
          subtitle: const Text('WhatsApp $supportWhatsApp · $supportEmail'),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (c) => const SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: BlocSupport(titre: 'Support Atelier Couture'),
              ),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Confidentialité et conditions'),
          subtitle:
              const Text('Politique de confidentialité, CGU, mentions légales'),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final (titre, page) in const [
                  ('Politique de confidentialité', 'confidentialite.html'),
                  ('Conditions générales d\'utilisation', 'cgu.html'),
                  ('Mentions légales', 'mentions-legales.html'),
                ])
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: Text(titre),
                    onTap: () => launchUrl(
                      Uri.parse(Config.siteUrl.isNotEmpty
                              ? Config.siteUrl
                              : 'https://atelier2couture.netlify.app/')
                          .resolve('/$page'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
              ]),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.swap_horiz),
          title: const Text('Changer d\'atelier'),
          onTap: () => Session.instance.vider(),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Se déconnecter'),
          subtitle: Text(supa.auth.currentUser?.email ?? ''),
          onTap: () async {
            if (await confirmer(
                context, 'Déconnexion', 'Voulez-vous vous déconnecter ?',
                ok: 'Se déconnecter')) {
              Session.instance.vider();
              await supa.auth.signOut();
            }
          },
        ),
      ]),
    );
  }
}
