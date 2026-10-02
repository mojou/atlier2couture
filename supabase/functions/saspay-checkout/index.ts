// Crée une session de paiement SasPay pour un abonnement d'atelier.
// Appelée par l'application (utilisateur connecté, propriétaire ou gérant).
//
// Secrets requis (Supabase → Edge Functions → Secrets) :
//   SASPAY_SECRET_KEY   clé secrète SasPay (sk_live_… ou sk_test_…)
//   SASPAY_RETURN_URL   (facultatif) page affichée après le paiement
import { createClient } from "npm:@supabase/supabase-js@2";

const API = "https://api.saspay.me/api/v1";

/** Prix mensuels en francs CFA. */
const PRIX: Record<string, number> = { standard: 5000, premium: 10000 };
const DUREES = [1, 3, 6, 12];

/** Pays SasPay payés en franc CFA → devise. */
const DEVISES: Record<string, string> = {
  BJ: "XOF", BF: "XOF", CI: "XOF", ML: "XOF", NE: "XOF", SN: "XOF", TG: "XOF",
  CM: "XAF",
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const cle = Deno.env.get("SASPAY_SECRET_KEY");
    if (!cle) return json({ erreur: "Paiement non configuré (clé SasPay absente)." }, 500);

    const url = Deno.env.get("SUPABASE_URL")!;
    const utilisateur = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await utilisateur.auth.getUser();
    if (!user) return json({ erreur: "Vous devez être connecté." }, 401);

    const { atelier_id, formule, mois, pays } = await req.json();
    if (!PRIX[formule]) return json({ erreur: "Formule invalide." }, 400);
    const duree = Number(mois);
    if (!DUREES.includes(duree)) return json({ erreur: "Durée invalide." }, 400);
    const devise = DEVISES[pays];
    if (!devise) return json({ erreur: "Pays non pris en charge pour le paiement." }, 400);

    const { data: autorise } = await utilisateur.rpc("est_gestionnaire_atelier", { a: atelier_id });
    if (!autorise) return json({ erreur: "Réservé au propriétaire ou au gérant de l'atelier." }, 403);

    const serveur = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: atelier } = await serveur.from("ateliers").select("nom").eq("id", atelier_id).single();
    const montant = PRIX[formule] * duree;

    const { data: paiement, error } = await serveur
      .from("abonnement_paiements")
      .insert({ atelier_id, formule, mois: duree, montant, devise, pays, cree_par: user.id })
      .select()
      .single();
    if (error) throw error;

    const corps: Record<string, unknown> = {
      amount: montant.toFixed(2),
      currency: devise,
      country: pays,
      customer_email: user.email,
      customer_name: atelier?.nom ?? user.email,
      description: `Atelier Couture - formule ${formule} - ${duree} mois`,
      metadata: { paiement_id: paiement.id, atelier_id },
    };
    const retour = Deno.env.get("SASPAY_RETURN_URL");
    if (retour) corps.return_url = retour;

    const reponse = await fetch(`${API}/checkout-sessions/`, {
      method: "POST",
      headers: { Authorization: `Bearer ${cle}`, "Content-Type": "application/json" },
      body: JSON.stringify(corps),
    });
    const contenu = await reponse.json().catch(() => ({}));
    const session = contenu?.data ?? contenu;
    if (!reponse.ok || !session?.checkout_url) {
      await serveur.from("abonnement_paiements").update({ statut: "echoue" }).eq("id", paiement.id);
      return json({ erreur: contenu?.error?.message ?? "SasPay a refusé la demande de paiement." }, 502);
    }

    await serveur
      .from("abonnement_paiements")
      .update({ session_id: session.id, checkout_url: session.checkout_url })
      .eq("id", paiement.id);

    return json({ paiement_id: paiement.id, checkout_url: session.checkout_url });
  } catch (e) {
    return json({ erreur: e instanceof Error ? e.message : String(e) }, 500);
  }
});
