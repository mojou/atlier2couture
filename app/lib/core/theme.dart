import 'package:flutter/material.dart';

const couleurParDefaut = Color(0xFF7B2D8E);

const couleursAtelier = <String>[
  '#7B2D8E', '#1E5AA8', '#0F7B6C', '#B5462E', '#C28A00', '#2F3A4A', '#C2185B', '#5D4037',
];

Color couleurDepuisHex(String? hex, [Color defaut = couleurParDefaut]) {
  if (hex == null) return defaut;
  final h = hex.replaceAll('#', '').trim();
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? defaut : Color(v);
}

ThemeData construireTheme(Color graine) {
  final schema = ColorScheme.fromSeed(seedColor: graine);
  return ThemeData(
    useMaterial3: true,
    colorScheme: schema,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}
