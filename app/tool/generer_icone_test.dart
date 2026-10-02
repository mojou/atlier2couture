// Génère le logo de l'application en PNG (icône, avant-plan adaptatif Android,
// image de partage pour les réseaux sociaux).
//
//   flutter test tool/generer_icone_test.dart
//   dart run flutter_launcher_icons
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _prune = Color(0xFF7B2D8E);
const _pruneFonce = Color(0xFF3C1247);
const _or = Color(0xFFE9B949);

/// Ciseaux ouverts dans un carré de côté [s], centrés en [centre].
void _ciseaux(Canvas c, Offset centre, double s) {
  final blanc = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.055
    ..strokeCap = StrokeCap.round;
  final lame = Paint()
    ..color = _or
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.085
    ..strokeCap = StrokeCap.round;

  Offset p(double x, double y) => centre + Offset((x - .5) * s, (y - .5) * s);

  final anneauG = p(.33, .73);
  final anneauD = p(.67, .73);
  final rayon = s * .12;
  // Lames : de chaque anneau vers la pointe opposée, croisées au pivot.
  c.drawLine(anneauG + Offset(rayon * .55, -rayon * .8), p(.70, .17), lame);
  c.drawLine(anneauD + Offset(-rayon * .55, -rayon * .8), p(.30, .17), lame);
  c.drawCircle(anneauG, rayon, blanc);
  c.drawCircle(anneauD, rayon, blanc);
  c.drawCircle(p(.5, .465), s * .035, Paint()..color = Colors.white);
}

Future<void> _ecrire(String chemin, int largeur, int hauteur, void Function(Canvas c, Size taille) dessin) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  dessin(canvas, Size(largeur.toDouble(), hauteur.toDouble()));
  final image = await rec.endRecording().toImage(largeur, hauteur);
  final octets = await image.toByteData(format: ui.ImageByteFormat.png);
  File(chemin)
    ..createSync(recursive: true)
    ..writeAsBytesSync(octets!.buffer.asUint8List());
}

void _fond(Canvas c, Rect r, {double arrondi = 0}) {
  final p = Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_prune, _pruneFonce],
    ).createShader(r);
  c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(arrondi)), p);
}

void main() {
  test('générer le logo', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      // Icône pleine (Android ancien, iOS, web) : fond dégradé + ciseaux.
      await _ecrire('assets/icone/icone.png', 1024, 1024, (c, t) {
        _fond(c, Offset.zero & t);
        _ciseaux(c, t.center(Offset.zero), t.width * .68);
      });
      // Avant-plan de l'icône adaptative Android : ciseaux seuls dans la zone sûre (≈ 60 %).
      await _ecrire('assets/icone/icone_avant.png', 1024, 1024, (c, t) {
        _ciseaux(c, t.center(Offset.zero), t.width * .52);
      });
      // Image de partage (WhatsApp, Facebook…) 1200 × 630.
      await _ecrire('../landing/partage.png', 1200, 630, (c, t) {
        _fond(c, Offset.zero & t);
        final motif = Paint()
          ..color = Colors.white.withAlpha(18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (var i = 0; i < 9; i++) {
          c.drawCircle(Offset(t.width * .78, t.height * .5), 60.0 + i * 46, motif);
        }
        final carre = Rect.fromCenter(center: Offset(t.width * .5, t.height * .5), width: 330, height: 330);
        c.drawShadow(Path()..addRRect(RRect.fromRectAndRadius(carre, const Radius.circular(70))), Colors.black, 18, false);
        _fond(c, carre, arrondi: 70);
        c.drawRRect(
          RRect.fromRectAndRadius(carre, const Radius.circular(70)),
          Paint()
            ..color = _or.withAlpha(120)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        _ciseaux(c, carre.center, 230);
        final fil = Paint()
          ..color = _or.withAlpha(160)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        final chemin = Path()..moveTo(0, t.height * .82);
        for (var x = 0.0; x <= t.width; x += 10) {
          chemin.lineTo(x, t.height * .82 + math.sin(x / 60) * 12);
        }
        c.drawPath(chemin, fil);
      });
    });
    expect(File('assets/icone/icone.png').existsSync(), isTrue);
  });
}
