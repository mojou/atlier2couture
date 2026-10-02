// Point de réception des notifications SasPay (webhooks).
//
// La signature (HMAC-SHA256 de « timestamp.corps ») est vérifiée, puis les
// paiements en attente des 7 derniers jours sont revérifiés directement
// auprès de SasPay : le contenu de la notification n'est jamais cru tel quel.
//
// À déployer SANS vérification JWT (SasPay n'envoie pas de jeton Supabase).
// Secrets requis : SASPAY_SECRET_KEY, SASPAY_WEBHOOK_SECRET
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const API = "https://api.saspay.me/api/v1";
const TOLERANCE_SECONDES = 300;

async function hmacHex(secret: string, message: string): Promise<string> {
  const cle = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", cle, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Comparaison en temps constant. */
function egal(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

type Paiement = { id: string; session_id: string | null; statut: string };

async function verifier(serveur: SupabaseClient, cle: string, p: Paiement): Promise<void> {
  if (!p.session_id) return;
  const reponse = await fetch(`${API}/checkout-sessions/${p.session_id}/status/`, {
    headers: { Authorization: `Bearer ${cle}` },
  });
  if (!reponse.ok) return;
  const contenu = await reponse.json().catch(() => ({}));
  const s = contenu?.data ?? contenu;
  const statut = String(s?.status ?? "").toUpperCase();
  const transaction = String(s?.transaction_status ?? "").toUpperCase();
  if (statut === "PAID" || transaction === "SUCCESS") {
    await serveur.rpc("appliquer_paiement_abonnement", { p: p.id, ref: s?.transaction_reference ?? null });
  } else if (["FAILED", "CANCELLED", "CANCELED", "EXPIRED"].includes(statut)) {
    const final = statut === "FAILED" ? "echoue" : "annule";
    await serveur.from("abonnement_paiements").update({ statut: final }).eq("id", p.id).eq("statut", "en_attente");
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Méthode non autorisée", { status: 405 });

  const secret = Deno.env.get("SASPAY_WEBHOOK_SECRET");
  const cle = Deno.env.get("SASPAY_SECRET_KEY");
  if (!secret || !cle) return new Response("Non configuré", { status: 500 });

  const corps = await req.text();
  const horodatage = req.headers.get("X-Webhook-Timestamp") ?? "";
  const signature = (req.headers.get("X-Webhook-Signature") ?? "").toLowerCase();
  const age = Math.abs(Date.now() / 1000 - Number(horodatage));
  if (!horodatage || !Number.isFinite(age) || age > TOLERANCE_SECONDES) {
    return new Response("Horodatage invalide", { status: 401 });
  }
  if (!egal(await hmacHex(secret, `${horodatage}.${corps}`), signature)) {
    return new Response("Signature invalide", { status: 401 });
  }

  const evenement = req.headers.get("X-Webhook-Event") ?? "";
  if (!evenement.startsWith("transaction.")) return new Response("ok");

  try {
    const serveur = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: enAttente } = await serveur
      .from("abonnement_paiements")
      .select("id, session_id, statut")
      .eq("statut", "en_attente")
      .gte("created_at", new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString())
      .limit(100);
    for (const p of enAttente ?? []) await verifier(serveur, cle, p);
    return new Response("ok");
  } catch (e) {
    // 500 : SasPay renverra la notification plus tard.
    return new Response(e instanceof Error ? e.message : String(e), { status: 500 });
  }
});
