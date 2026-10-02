-- =====================================================================
-- Période d'essai de 48 h
--
-- Un nouvel atelier est utilisable immédiatement (statut « essai »).
-- Si le super administrateur ne l'active pas avant essai_fin, l'accès
-- aux données est coupé automatiquement (contrôle fait à chaque requête,
-- sans tâche planifiée). L'administrateur peut activer, suspendre ou
-- prolonger l'essai.
-- =====================================================================

-- Seul un super administrateur modifie le statut ou la fin d'essai depuis
-- l'application. Sans utilisateur connecté (SQL Editor, clé serveur), la
-- modification est permise : c'est le propriétaire du projet qui agit.
create or replace function public.tg_ateliers_statut() returns trigger
language plpgsql as $$
begin
  if (new.statut is distinct from old.statut
      or new.motif_statut is distinct from old.motif_statut
      or new.statut_change_le is distinct from old.statut_change_le
      or new.essai_fin is distinct from old.essai_fin)
     and auth.uid() is not null
     and not public.est_super_admin() then
    raise exception 'Seul l''administrateur de la plateforme peut changer le statut d''un atelier';
  end if;
  return new;
end $$;

alter table public.ateliers drop constraint if exists ateliers_statut_check;
alter table public.ateliers add constraint ateliers_statut_check
  check (statut in ('essai', 'en_attente', 'actif', 'suspendu'));

alter table public.ateliers add column if not exists essai_fin timestamptz;
alter table public.ateliers alter column statut set default 'essai';
alter table public.ateliers alter column essai_fin set default now() + interval '48 hours';

-- Les ateliers en attente créés sous l'ancienne règle passent en essai,
-- 48 h à compter de leur création.
update public.ateliers
   set statut = 'essai', essai_fin = created_at + interval '48 hours'
 where statut = 'en_attente';

-- Accès aux données métier : atelier actif, ou en essai non expiré.
create or replace function public.est_membre(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres m join public.ateliers t on t.id = m.atelier_id
    where m.atelier_id = a and m.user_id = auth.uid()
      and (t.statut = 'actif' or (t.statut = 'essai' and t.essai_fin > now()))
  );
$$;

create or replace function public.est_gestionnaire(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres m join public.ateliers t on t.id = m.atelier_id
    where m.atelier_id = a and m.user_id = auth.uid()
      and m.role in ('proprietaire', 'gerant')
      and (t.statut = 'actif' or (t.statut = 'essai' and t.essai_fin > now()))
  );
$$;

-- ---------------------------------------------------------------------
-- Administration
-- ---------------------------------------------------------------------
create or replace function public.admin_changer_statut(a uuid, s text, motif text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if s not in ('essai', 'en_attente', 'actif', 'suspendu') then
    raise exception 'Statut invalide';
  end if;
  update public.ateliers
     set statut = s, motif_statut = nullif(trim(motif), ''), statut_change_le = now()
   where id = a;
  if not found then
    raise exception 'Atelier introuvable';
  end if;
end $$;

-- Remet l'atelier en essai pour « heures » heures à partir de maintenant
-- (ou de la fin d'essai actuelle si elle n'est pas encore passée).
create or replace function public.admin_prolonger_essai(a uuid, heures int default 48)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.admin_verifier();
  if heures <= 0 or heures > 24 * 365 then
    raise exception 'Durée invalide';
  end if;
  update public.ateliers
     set statut = 'essai',
         essai_fin = greatest(now(), coalesce(essai_fin, now())) + make_interval(hours => heures),
         motif_statut = null,
         statut_change_le = now()
   where id = a;
  if not found then
    raise exception 'Atelier introuvable';
  end if;
end $$;

-- Le type de retour change (ajout de essai_fin) : la fonction est recréée.
drop function if exists public.admin_liste_ateliers();
create function public.admin_liste_ateliers()
returns table (
  id uuid, nom text, statut text, motif_statut text, statut_change_le timestamptz,
  essai_fin timestamptz, created_at timestamptz, telephone text, ville text, pays text,
  logo_url text, proprietaire_nom text, proprietaire_email text,
  nb_membres bigint, nb_clients bigint, nb_commandes bigint, derniere_activite timestamptz
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.admin_verifier();
  return query
  select a.id, a.nom, a.statut, a.motif_statut, a.statut_change_le, a.essai_fin, a.created_at,
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
   order by (a.statut in ('essai', 'en_attente')) desc, a.created_at desc;
end $$;

create or replace function public.admin_statistiques() returns json
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public.admin_verifier();
  return json_build_object(
    'ateliers',          (select count(*) from public.ateliers),
    'actifs',            (select count(*) from public.ateliers where statut = 'actif'),
    'en_essai',          (select count(*) from public.ateliers where statut = 'essai' and essai_fin > now()),
    'essais_expires',    (select count(*) from public.ateliers where statut = 'essai' and essai_fin <= now()),
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

revoke execute on function public.admin_liste_ateliers() from public, anon;
grant execute on function public.admin_liste_ateliers() to authenticated;
revoke execute on function public.admin_prolonger_essai(uuid, int) from public, anon;
grant execute on function public.admin_prolonger_essai(uuid, int) to authenticated;
