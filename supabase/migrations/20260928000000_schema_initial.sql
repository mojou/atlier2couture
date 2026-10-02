-- =====================================================================
-- Atelier Couture : schéma multi-ateliers (multi-tenant)
--
-- Chaque table métier porte une colonne atelier_id. La sécurité par ligne
-- (RLS) garantit qu'un utilisateur ne lit et n'écrit que les données des
-- ateliers dont il est membre. Un même utilisateur peut appartenir à
-- plusieurs ateliers.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Ateliers (les « tenants ») et membres
-- ---------------------------------------------------------------------
create table public.ateliers (
  id                   uuid primary key default gen_random_uuid(),
  nom                  text not null check (length(trim(nom)) > 0),
  slogan               text,
  logo_url             text,
  telephone            text,
  email                text,
  adresse              text,
  ville                text,
  pays                 text,
  identifiant_fiscal   text,           -- NIF / IFU / NCC selon le pays
  registre_commerce    text,           -- RCCM
  devise               text not null default 'FCFA',
  unite_tissu          text not null default 'yd' check (unite_tissu in ('m', 'yd')),
  largeur_tissu_cm     numeric not null default 150 check (largeur_tissu_cm > 0),
  taux_tva             numeric not null default 0 check (taux_tva >= 0),
  acompte_pct          numeric not null default 50 check (acompte_pct between 0 and 100),
  validite_devis_jours int not null default 30,
  conditions_facture   text,
  pied_facture         text,
  couleur              text not null default '#7B2D8E',
  created_at           timestamptz not null default now()
);

create table public.membres (
  atelier_id uuid not null references public.ateliers(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null default 'couturier'
             check (role in ('proprietaire', 'gerant', 'couturier', 'caissier')),
  nom        text,
  created_at timestamptz not null default now(),
  primary key (atelier_id, user_id)
);
create index membres_user_idx on public.membres(user_id);

create or replace function public.est_membre(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.membres where atelier_id = a and user_id = auth.uid());
$$;

create or replace function public.est_gestionnaire(a uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.membres
    where atelier_id = a and user_id = auth.uid() and role in ('proprietaire', 'gerant')
  );
$$;

-- ---------------------------------------------------------------------
-- Clients et mesures
-- ---------------------------------------------------------------------
create table public.clients (
  id         uuid primary key default gen_random_uuid(),
  atelier_id uuid not null references public.ateliers(id) on delete cascade,
  nom        text not null,
  telephone  text,
  email      text,
  sexe       text check (sexe in ('homme', 'femme', 'enfant')),
  adresse    text,
  notes      text,
  created_at timestamptz not null default now()
);
create index clients_nom_idx on public.clients(atelier_id, nom);

-- Historique : on ne modifie pas une prise de mesures, on en ajoute une nouvelle.
create table public.mesures (
  id         uuid primary key default gen_random_uuid(),
  atelier_id uuid not null references public.ateliers(id) on delete cascade,
  client_id  uuid not null references public.clients(id) on delete cascade,
  valeurs    jsonb not null default '{}'::jsonb,   -- { "tour_poitrine": 98, ... } en cm
  note       text,
  prise_par  uuid default auth.uid() references auth.users(id) on delete set null,
  prise_le   timestamptz not null default now()
);
create index mesures_client_idx on public.mesures(client_id, prise_le desc);

-- Catalogue des modèles de l'atelier (prix de façon par défaut)
create table public.modeles (
  id            uuid primary key default gen_random_uuid(),
  atelier_id    uuid not null references public.ateliers(id) on delete cascade,
  nom           text not null,
  type_vetement text,
  prix_facon    numeric not null default 0 check (prix_facon >= 0),
  description   text,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------
create table public.stock_articles (
  id           uuid primary key default gen_random_uuid(),
  atelier_id   uuid not null references public.ateliers(id) on delete cascade,
  nom          text not null,
  categorie    text not null default 'tissu'
               check (categorie in ('tissu', 'doublure', 'fil', 'bouton', 'fermeture',
                                    'entoilage', 'accessoire', 'autre')),
  reference    text,
  couleur      text,
  unite        text not null default 'm',
  quantite     numeric not null default 0,
  seuil_alerte numeric not null default 0,
  prix_achat   numeric not null default 0,
  prix_vente   numeric not null default 0,
  largeur_cm   numeric,
  fournisseur  text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Commandes (production)
-- ---------------------------------------------------------------------
create table public.commandes (
  id             uuid primary key default gen_random_uuid(),
  atelier_id     uuid not null references public.ateliers(id) on delete cascade,
  numero         text,
  client_id      uuid not null references public.clients(id) on delete restrict,
  statut         text not null default 'nouvelle'
                 check (statut in ('nouvelle', 'decoupe', 'couture', 'essayage',
                                   'finitions', 'prete', 'livree', 'annulee')),
  priorite       text not null default 'normale' check (priorite in ('normale', 'urgente')),
  date_commande  date not null default current_date,
  date_livraison date,
  assigne_a      uuid references auth.users(id) on delete set null,
  articles       jsonb not null default '[]'::jsonb,   -- vêtements + calcul de coupe
  total          numeric not null default 0,
  stock_deduit   boolean not null default false,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (atelier_id, numero)
);
create index commandes_statut_idx on public.commandes(atelier_id, statut, date_livraison);

create table public.commande_historique (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  commande_id uuid not null references public.commandes(id) on delete cascade,
  statut      text not null,
  par         uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create table public.stock_mouvements (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  article_id  uuid not null references public.stock_articles(id) on delete cascade,
  type        text not null check (type in ('entree', 'sortie', 'ajustement')),
  quantite    numeric not null,  -- positive pour entrée/sortie, signée pour un ajustement
  motif       text,
  commande_id uuid references public.commandes(id) on delete set null,
  par         uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  check (type = 'ajustement' or quantite > 0)
);

-- ---------------------------------------------------------------------
-- Devis, factures, paiements
-- ---------------------------------------------------------------------
create table public.documents (
  id             uuid primary key default gen_random_uuid(),
  atelier_id     uuid not null references public.ateliers(id) on delete cascade,
  type           text not null check (type in ('devis', 'facture')),
  numero         text,
  client_id      uuid not null references public.clients(id) on delete restrict,
  commande_id    uuid references public.commandes(id) on delete set null,
  statut         text not null default 'brouillon'
                 check (statut in ('brouillon', 'envoye', 'accepte', 'refuse',
                                   'impayee', 'partielle', 'payee', 'annulee')),
  date_emission  date not null default current_date,
  date_echeance  date,
  lignes         jsonb not null default '[]'::jsonb,
  sous_total     numeric not null default 0,
  remise_montant numeric not null default 0,
  taux_tva       numeric not null default 0,
  montant_tva    numeric not null default 0,
  total          numeric not null default 0,
  montant_paye   numeric not null default 0,   -- tenu à jour par trigger
  notes          text,
  meta           jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  unique (atelier_id, type, numero)
);
create index documents_idx on public.documents(atelier_id, type, created_at desc);

create table public.paiements (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  montant     numeric not null check (montant > 0),
  mode        text not null default 'especes'
              check (mode in ('especes', 'mobile_money', 'carte', 'virement', 'autre')),
  reference   text,
  paye_le     timestamptz not null default now(),
  par         uuid default auth.uid() references auth.users(id) on delete set null
);
create index paiements_idx on public.paiements(atelier_id, paye_le);

-- ---------------------------------------------------------------------
-- Rendez-vous
-- ---------------------------------------------------------------------
create table public.rendez_vous (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  client_id   uuid not null references public.clients(id) on delete cascade,
  commande_id uuid references public.commandes(id) on delete set null,
  type        text not null default 'essayage'
              check (type in ('prise_mesures', 'essayage', 'livraison', 'retouche', 'autre')),
  debut       timestamptz not null,
  duree_min   int not null default 30,
  alarme_a    timestamptz,     -- heure à laquelle l'alarme musicale sonne
  note        text,
  statut      text not null default 'prevu' check (statut in ('prevu', 'honore', 'absent', 'annule')),
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index rendez_vous_idx on public.rendez_vous(atelier_id, debut);

-- ---------------------------------------------------------------------
-- Numérotation automatique par atelier et par année : FAC-2026-0001
-- ---------------------------------------------------------------------
create table public.compteurs (
  atelier_id uuid not null references public.ateliers(id) on delete cascade,
  type       text not null,
  annee      int  not null,
  valeur     int  not null default 0,
  primary key (atelier_id, type, annee)
);

create or replace function public.prochain_numero(a uuid, t text) returns text
language plpgsql security definer set search_path = public as $$
declare
  an int := extract(year from now())::int;
  v  int;
begin
  if not public.est_membre(a) then
    raise exception 'Accès refusé';
  end if;
  insert into public.compteurs (atelier_id, type, annee, valeur) values (a, t, an, 1)
  on conflict (atelier_id, type, annee) do update set valeur = public.compteurs.valeur + 1
  returning valeur into v;
  return case t when 'devis' then 'DEV' when 'facture' then 'FAC' else 'CMD' end
         || '-' || an || '-' || lpad(v::text, 4, '0');
end $$;

create or replace function public.tg_numero_commande() returns trigger
language plpgsql as $$
begin
  if new.numero is null then
    new.numero := public.prochain_numero(new.atelier_id, 'commande');
  end if;
  return new;
end $$;

create or replace function public.tg_numero_document() returns trigger
language plpgsql as $$
begin
  if new.numero is null then
    new.numero := public.prochain_numero(new.atelier_id, new.type);
  end if;
  return new;
end $$;

create trigger commandes_numero before insert on public.commandes
  for each row execute function public.tg_numero_commande();
create trigger documents_numero before insert on public.documents
  for each row execute function public.tg_numero_document();

-- ---------------------------------------------------------------------
-- Historique des étapes de production
-- ---------------------------------------------------------------------
create or replace function public.tg_commande_maj() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create or replace function public.tg_commande_historique() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' or new.statut is distinct from old.statut then
    insert into public.commande_historique (atelier_id, commande_id, statut)
    values (new.atelier_id, new.id, new.statut);
  end if;
  return null;
end $$;

create trigger commandes_maj before update on public.commandes
  for each row execute function public.tg_commande_maj();
create trigger commandes_historique after insert or update of statut on public.commandes
  for each row execute function public.tg_commande_historique();

-- ---------------------------------------------------------------------
-- Stock : la quantité suit les mouvements
-- ---------------------------------------------------------------------
create or replace function public.tg_stock_mouvement() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.stock_articles
                   where id = new.article_id and atelier_id = new.atelier_id) then
      raise exception 'Article de stock introuvable pour cet atelier';
    end if;
    update public.stock_articles
       set quantite = quantite + case new.type when 'sortie' then -new.quantite else new.quantite end
     where id = new.article_id;
  elsif tg_op = 'DELETE' then
    update public.stock_articles
       set quantite = quantite - case old.type when 'sortie' then -old.quantite else old.quantite end
     where id = old.article_id;
  end if;
  return null;
end $$;

create trigger stock_mouvements_quantite after insert or delete on public.stock_mouvements
  for each row execute function public.tg_stock_mouvement();

-- ---------------------------------------------------------------------
-- Paiements : montant payé et statut de la facture
-- ---------------------------------------------------------------------
create or replace function public.tg_paiement() returns trigger
language plpgsql as $$
declare
  d    uuid := coalesce(new.document_id, old.document_id);
  paye numeric;
begin
  select coalesce(sum(montant), 0) into paye from public.paiements where document_id = d;
  update public.documents
     set montant_paye = paye,
         statut = case
                    when statut = 'annulee' then statut
                    when total > 0 and paye >= total then 'payee'
                    when paye > 0 then 'partielle'
                    else 'impayee'
                  end
   where id = d and type = 'facture';
  return null;
end $$;

create trigger paiements_maj after insert or update or delete on public.paiements
  for each row execute function public.tg_paiement();

-- ---------------------------------------------------------------------
-- Sécurité par ligne (RLS)
-- ---------------------------------------------------------------------
alter table public.ateliers  enable row level security;
alter table public.membres   enable row level security;
alter table public.compteurs enable row level security;   -- aucun accès direct

create policy ateliers_lecture on public.ateliers for select to authenticated
  using (public.est_membre(id));
create policy ateliers_modif on public.ateliers for update to authenticated
  using (public.est_gestionnaire(id)) with check (public.est_gestionnaire(id));

create policy membres_lecture on public.membres for select to authenticated
  using (public.est_membre(atelier_id));
create policy membres_modif on public.membres for update to authenticated
  using (public.est_gestionnaire(atelier_id) and role <> 'proprietaire')
  with check (public.est_gestionnaire(atelier_id) and role <> 'proprietaire');
create policy membres_suppression on public.membres for delete to authenticated
  using (public.est_gestionnaire(atelier_id) and role <> 'proprietaire');

-- Tables métier : lecture / écriture pour tout membre, suppression réservée
-- au propriétaire et au gérant.
do $$
declare t text;
begin
  foreach t in array array['clients', 'mesures', 'modeles', 'stock_articles', 'stock_mouvements',
                           'commandes', 'commande_historique', 'documents', 'paiements',
                           'rendez_vous'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.est_membre(atelier_id))', t || '_lecture', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.est_membre(atelier_id))', t || '_ajout', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.est_membre(atelier_id)) with check (public.est_membre(atelier_id))', t || '_modif', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.est_gestionnaire(atelier_id))', t || '_suppression', t);
    execute format('create index if not exists %I on public.%I(atelier_id)', t || '_atelier_idx', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Création d'un atelier : l'utilisateur connecté en devient propriétaire
-- ---------------------------------------------------------------------
create or replace function public.creer_atelier(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  u      uuid := auth.uid();
  nouvel uuid;
begin
  if u is null then
    raise exception 'Non authentifié';
  end if;
  if coalesce(trim(p->>'nom'), '') = '' then
    raise exception 'Le nom de l''atelier est obligatoire';
  end if;

  insert into public.ateliers (nom, slogan, telephone, email, adresse, ville, pays,
                               identifiant_fiscal, registre_commerce, devise, unite_tissu,
                               largeur_tissu_cm, taux_tva, acompte_pct, validite_devis_jours,
                               conditions_facture, pied_facture, couleur)
  values (trim(p->>'nom'), p->>'slogan', p->>'telephone', p->>'email', p->>'adresse',
          p->>'ville', p->>'pays', p->>'identifiant_fiscal', p->>'registre_commerce',
          coalesce(nullif(p->>'devise', ''), 'FCFA'),
          coalesce(nullif(p->>'unite_tissu', ''), 'yd'),
          coalesce((p->>'largeur_tissu_cm')::numeric, 150),
          coalesce((p->>'taux_tva')::numeric, 0),
          coalesce((p->>'acompte_pct')::numeric, 50),
          coalesce((p->>'validite_devis_jours')::int, 30),
          p->>'conditions_facture', p->>'pied_facture',
          coalesce(nullif(p->>'couleur', ''), '#7B2D8E'))
  returning id into nouvel;

  insert into public.membres (atelier_id, user_id, role, nom)
  select nouvel, u, 'proprietaire', coalesce(raw_user_meta_data->>'nom', email)
    from auth.users where id = u;

  return nouvel;
end $$;

-- Ajout d'un employé déjà inscrit dans l'application (par son e-mail)
create or replace function public.ajouter_membre(a uuid, courriel text, r text) returns void
language plpgsql security definer set search_path = public as $$
declare
  u uuid;
  n text;
begin
  if not public.est_gestionnaire(a) then
    raise exception 'Réservé au propriétaire ou au gérant';
  end if;
  if r not in ('gerant', 'couturier', 'caissier') then
    raise exception 'Rôle invalide';
  end if;
  select id, coalesce(raw_user_meta_data->>'nom', email) into u, n
    from auth.users where lower(email) = lower(trim(courriel));
  if u is null then
    raise exception 'Aucun compte avec cet e-mail. La personne doit d''abord s''inscrire dans l''application.';
  end if;
  insert into public.membres (atelier_id, user_id, role, nom) values (a, u, r, n)
  on conflict (atelier_id, user_id) do update set role = excluded.role
  where public.membres.role <> 'proprietaire';
end $$;

revoke execute on function public.creer_atelier(jsonb) from public, anon;
revoke execute on function public.ajouter_membre(uuid, text, text) from public, anon;
revoke execute on function public.prochain_numero(uuid, text) from public, anon;
grant execute on function public.creer_atelier(jsonb) to authenticated;
grant execute on function public.ajouter_membre(uuid, text, text) to authenticated;
grant execute on function public.prochain_numero(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Stockage des logos : logos/<atelier_id>/logo.png (lecture publique)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('logos', 'logos', true)
on conflict (id) do nothing;

create policy logos_lecture on storage.objects for select to authenticated
  using (bucket_id = 'logos');
create policy logos_ajout on storage.objects for insert to authenticated
  with check (bucket_id = 'logos'
              and public.est_gestionnaire(((storage.foldername(name))[1])::uuid));
create policy logos_modif on storage.objects for update to authenticated
  using (bucket_id = 'logos'
         and public.est_gestionnaire(((storage.foldername(name))[1])::uuid));
create policy logos_suppression on storage.objects for delete to authenticated
  using (bucket_id = 'logos'
         and public.est_gestionnaire(((storage.foldername(name))[1])::uuid));
