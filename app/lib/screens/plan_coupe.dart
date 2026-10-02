import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calcul/calcul.dart';
import '../core/format.dart';

const _couleurs = [
  Color(0xFFFFE082), Color(0xFF81D4FA), Color(0xFFC5E1A5), Color(0xFFF8BBD0),
  Color(0xFFB39DDB), Color(0xFFFFCC80), Color(0xFF80CBC4), Color(0xFF9FA8DA),
];

/// Dessin du tissu déplié avec la position de chaque pièce et des repères
/// tous les yards (ou mètres).
class PlanCoupe extends StatelessWidget {
  const PlanCoupe({super.key, required this.resultat, required this.unite});

  final ResultatPlacement resultat;
  final String unite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final largeur = math.min(c.maxWidth, 520.0);
      final hauteur = resultat.longueurCoupe * largeur / resultat.largeurTissu;
      return Center(
        child: SizedBox(
          width: largeur,
          height: hauteur,
          child: CustomPaint(
            painter: _PlanPainter(resultat, unite, Theme.of(context).colorScheme.outline),
          ),
        ),
      );
    });
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.r, this.unite, this.contour);

  final ResultatPlacement r;
  final String unite;
  final Color contour;

  @override
  void paint(Canvas canvas, Size size) {
    final e = size.width / r.largeurTissu;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF1EDE4));

    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF424242);
    for (var i = 0; i < r.placements.length; i++) {
      final p = r.placements[i];
      final rect = Rect.fromLTWH(p.x * e, p.y * e, p.largeur * e, p.hauteur * e);
      canvas.drawRect(rect, Paint()..color = _couleurs[i % _couleurs.length]);
      canvas.drawRect(rect, trait);
      final tp = TextPainter(
        text: TextSpan(
          text: '${p.libelle}\n${nombre(p.largeur)} × ${nombre(p.hauteur)}',
          style: const TextStyle(fontSize: 9, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, rect.width - 4));
      if (tp.height <= rect.height - 2 && rect.width > 16) tp.paint(canvas, rect.topLeft + const Offset(2, 2));
    }

    // Repères d'unité (1 yd, 2 yd…) sur le côté gauche.
    final pas = unite == 'yd' ? cmParYard : 100.0;
    final repere = Paint()
      ..color = Colors.red.withAlpha(150)
      ..strokeWidth = 1;
    for (var n = 1; n * pas < r.longueurCoupe; n++) {
      final y = n * pas * e;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), repere);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '$n $unite',
          style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width - 2, y - tp.height - 1));
    }
    canvas.drawRect(Offset.zero & size, Paint()
      ..style = PaintingStyle.stroke
      ..color = contour
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant _PlanPainter old) => old.r != r || old.unite != unite;
}
