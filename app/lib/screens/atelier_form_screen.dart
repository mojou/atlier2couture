import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../pdf/facture_pdf.dart';

/// Création ou modification de l'atelier. Ces informations (logo, nom,
/// coordonnées, identifiants fiscaux) apparaissent sur les devis et factures.
class AtelierFormScreen extends StatefulWidget {
  const AtelierFormScreen({super.key, this.atelier, this.onCree, this.premier = false, this.onAdministration});

  final Map<String, dynamic>? atelier;
  final void Function(String id)? onCree;
  final bool premier;

  /// Accès à l'administration de la plateforme (super administrateur).
  final VoidCallback? onAdministration;

  @override
  State<AtelierFormScreen> createState() => _AtelierFormScreenState();
}

class _AtelierFormScreenState extends State<AtelierFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _unite;
  late String _couleur;
  late String _modeleFacture;
  Uint8List? _logo;
  String _logoExt = 'png';
  bool _occupe = false;

  static const _champsTexte = [
    'nom', 'slogan', 'telephone', 'email', 'adresse', 'ville', 'pays',
    'identifiant_fiscal', 'registre_commerce', 'devise', 'conditions_facture', 'pied_facture',
  ];
  static const _champsNombre = ['largeur_tissu_cm', 'taux_tva', 'acompte_pct', 'validite_devis_jours'];

  @override
  void initState() {
    super.initState();
    final a = widget.atelier ?? const {};
    _c = {
      for (final k in _champsTexte) k: TextEditingController(text: a[k] as String? ?? ''),
      for (final k in _champsNombre) k: TextEditingController(text: nombreChamp(a[k] as num?)),
    };
    if (widget.atelier == null) {
      _c['devise']!.text = 'FCFA';
      _c['largeur_tissu_cm']!.text = '150';
      _c['taux_tva']!.text = '0';
      _c['acompte_pct']!.text = '50';
      _c['validite_devis_jours']!.text = '30';
      _c['conditions_facture']!.text =
          'Un acompte est exigé à la commande. Les vêtements non retirés 60 jours après la date '
          'de livraison ne sont plus sous notre responsabilité.';
      _c['pied_facture']!.text = 'Merci de votre confiance !';
    }
    _unite = a['unite_tissu'] as String? ?? 'yd';
    _couleur = a['couleur'] as String? ?? couleursAtelier.first;
    _modeleFacture = modeleValide(a['modele_facture'] as String?);
  }

  Future<void> _choisirLogo() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final f = r?.files.single;
    if (f?.bytes == null) return;
    if (f!.bytes!.length > 2 * 1024 * 1024) {
      if (mounted) snack(context, 'Logo trop lourd (2 Mo maximum)', erreur: true);
      return;
    }
    setState(() {
      _logo = f.bytes;
      _logoExt = (f.extension ?? 'png').toLowerCase();
    });
  }

  Future<void> _enregistrer() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _occupe = true);
    try {
      final data = <String, dynamic>{
        for (final k in _champsTexte) k: _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim(),
        'largeur_tissu_cm': lireNombre(_c['largeur_tissu_cm']!.text) ?? 150,
        'taux_tva': lireNombre(_c['taux_tva']!.text) ?? 0,
        'acompte_pct': lireNombre(_c['acompte_pct']!.text) ?? 50,
        'validite_devis_jours': (lireNombre(_c['validite_devis_jours']!.text) ?? 30).round(),
        'unite_tissu': _unite,
        'couleur': _couleur,
      };
      // Le modèle de facture est enregistré par une mise à jour (colonne ajoutée ensuite).
      if (widget.atelier != null) data['modele_facture'] = _modeleFacture;
      data['devise'] ??= 'FCFA';

      final String id;
      if (widget.atelier == null) {
        id = await supa.rpc('creer_atelier', params: {'p': data}) as String;
      } else {
        id = widget.atelier!['id'] as String;
        await supa.from('ateliers').update(data).eq('id', id);
      }

      // L'atelier est enregistré : un échec du logo ne doit pas bloquer
      // (sinon un nouvel essai créerait un second atelier).
      if (_logo != null) {
        try {
          await _envoyerLogo(id);
        } catch (e) {
          if (mounted) {
            snack(context, 'Atelier enregistré, mais le logo n\'a pas pu être envoyé : ${messageErreur(e)}. '
                'Réessayez depuis Plus → Paramètres de l\'atelier.', erreur: true);
          }
        }
      }

      if (!mounted) return;
      if (widget.atelier != null) {
        final a = await supa.from('ateliers').select().eq('id', id).single();
        Session.instance.majAtelier(a);
        if (mounted) {
          snack(context, 'Atelier enregistré');
          Navigator.pop(context);
        }
      } else if (widget.onCree != null) {
        widget.onCree!(id);
      } else {
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _envoyerLogo(String id) async {
    final chemin = '$id/logo.$_logoExt';
    await supa.storage.from('logos').uploadBinary(
          chemin,
          _logo!,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/${_logoExt == 'jpg' ? 'jpeg' : _logoExt}',
          ),
        );
    final url = '${supa.storage.from('logos').getPublicUrl(chemin)}'
        '?v=${DateTime.now().millisecondsSinceEpoch}';
    await supa.from('ateliers').update({'logo_url': url}).eq('id', id);
  }

  Widget _champ(String cle, String label, {bool obligatoire = false, int lignes = 1, TextInputType? clavier, String? aide}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[cle],
        maxLines: lignes,
        keyboardType: clavier,
        decoration: InputDecoration(labelText: obligatoire ? '$label *' : label, helperText: aide),
        validator: obligatoire ? (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = widget.atelier?['logo_url'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.atelier == null ? 'Créer mon atelier' : 'Paramètres de l\'atelier'),
        actions: [
          if (widget.onAdministration != null)
            IconButton(
              tooltip: 'Administration de la plateforme',
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: widget.onAdministration,
            ),
          if (widget.premier)
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: () => supa.auth.signOut(),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.premier)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Bienvenue ! Renseignez votre atelier : ces informations apparaîtront '
                  'sur vos devis et factures. Vous pourrez les modifier plus tard.'),
            ),
          Center(
            child: InkWell(
              onTap: _choisirLogo,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _logo != null
                    ? Image.memory(_logo!, fit: BoxFit.contain)
                    : (logoUrl != null
                        ? Image.network(logoUrl, fit: BoxFit.contain)
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_photo_alternate, size: 36),
                            Text('Logo'),
                          ])),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Identité', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _champ('nom', 'Nom de l\'atelier', obligatoire: true),
          _champ('slogan', 'Slogan'),
          _champ('telephone', 'Téléphone', clavier: TextInputType.phone),
          _champ('email', 'E-mail', clavier: TextInputType.emailAddress),
          _champ('adresse', 'Adresse'),
          Row(children: [
            Expanded(child: _champ('ville', 'Ville')),
            const SizedBox(width: 12),
            Expanded(child: _champ('pays', 'Pays')),
          ]),
          _champ('identifiant_fiscal', 'Identifiant fiscal (NIF / IFU / NCC)'),
          _champ('registre_commerce', 'Registre du commerce (RCCM)'),
          const SizedBox(height: 8),
          Text('Couleur des documents', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final hex in couleursAtelier)
              InkWell(
                onTap: () => setState(() => _couleur = hex),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: couleurDepuisHex(hex),
                  child: _couleur == hex ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Réglages de calcul', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _champ('devise', 'Devise', obligatoire: true, aide: 'FCFA, EUR, GNF…')),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'yd', label: Text('Yards')),
                    ButtonSegment(value: 'm', label: Text('Mètres')),
                  ],
                  selected: {_unite},
                  onSelectionChanged: (s) => setState(() => _unite = s.first),
                ),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: ChampNombre(
                controller: _c['largeur_tissu_cm']!,
                label: 'Largeur tissu',
                suffixe: 'cm',
                obligatoire: true,
                aide: 'Largeur la plus courante',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: ChampNombre(controller: _c['taux_tva']!, label: 'TVA', suffixe: '%')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ChampNombre(controller: _c['acompte_pct']!, label: 'Acompte demandé', suffixe: '%')),
            const SizedBox(width: 12),
            Expanded(
              child: ChampNombre(
                  controller: _c['validite_devis_jours']!, label: 'Validité des devis', suffixe: 'jours'),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Factures', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (widget.atelier != null) ...[
            DropdownButtonFormField<String>(
              initialValue: _modeleFacture,
              decoration: const InputDecoration(labelText: 'Modèle de facture par défaut'),
              items: [
                for (final e in modelesFacture.entries)
                  DropdownMenuItem(value: e.key, child: Text('${e.value.$1} - ${e.value.$2}')),
              ],
              onChanged: (v) => setState(() => _modeleFacture = v ?? 'classique'),
            ),
            const SizedBox(height: 12),
          ],
          _champ('conditions_facture', 'Conditions (bas de facture)', lignes: 3),
          _champ('pied_facture', 'Pied de page', lignes: 2),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _occupe ? null : _enregistrer,
            icon: _occupe
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(widget.atelier == null ? 'Créer l\'atelier' : 'Enregistrer'),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
