-- =====================================================================
-- Formules d'abonnement : Gratuit, Standard (5 000 / mois), Premium (10 000 / mois)
--
-- - Plus de période d'essai : tout nouvel atelier est actif en formule Gratuite.
-- - Les limites de chaque formule sont appliquées par la base (triggers).
-- - Les paiements passent par SasPay via les Edge Functions (clé secrète
--   côté serveur) ; seule la fonction serveur peut valider un paiement.
-- =====================================================================

alter table public.ateliers
  add column if not exists formule text not null default 'gratuit'
  check (formule in ('gratuit', 'standard', 'premium'));
alter table public.ateliers add column if not exists formule_fin timestamptz;

-- Plus d'essai : les nouveaux ateliers sont actifs, les essais en cours aussi.
alter table public.ateliers alter column statut set default 'actif';
update public.ateliers set statut = 'actif' where statut in ('essai', 'en_attente');

-- Formule réellement en vigueur (une formule payante expirée redevient Gratuite).
create or replace function public.formule_effective(a uuid) returns text
language sql stable security definer set search_path = public as $$
  select case when t.formule <> 'gratuit' and t.formule_fin > now() then t.formule else 'gratuit' end
    from public.ateliers t where t.id = a;
$$;

-- Statut, formule et échéances ne se modifient que par l'administrateur
-- ou par le serveur (paiement validé) — jamais par l'atelier lui-même.
create or replace function public.tg_ateliers_statut() returns trigger
language plpgsql as $$
begin
  if (new.statut is distinct from old.statut
      or new.motif_statut is distinct from old.motif_statut
      or new.statut_change_le is distinct from old.statut_change_le
      or new.essai_fin is distinct from old.essai_fin
      or new.formule is distinct from old.formule
      or new.formule_fin is distinct from old.formule_fin)
     and auth.uid() is not null
     and not public.est_super_admin() then
    raise exception 'Seul l''administrateur de la plateforme peut modifier le statut ou la formule d''un atelier';
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Limites des formules
--   Gratuit  : 1 utilisateur, 30 clients, 15 commandes / mois, pas de stock
--   Standard : 3 utilisateurs, le reste illimité
--   Premium  : illimité, plusieurs ateliers
-- Les messages commencent par LIMITE_FORMULE: pour que l'application
-- propose de changer de formule.
-- ---------------------------------------------------------------------
create or replace function public.tg_limite_clients() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.formule_effective(new.atelier_id) = 'gratuit'
     and (select count(*) from public.clients where atelier_id = new.atelier_id) >= 30 then
    raise exception 'LIMITE_FORMULE: La formule Gratuite est limitée à 30 clients. Passez à la formule Standard pour en ajouter davantage.';
  end if;
  return new;
end $$;

create or replace function public.tg_limite_commandes() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.formule_effective(new.atelier_id) = 'gratuit'
     and (select count(*) from public.commandes
           where atelier_id = new.atelier_id
             and created_at >= date_trunc('month', now())) >= 15 then
    raise exception 'LIMITE_FORMULE: La formule Gratuite est limitée à 15 commandes par mois. Passez à la formule Standard pour continuer ce mois-ci.';
  end if;
  return new;
end $$;

create or replace function public.tg_limite_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.formule_effective(new.atelier_id) = 'gratuit' then
    raise exception 'LIMITE_FORMULE: La gestion du stock est disponible à partir de la formule Standard.';
  end if;
  return new;
end $$;

create or replace function public.tg_limite_membres() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  f   text := public.formule_effective(new.atelier_id);
  nb  int;
begin
  select count(*) into nb from public.membres where atelier_id = new.atelier_id;
  if f = 'gratuit' and nb >= 1 then
    raise exception 'LIMITE_FORMULE: La formule Gratuite est limitée à 1 utilisateur. Passez à la formule Standard (3 utilisateurs) ou Premium (illimité).';
  elsif f = 'standard' and nb >= 3 then
    raise exception 'LIMITE_FORMULE: La formule Standard est limitée à 3 utilisateurs. Passez à la formule Premium pour une équipe illimitée.';
  end if;
  return new;
end $$;

drop trigger if exists clients_limite on public.clients;
create trigger clients_limite before insert on public.clients
  for each row execute function public.tg_limite_clients();
drop trigger if exists commandes_limite on public.commandes;
create trigger commandes_limite before insert on public.commandes
  for each row execute function public.tg_limite_commandes();
drop trigger if exists stock_articles_limite on public.stock_articles;
create trigger stock_articles_limite before insert on public.stock_articles
  for each row execute function public.tg_limite_stock();
drop trigger if exists membres_limite on public.membres;
create trigger membres_limite before insert on public.membres
  for each row execute function public.tg_limite_membres();

-- Création d'atelier : un seul atelier par propriétaire, sauf en Premium.
-- Les ateliers supplémentaires d'un compte Premium partagent sa formule.
create or replace function public.creer_atelier(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u      uuid := auth.uid();
  nouvel uuid;
  f      text := 'gratuit';
  fin    timestamptz;
begin
  if u is null then
    raise exception 'Non authentifié';
  end if;
  if coalesce(trim(p->>'nom'), '') = '' then
    raise exception 'Le nom de l''atelier est obligatoire';
  end if;

  if exists (select 1 from public.membres where user_id = u and role = 'proprietaire')
     and not public.est_super_admin() then
    select t.formule, t.formule_fin into f, fin
      from public.membres m join public.ateliers t on t.id = m.atelier_id
     where m.user_id = u and m.role = 'proprietaire'
       and t.formule = 'premium' and t.formule_fin > now()
     order by t.formule_fin desc
     limit 1;
    if f is null then
      raise exception 'LIMITE_FORMULE: Gérer plusieurs ateliers est réservé à la formule Premium.';
    end if;
  end if;

  insert into public.ateliers (nom, slogan, telephone, email, adresse, ville, pays,
                               identifiant_fiscal, registre_commerce, devise, unite_tissu,
                               largeur_tissu_cm, taux_tva, acompte_pct, validite_devis_jours,
                               conditions_facture, pied_facture, couleur, formule, formule_fin)
  values (trim(p->>'nom'), p->>'slogan', p->>'telephone', p->>'email', p->>'adresse',
          p->>'ville', p->>'pays', p->>'identifiant_fiscal', p->>'registre_commerce',
          coalesce(nullif(p->>'devise', ''), 'FCFA'),
          coalesce(nullif(p->>'unite_tissu', ''), 'yd'),
          coalesce((p->>'largeur_tissu_cm')::numeric, 150),
          coalesce((p->>'taux_tva')::numeric, 0),
          coalesce((p->>'acompte_pct')::numeric, 50),
          coalesce((p->>'validite_devis_jours')::int, 30),
          p->>'conditions_facture', p->>'pied_facture',
          coalesce(nullif(p->>'couleur', ''), '#7B2D8E'),
          coalesce(f, 'gratuit'), fin)
  returning id into nouvel;

  insert into public.membres (atelier_id, user_id, role, nom)
  select nouvel, u, 'proprietaire', coalesce(raw_user_meta_data->>'nom', email)
    from auth.users where id = u;

  return nouvel;
end $$;

-- ---------------------------------------------------------------------
-- Paiements d'abonnement (SasPay)
-- ---------------------------------------------------------------------
create table if not exists public.abonnement_paiements (
  id              uuid primary key default gen_random_uuid(),
  atelier_id      uuid not null references public.ateliers(id) on delete cascade,
  formule         text not null check (formule in ('standard', 'premium')),
  mois            int  not null check (mois between 1 and 12),
  montant         numeric not null check (montant > 0),
  devise          text not null,
  pays            text,
  statut          text not null default 'en_attente'
                  check (statut in ('en_attente', 'paye', 'echoue', 'annule')),
  session_id      text,
  checkout_url    text,
  transaction_ref text,
  cree_par        uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  paye_le         timestamptz
);
create index if not exists abonnement_paiements_idx
  on public.abonnement_paiements(atelier_id, created_at desc);
create index if not exists abonnement_paiements_attente_idx
  on public.abonnement_paiements(statut, created_at) where statut = 'en_attente';

alter table public.abonnement_paiements enable row level security;
drop policy if exists abonnement_paiements_lecture on public.abonnement_paiements;
create policy abonnement_paiements_lecture on public.abonnement_paiements for select to authenticated
  using (public.est_gestionnaire_atelier(atelier_id) or public.est_super_admin());
-- Aucune écriture directe : seules les Edge Functions (clé serveur) créent et valident.

-- Applique un paiement confirmé par SasPay (appelée uniquement par le serveur).
-- Même formule encore en cours : prolongation ; sinon la nouvelle formule démarre maintenant.
create or replace function public.appliquer_paiement_abonnement(p uuid, ref text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  r     public.abonnement_paiements%rowtype;
  debut timestamptz;
begin
  select * into r from public.abonnement_paiements where id = p for update;
  if not found then
    raise exception 'Paiement introuvable';
  end if;
  if r.statut = 'paye' then
    return;
  end if;
  select case when t.formule = r.formule and t.formule_fin > now() then t.formule_fin else now() end
    into debut from public.ateliers t where t.id = r.atelier_id;
  update public.ateliers
     set formule = r.formule, formule_fin = debut + make_interval(months => r.mois)
   where id = r.atelier_id;
  update public.abonnement_paiements
     set statut = 'paye', paye_le = now(), transaction_ref = coalesce(ref, transaction_ref)
   where id = p;
end $$;

revoke execute on function public.appliquer_paiement_abonnement(uuid, text) from public, anon, authenticated;
grant execute on function public.appliquer_paiement_abonnement(uuid, text) to service_role;

-- ---------------------------------------------------------------------
-- Administration
-- ---------------------------------------------------------------------
-- Offrir ou modifier une formule à la main (mois = 0 : retour en Gratuit).
create or replace function public.admin_definir_formule(a uuid, f text, mois int default 1)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if f not in ('gratuit', 'standard', 'premium') or mois < 0 or mois > 36 then
    raise exception 'Formule ou durée invalide';
  end if;
  update public.ateliers
     set formule = f,
         formule_fin = case when f = 'gratuit' then null
                            when formule = f and formule_fin > now() then formule_fin + make_interval(months => mois)
                            else now() + make_interval(months => mois) end
   where id = a;
  if not found then
    raise exception 'Atelier introuvable';
  end if;
end $$;

drop function if exists public.admin_liste_ateliers();
create function public.admin_liste_ateliers()
returns table (
  id uuid, nom text, statut text, motif_statut text, statut_change_le timestamptz,
  essai_fin timestamptz, formule text, formule_fin timestamptz, created_at timestamptz,
  telephone text, ville text, pays text, logo_url text,
  proprietaire_nom text, proprietaire_email text,
  nb_membres bigint, nb_clients bigint, nb_commandes bigint, derniere_activite timestamptz
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.admin_verifier();
  return query
  select a.id, a.nom, a.statut, a.motif_statut, a.statut_change_le, a.essai_fin,
         public.formule_effective(a.id), a.formule_fin, a.created_at,
         a.telephone, a.ville, a.pays, a.logo_url,
         p.nom, u.email::text,
         (select count(*) from public.membres m where m.atelier_id = a.id),
         (select count(*) from public.clients c where c.atelier_id = a.id),
         (select count(*) from public.commandes c where c.atelier_id = a.id),
         greatest(a.created_at,
                  (select max(c.updated_at) from public.commandes c where c.atelier_id = a.id),
                  (select max(d.created_at) from public.documents d where d.atelier_id = a.id))
    from public.ateliers a
    left join lateral (
      select m.user_id, m.nom from public.membres m
       where m.atelier_id = a.id and m.role = 'proprietaire'
       order by m.created_at limit 1
    ) p on true
    left join auth.users u on u.id = p.user_id
   order by a.created_at desc;
end $$;

create or replace function public.admin_statistiques() returns json
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public.admin_verifier();
  return json_build_object(
    'ateliers',          (select count(*) from public.ateliers),
    'actifs',            (select count(*) from public.ateliers where statut = 'actif'),
    'suspendus',         (select count(*) from public.ateliers where statut = 'suspendu'),
    'gratuits',          (select count(*) from public.ateliers a where public.formule_effective(a.id) = 'gratuit'),
    'standard',          (select count(*) from public.ateliers a where public.formule_effective(a.id) = 'standard'),
    'premium',           (select count(*) from public.ateliers a where public.formule_effective(a.id) = 'premium'),
    'revenus_mois',      (select coalesce(sum(montant), 0) from public.abonnement_paiements
                           where statut = 'paye' and paye_le >= date_trunc('month', now())),
    'revenus_total',     (select coalesce(sum(montant), 0) from public.abonnement_paiements where statut = 'paye'),
    'utilisateurs',      (select count(*) from auth.users),
    'clients',           (select count(*) from public.clients),
    'commandes',         (select count(*) from public.commandes),
    'factures',          (select count(*) from public.documents where type = 'facture'),
    'ateliers_30j',      (select count(*) from public.ateliers where created_at > now() - interval '30 days'),
    'commandes_30j',     (select count(*) from public.commandes where created_at > now() - interval '30 days'),
    'connexions_7j',     (select count(*) from auth.users where last_sign_in_at > now() - interval '7 days')
  );
end $$;

revoke execute on function public.admin_liste_ateliers() from public, anon;
grant execute on function public.admin_liste_ateliers() to authenticated;
revoke execute on function public.admin_definir_formule(uuid, text, int) from public, anon;
grant execute on function public.admin_definir_formule(uuid, text, int) to authenticated;
