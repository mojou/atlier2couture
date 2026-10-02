-- =====================================================================
-- Espace super administrateur de la plateforme
--
-- - Chaque atelier a un statut : en_attente, actif, suspendu.
--   Les ateliers existants restent actifs ; les nouveaux attendent
--   l'activation par un super administrateur.
-- - Un atelier non actif n'a plus accès à ses données (bloqué par la base).
-- - Les super administrateurs gèrent les ateliers et les comptes via des
--   fonctions dédiées (admin_*), refusées à tout autre utilisateur.
--
-- Ce script inclut aussi la colonne modele_facture (sans effet si déjà ajoutée).
-- =====================================================================

alter table public.ateliers
  add column if not exists modele_facture text not null default 'classique'
  check (modele_facture in ('classique', 'moderne', 'elegant', 'minimal', 'ticket'));

-- Les ateliers existants reçoivent « actif », les suivants « en_attente ».
alter table public.ateliers
  add column if not exists statut text not null default 'actif'
  check (statut in ('en_attente', 'actif', 'suspendu'));
alter table public.ateliers alter column statut set default 'en_attente';
alter table public.ateliers add column if not exists motif_statut text;
alter table public.ateliers add column if not exists statut_change_le timestamptz;

-- ---------------------------------------------------------------------
-- Super administrateurs
-- ---------------------------------------------------------------------
create table if not exists public.super_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.super_admins enable row level security;   -- aucun accès direct

create or replace function public.est_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.super_admins where user_id = auth.uid());
$$;

-- ---------------------------------------------------------------------
-- Appartenance à un atelier
--   est_membre_atelier / est_gestionnaire_atelier : quel que soit le statut
--     (lire son atelier, voir qu'il est en attente, régler logo et infos)
--   est_membre / est_gestionnaire : atelier ACTIF uniquement
--     (toutes les données métier : clients, commandes, factures…)
-- ---------------------------------------------------------------------
create or replace function public.est_membre_atelier(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membres where atelier_id = a and user_id = auth.uid());
$$;

create or replace function public.est_gestionnaire_atelier(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres
    where atelier_id = a and user_id = auth.uid() and role in ('proprietaire', 'gerant')
  );
$$;

create or replace function public.est_membre(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres m join public.ateliers t on t.id = m.atelier_id
    where m.atelier_id = a and m.user_id = auth.uid() and t.statut = 'actif'
  );
$$;

create or replace function public.est_gestionnaire(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres m join public.ateliers t on t.id = m.atelier_id
    where m.atelier_id = a and m.user_id = auth.uid()
      and m.role in ('proprietaire', 'gerant') and t.statut = 'actif'
  );
$$;

drop policy if exists ateliers_lecture on public.ateliers;
drop policy if exists ateliers_modif on public.ateliers;
create policy ateliers_lecture on public.ateliers for select to authenticated
  using (public.est_membre_atelier(id));
create policy ateliers_modif on public.ateliers for update to authenticated
  using (public.est_gestionnaire_atelier(id)) with check (public.est_gestionnaire_atelier(id));

drop policy if exists membres_lecture on public.membres;
drop policy if exists membres_modif on public.membres;
drop policy if exists membres_suppression on public.membres;
create policy membres_lecture on public.membres for select to authenticated
  using (public.est_membre_atelier(atelier_id));
create policy membres_modif on public.membres for update to authenticated
  using (public.est_gestionnaire_atelier(atelier_id) and role <> 'proprietaire')
  with check (public.est_gestionnaire_atelier(atelier_id) and role <> 'proprietaire');
create policy membres_suppression on public.membres for delete to authenticated
  using (public.est_gestionnaire_atelier(atelier_id) and role <> 'proprietaire');

drop policy if exists logos_ajout on storage.objects;
drop policy if exists logos_modif on storage.objects;
drop policy if exists logos_suppression on storage.objects;
create policy logos_ajout on storage.objects for insert to authenticated
  with check (bucket_id = 'logos'
              and public.est_gestionnaire_atelier(((storage.foldername(name))[1])::uuid));
create policy logos_modif on storage.objects for update to authenticated
  using (bucket_id = 'logos'
         and public.est_gestionnaire_atelier(((storage.foldername(name))[1])::uuid));
create policy logos_suppression on storage.objects for delete to authenticated
  using (bucket_id = 'logos'
         and (public.est_super_admin()
              or public.est_gestionnaire_atelier(((storage.foldername(name))[1])::uuid)));

-- Seul un super administrateur change le statut d'un atelier.
create or replace function public.tg_ateliers_statut() returns trigger
language plpgsql as $$
begin
  if (new.statut is distinct from old.statut
      or new.motif_statut is distinct from old.motif_statut
      or new.statut_change_le is distinct from old.statut_change_le)
     and auth.uid() is not null
     and not public.est_super_admin() then
    raise exception 'Seul l''administrateur de la plateforme peut changer le statut d''un atelier';
  end if;
  return new;
end $$;

drop trigger if exists ateliers_statut on public.ateliers;
create trigger ateliers_statut before update on public.ateliers
  for each row execute function public.tg_ateliers_statut();

-- ---------------------------------------------------------------------
-- Fonctions d'administration
-- ---------------------------------------------------------------------
create or replace function public.admin_verifier() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.est_super_admin() then
    raise exception 'Réservé à l''administrateur de la plateforme';
  end if;
end $$;

create or replace function public.admin_liste_ateliers()
returns table (
  id uuid, nom text, statut text, motif_statut text, statut_change_le timestamptz,
  created_at timestamptz, telephone text, ville text, pays text, logo_url text,
  proprietaire_nom text, proprietaire_email text,
  nb_membres bigint, nb_clients bigint, nb_commandes bigint, derniere_activite timestamptz
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.admin_verifier();
  return query
  select a.id, a.nom, a.statut, a.motif_statut, a.statut_change_le, a.created_at,
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
   order by (a.statut = 'en_attente') desc, a.created_at desc;
end $$;

create or replace function public.admin_changer_statut(a uuid, s text, motif text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if s not in ('en_attente', 'actif', 'suspendu') then
    raise exception 'Statut invalide';
  end if;
  update public.ateliers
     set statut = s, motif_statut = nullif(trim(motif), ''), statut_change_le = now()
   where id = a;
  if not found then
    raise exception 'Atelier introuvable';
  end if;
end $$;

-- Suppression complète d'un atelier et de toutes ses données (usage interne).
create or replace function public._supprimer_atelier(a uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.paiements where atelier_id = a;
  delete from public.documents where atelier_id = a;
  delete from public.stock_mouvements where atelier_id = a;
  delete from public.rendez_vous where atelier_id = a;
  delete from public.commande_historique where atelier_id = a;
  delete from public.commandes where atelier_id = a;
  delete from public.mesures where atelier_id = a;
  delete from public.clients where atelier_id = a;
  delete from public.modeles where atelier_id = a;
  delete from public.stock_articles where atelier_id = a;
  delete from public.compteurs where atelier_id = a;
  delete from public.membres where atelier_id = a;
  delete from public.ateliers where id = a;
end $$;

create or replace function public.admin_supprimer_atelier(a uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if not exists (select 1 from public.ateliers where id = a) then
    raise exception 'Atelier introuvable';
  end if;
  perform public._supprimer_atelier(a);
end $$;

create or replace function public.admin_liste_utilisateurs()
returns table (
  id uuid, email text, nom text, created_at timestamptz, derniere_connexion timestamptz,
  super_admin boolean, ateliers text
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.admin_verifier();
  return query
  select u.id, u.email::text, coalesce(u.raw_user_meta_data->>'nom', ''),
         u.created_at, u.last_sign_in_at,
         exists (select 1 from public.super_admins s where s.user_id = u.id),
         (select string_agg(t.nom || ' (' || m.role || ')', ', ' order by t.nom)
            from public.membres m join public.ateliers t on t.id = m.atelier_id
           where m.user_id = u.id)
    from auth.users u
   order by u.created_at desc;
end $$;

-- Supprime un compte. Avec avec_ateliers, supprime aussi les ateliers dont
-- il est le seul propriétaire (et toutes leurs données).
create or replace function public.admin_supprimer_utilisateur(u uuid, avec_ateliers boolean default false)
returns void
language plpgsql security definer set search_path = public, auth as $$
declare
  a uuid;
begin
  perform public.admin_verifier();
  if u = auth.uid() then
    raise exception 'Vous ne pouvez pas supprimer votre propre compte';
  end if;
  if exists (select 1 from public.super_admins where user_id = u) then
    raise exception 'Retirez d''abord ses droits de super administrateur';
  end if;
  if avec_ateliers then
    for a in
      select m.atelier_id from public.membres m
       where m.user_id = u and m.role = 'proprietaire'
         and not exists (select 1 from public.membres m2
                          where m2.atelier_id = m.atelier_id and m2.role = 'proprietaire'
                            and m2.user_id <> u)
    loop
      perform public._supprimer_atelier(a);
    end loop;
  end if;
  delete from auth.users where id = u;
  if not found then
    raise exception 'Compte introuvable';
  end if;
end $$;

create or replace function public.admin_definir_super_admin(u uuid, actif boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if actif then
    insert into public.super_admins (user_id) values (u) on conflict do nothing;
  else
    if u = auth.uid() then
      raise exception 'Vous ne pouvez pas retirer vos propres droits';
    end if;
    delete from public.super_admins where user_id = u;
  end if;
end $$;

create or replace function public.admin_statistiques() returns json
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public.admin_verifier();
  return json_build_object(
    'ateliers',          (select count(*) from public.ateliers),
    'actifs',            (select count(*) from public.ateliers where statut = 'actif'),
    'en_attente',        (select count(*) from public.ateliers where statut = 'en_attente'),
    'suspendus',         (select count(*) from public.ateliers where statut = 'suspendu'),
    'utilisateurs',      (select count(*) from auth.users),
    'clients',           (select count(*) from public.clients),
    'commandes',         (select count(*) from public.commandes),
    'factures',          (select count(*) from public.documents where type = 'facture'),
    'ateliers_30j',      (select count(*) from public.ateliers where created_at > now() - interval '30 days'),
    'commandes_30j',     (select count(*) from public.commandes where created_at > now() - interval '30 days'),
    'connexions_7j',     (select count(*) from auth.users where last_sign_in_at > now() - interval '7 days')
  );
end $$;

-- Droits d'exécution
revoke execute on function public._supprimer_atelier(uuid) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.admin_verifier()',
    'public.admin_liste_ateliers()',
    'public.admin_changer_statut(uuid, text, text)',
    'public.admin_supprimer_atelier(uuid)',
    'public.admin_liste_utilisateurs()',
    'public.admin_supprimer_utilisateur(uuid, boolean)',
    'public.admin_definir_super_admin(uuid, boolean)',
    'public.admin_statistiques()'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Premier super administrateur : REMPLACEZ l'e-mail si votre compte
-- utilise une autre adresse.
-- ---------------------------------------------------------------------
insert into public.super_admins (user_id)
select id from auth.users where lower(email) = lower('germbob96@gmail.com')
on conflict do nothing;
