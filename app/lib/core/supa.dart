import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supa => Supabase.instance.client;

String? get utilisateurId => supa.auth.currentUser?.id;

/// Clé du navigateur racine (utilisée par les alarmes pour afficher un dialogue).
final navigatorKey = GlobalKey<NavigatorState>();
