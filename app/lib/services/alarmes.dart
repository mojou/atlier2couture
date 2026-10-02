import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:alarm/alarm.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constantes.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/supa.dart';

/// Alarmes musicales des rendez-vous.
///
/// L'alarme est programmée sur le téléphone : elle sonne à l'heure choisie
/// (alarme_a) avec une musique prise dans le téléphone, ou un bip par défaut.
/// Les choix de musique sont propres à chaque téléphone (préférences locales).
class Alarmes {
  static bool get supporte => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _clePlanifiees = 'alarmes_planifiees';
  static const _cleDefaut = 'sonnerie_defaut';
  static const _idTest = 999999;
  static StreamSubscription<AlarmSettings>? _abonnement;

  static Future<void> init() async {
    if (!supporte) return;
    await Alarm.init();
    _abonnement ??= Alarm.ringStream.stream.listen(_quandSonne);
  }

  static Future<void> demanderPermissions() async {
    if (!supporte || !Platform.isAndroid) return;
    if (await Permission.notification.isDenied) await Permission.notification.request();
    if (await Permission.scheduleExactAlarm.isDenied) await Permission.scheduleExactAlarm.request();
  }

  /// Identifiant entier stable dérivé de l'identifiant du rendez-vous.
  static int idPour(String rdvId) {
    var h = 0x811c9dc5;
    for (final c in rdvId.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h == 0 || h == _idTest ? 1 : h;
  }

  // ---------------------------------------------------------------- musiques

  static Future<String?> sonnerieDefaut() async =>
      (await SharedPreferences.getInstance()).getString(_cleDefaut);

  static Future<void> definirSonnerieDefaut(String? chemin) async {
    final p = await SharedPreferences.getInstance();
    chemin == null ? await p.remove(_cleDefaut) : await p.setString(_cleDefaut, chemin);
  }

  static Future<String?> sonneriePour(String rdvId) async =>
      (await SharedPreferences.getInstance()).getString('sonnerie_$rdvId');

  static Future<void> definirSonneriePour(String rdvId, String? chemin) async {
    final p = await SharedPreferences.getInstance();
    chemin == null ? await p.remove('sonnerie_$rdvId') : await p.setString('sonnerie_$rdvId', chemin);
  }

  static String nomFichier(String? chemin) =>
      chemin == null ? 'Bip par défaut' : chemin.split(RegExp(r'[\\/]')).last;

  /// Choisit une musique dans le téléphone et la copie dans l'application
  /// (le fichier reste disponible même si l'original est déplacé).
  static Future<String?> choisirMusique() async {
    if (!supporte) return null;
    final r = await FilePicker.platform.pickFiles(type: FileType.audio);
    final f = r?.files.single;
    if (f == null || f.path == null) return null;
    final dossier = await _dossierSonneries();
    final dest = File('${dossier.path}/${f.name}');
    await File(f.path!).copy(dest.path);
    return dest.path;
  }

  static Future<Directory> _dossierSonneries() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/sonneries');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<String> _cheminBip() async {
    final f = File('${(await _dossierSonneries()).path}/bip_defaut.wav');
    if (!await f.exists()) await f.writeAsBytes(_bipWav());
    return f.path;
  }

  static Future<String> _cheminMusique(String? rdvId) async {
    final choix = (rdvId == null ? null : await sonneriePour(rdvId)) ?? await sonnerieDefaut();
    if (choix != null && await File(choix).exists()) return choix;
    return _cheminBip();
  }

  // ------------------------------------------------------------ programmation

  static Future<void> programmer({
    required String rdvId,
    required DateTime quand,
    required String titre,
    required String corps,
  }) async {
    if (!supporte) return;
    if (!quand.isAfter(DateTime.now())) {
      await annuler(rdvId);
      return;
    }
    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: idPour(rdvId),
        dateTime: quand,
        assetAudioPath: await _cheminMusique(rdvId),
        loopAudio: true,
        vibrate: true,
        volume: 0.9,
        fadeDuration: 3,
        notificationSettings: NotificationSettings(title: titre, body: corps, stopButton: 'Arrêter'),
      ),
    );
    final p = await SharedPreferences.getInstance();
    final liste = p.getStringList(_clePlanifiees) ?? [];
    if (!liste.contains(rdvId)) await p.setStringList(_clePlanifiees, [...liste, rdvId]);
  }

  static Future<void> annuler(String rdvId) async {
    if (!supporte) return;
    await Alarm.stop(idPour(rdvId));
    final p = await SharedPreferences.getInstance();
    final liste = p.getStringList(_clePlanifiees) ?? [];
    await p.setStringList(_clePlanifiees, liste.where((e) => e != rdvId).toList());
  }

  /// Alarme de test dans 5 secondes avec la sonnerie par défaut.
  static Future<void> tester() async {
    if (!supporte) return;
    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: _idTest,
        dateTime: DateTime.now().add(const Duration(seconds: 5)),
        assetAudioPath: await _cheminMusique(null),
        loopAudio: true,
        vibrate: true,
        volume: 0.9,
        fadeDuration: 2,
        notificationSettings: const NotificationSettings(
            title: 'Test de sonnerie', body: 'Voici votre alarme de rendez-vous', stopButton: 'Arrêter'),
      ),
    );
  }

  static String titrePour(Map<String, dynamic> rdv) {
    final client = (rdv['clients'] as Map?)?['nom'] ?? 'Client';
    return 'RDV ${typesRdv[rdv['type']] ?? ''} - $client';
  }

  static String corpsPour(Map<String, dynamic> rdv) {
    final debut = lireDate(rdv['debut'])!;
    final note = (rdv['note'] as String?)?.trim();
    return 'Le ${dateHeure(debut)}${note == null || note.isEmpty ? '' : ' · $note'}';
  }

  /// Reprogramme sur ce téléphone les alarmes des rendez-vous à venir de
  /// l'atelier courant, et supprime celles qui n'ont plus lieu d'être.
  static Future<void> synchroniser() async {
    if (!supporte || !Session.instance.aAtelier) return;
    try {
      // Formule sans alarmes musicales : on retire celles déjà programmées.
      if (!Session.instance.offre.alarmes) {
        final p = await SharedPreferences.getInstance();
        for (final id in p.getStringList(_clePlanifiees) ?? const <String>[]) {
          await annuler(id);
        }
        return;
      }
      final maintenant = DateTime.now();
      final rows = await supa
          .from('rendez_vous')
          .select('id, type, debut, alarme_a, note, statut, clients(nom)')
          .eq('atelier_id', Session.instance.atelierId)
          .eq('statut', 'prevu')
          .gte('alarme_a', maintenant.toUtc().toIso8601String())
          .lte('alarme_a', maintenant.add(const Duration(days: 60)).toUtc().toIso8601String());
      final voulus = <String>{};
      for (final r in rows) {
        final id = r['id'] as String;
        voulus.add(id);
        await programmer(
          rdvId: id,
          quand: lireDate(r['alarme_a'])!,
          titre: titrePour(r),
          corps: corpsPour(r),
        );
      }
      final p = await SharedPreferences.getInstance();
      for (final id in p.getStringList(_clePlanifiees) ?? const <String>[]) {
        if (!voulus.contains(id)) await annuler(id);
      }
    } catch (e) {
      debugPrint('Synchronisation des alarmes impossible : $e');
    }
  }

  static void _quandSonne(AlarmSettings a) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.alarm, size: 40),
        title: Text(a.notificationSettings.title),
        content: Text(a.notificationSettings.body),
        actions: [
          FilledButton(
            onPressed: () {
              Alarm.stop(a.id);
              Navigator.pop(c);
            },
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
  }

  /// Bip d'alarme généré (WAV 16 bits mono), utilisé si aucune musique n'est choisie.
  static Uint8List _bipWav() {
    const frequence = 22050;
    const duree = 2.0;
    final n = (frequence * duree).toInt();
    final d = ByteData(44 + n * 2);
    void ecrire(int pos, String s) {
      for (var i = 0; i < s.length; i++) {
        d.setUint8(pos + i, s.codeUnitAt(i));
      }
    }

    ecrire(0, 'RIFF');
    d.setUint32(4, 36 + n * 2, Endian.little);
    ecrire(8, 'WAVE');
    ecrire(12, 'fmt ');
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 1, Endian.little);
    d.setUint32(24, frequence, Endian.little);
    d.setUint32(28, frequence * 2, Endian.little);
    d.setUint16(32, 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    ecrire(36, 'data');
    d.setUint32(40, n * 2, Endian.little);
    for (var i = 0; i < n; i++) {
      final t = i / frequence;
      final note = (t % 1.0) < 0.5 ? 880.0 : 1175.0;
      final v = (t % 0.5) < 0.25 ? math.sin(2 * math.pi * note * t) * 0.6 : 0.0;
      d.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
    }
    return d.buffer.asUint8List();
  }
}
