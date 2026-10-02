// Vérifie auprès de SasPay les paiements en attente d'un atelier et active
// l'abonnement de ceux qui sont payés. Appelée par l'application au retour
// de la page de paiement (utilisateur connecté, gestionnaire de l'atelier).
//
// Secret requis : SASPAY_SECRET_KEY
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const API = "https://api.saspay.me/api/v1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (corps: unknown, status = 200) =>
  new Response(JSON.stringify(corps), { status, headers: { ...cors, "Content-Type": "application/json" } });

type Paiement = { id: string; session_id: string | null; statut: string };

/** Interroge SasPay pour une session et met à jour le paiement. Renvoie le statut final. */
async function verifier(serveur: SupabaseClient, cle: string, p: Paiement): Promise<string> {
  if (!p.session_id) return p.statut;
  const reponse = await fetch(`${API}/checkout-sessions/${p.session_id}/status/`, {
    headers: { Authorization: `Bearer ${cle}` },
  });
  if (!reponse.ok) return p.statut;
  const contenu = await reponse.json().catch(() => ({}));
  const s = contenu?.data ?? contenu;
  const statut = String(s?.status ?? "").toUpperCase();
  const transaction = String(s?.transaction_status ?? "").toUpperCase();

  if (statut === "PAID" || transaction === "SUCCESS") {
    const { error } = await serveur.rpc("appliquer_paiement_abonnement", {
      p: p.id,
      ref: s?.transaction_reference ?? null,
    });
    if (error) throw error;
    return "paye";
  }
  if (["FAILED", "CANCELLED", "CANCELED", "EXPIRED"].includes(statut) ||
      ["FAILED", "CANCELLED", "CANCELED"].includes(transaction)) {
    const final = statut === "EXPIRED" || statut.startsWith("CANCEL") ? "annule" : "echoue";
    await serveur.from("abonnement_paiements").update({ statut: final }).eq("id", p.id).eq("statut", "en_attente");
    return final;
  }
  return "en_attente";
}

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

    const { atelier_id } = await req.json();
    const { data: gestionnaire } = await utilisateur.rpc("est_gestionnaire_atelier", { a: atelier_id });
    const { data: superAdmin } = await utilisateur.rpc("est_super_admin");
    if (!gestionnaire && !superAdmin) return json({ erreur: "Accès refusé." }, 403);

    const serveur = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: enAttente, error } = await serveur
      .from("abonnement_paiements")
      .select("id, session_id, statut")
      .eq("atelier_id", atelier_id)
      .eq("statut", "en_attente")
      .gte("created_at", new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString());
    if (error) throw error;

    const resultats: Record<string, string> = {};
    for (const p of enAttente ?? []) {
      resultats[p.id] = await verifier(serveur, cle, p);
    }
    return json({ resultats, payes: Object.values(resultats).filter((s) => s === "paye").length });
  } catch (e) {
    return json({ erreur: e instanceof Error ? e.message : String(e) }, 500);
  }
});
