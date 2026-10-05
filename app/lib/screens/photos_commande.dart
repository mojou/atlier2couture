import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import 'abonnement_screen.dart';

/// Photos d'une commande (modèle souhaité, tissu déposé, essayage, vêtement fini),
/// stockées dans le bucket privé « photos » et affichées par liens temporaires.
class PhotosCommande extends StatefulWidget {
  const PhotosCommande({super.key, required this.commandeId, this.clientId});

  final String commandeId;
  final String? clientId;

  @override
  State<PhotosCommande> createState() => _PhotosCommandeState();
}

class _PhotosCommandeState extends State<PhotosCommande> {
  List<Map<String, dynamic>> _photos = [];
  Map<String, String> _liens = {};
  bool _chargement = true;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final rows = await supa.from('photos').select().eq('commande_id', widget.commandeId).order('created_at');
      final liens = <String, String>{};
      if (rows.isNotEmpty) {
        final signes = await supa.storage
            .from('photos')
            .createSignedUrlsResult([for (final p in rows) p['chemin'] as String], 3600);
        for (final s in signes) {
          if (s is SignedUrlSuccess) liens[s.path] = s.signedUrl;
        }
      }
      if (mounted) {
        setState(() {
          _photos = rows;
          _liens = liens;
          _chargement = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _ajouter() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            subtitle: const Text('Ex. : modèle reçu sur WhatsApp'),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    // Photo réduite et compressée : rapide à envoyer, même avec une connexion lente.
    final image = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
    if (image == null || !mounted) return;
    final categorie = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Cette photo montre…')),
          for (final e in categoriesPhoto.entries)
            ListTile(title: Text(e.value), onTap: () => Navigator.pop(c, e.key)),
        ]),
      ),
    );
    if (categorie == null || !mounted) return;

    setState(() => _envoi = true);
    try {
      final octets = await image.readAsBytes();
      final ext = image.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final chemin = '${Session.instance.atelierId}/${widget.commandeId}/'
          '${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supa.storage.from('photos').uploadBinary(
            chemin,
            octets,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
          );
      await supa.from('photos').insert({
        'atelier_id': Session.instance.atelierId,
        'commande_id': widget.commandeId,
        'client_id': widget.clientId,
        'categorie': categorie,
        'chemin': chemin,
      });
      await _charger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _supprimer(Map<String, dynamic> p) async {
    try {
      await supa.storage.from('photos').remove([p['chemin'] as String]);
      await supa.from('photos').delete().eq('id', p['id'] as String);
      await _charger();
    } catch (e) {
      if (mounted) snack(context, messageErreur(e), erreur: true);
    }
  }

  void _agrandir(Map<String, dynamic> p) {
    final lien = _liens[p['chemin']];
    if (lien == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (c) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${categoriesPhoto[p['categorie']] ?? ''} · ${dateCourte(lireDate(p['created_at']))}'),
          actions: [
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirmer(c, 'Supprimer la photo', 'Cette photo sera supprimée définitivement.', ok: 'Supprimer')) {
                  if (c.mounted) Navigator.pop(c);
                  await _supprimer(p);
                }
              },
            ),
          ],
        ),
        body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(lien))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (!Session.instance.offre.photos) {
      return Section(
        titre: 'Photos',
        action: TextButton.icon(
          onPressed: () => proposerFormule(context,
              'Les photos de commande (modèle, tissu, essayage, vêtement fini) sont incluses à partir de la formule Standard.'),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Débloquer'),
        ),
        children: const [Text('Gardez la photo du modèle souhaité et du tissu déposé avec la commande.')],
      );
    }
    return Section(
      titre: 'Photos (${_photos.length})',
      action: TextButton.icon(
        onPressed: _envoi ? null : _ajouter,
        icon: _envoi
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(_envoi ? 'Envoi…' : 'Ajouter'),
      ),
      children: [
        if (_chargement)
          const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else if (_photos.isEmpty)
          Text(kIsWeb
              ? 'Ajoutez le modèle souhaité, le tissu déposé ou le vêtement fini.'
              : 'Photographiez le modèle souhaité, le tissu déposé ou le vêtement fini.')
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final p = _photos[i];
                final lien = _liens[p['chemin']];
                return InkWell(
                  onTap: () => _agrandir(p),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 96,
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: lien == null
                            ? Container(width: 96, height: 88, color: t.colorScheme.surfaceContainerHighest)
                            : Image.network(lien, width: 96, height: 88, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    width: 96, height: 88, color: t.colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image_outlined))),
                      ),
                      const SizedBox(height: 4),
                      Text(categoriesPhoto[p['categorie']] ?? '',
                          style: t.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
