/// Paramètres de connexion Supabase, lus depuis config.json au lancement :
/// flutter run --dart-define-from-file=config.json
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clé publique du projet (sb_publishable_…). Jamais la clé secrète.
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Adresse publique de l'application web (ex. https://mon-site.netlify.app/app/).
  /// Sert de retour au lien « mot de passe oublié » envoyé depuis le téléphone.
  static const siteUrl = String.fromEnvironment('SITE_URL');

  static bool get estConfigure => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
