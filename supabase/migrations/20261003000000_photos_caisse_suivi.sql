-- =====================================================================
-- Photos de commande, suivi public des commandes, dépenses (caisse),
-- paramètres de paie des couturiers.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Photos : modèle souhaité, tissu déposé, essayage, vêtement fini
-- Fichiers dans le bucket privé « photos » : <atelier_id>/<commande_id>/<fichier>
-- ---------------------------------------------------------------------
create table if not exists public.photos (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  commande_id uuid references public.commandes(id) on delete cascade,
  client_id   uuid references public.clients(id) on delete cascade,
  categorie   text not null default 'modele'
              check (categorie in ('modele', 'tissu', 'essayage', 'resultat', 'autre')),
  chemin      text not null,
  legende     text,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists photos_commande_idx on public.photos(commande_id, created_at);

insert into storage.buckets (id, name, public) values ('photos', 'photos', false)
on conflict (id) do nothing;

drop policy if exists photos_fichiers_lecture on storage.objects;
create policy photos_fichiers_lecture on storage.objects for select to authenticated
  using (bucket_id = 'photos' and public.est_membre(((storage.foldername(name))[1])::uuid));
drop policy if exists photos_fichiers_ajout on storage.objects;
create policy photos_fichiers_ajout on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.est_membre(((storage.foldername(name))[1])::uuid));
drop policy if exists photos_fichiers_suppression on storage.objects;
create policy photos_fichiers_suppression on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and public.est_membre(((storage.foldername(name))[1])::uuid));

-- ---------------------------------------------------------------------
-- Dépenses de l'atelier (caisse) — les salaires versés y sont enregistrés aussi
-- ---------------------------------------------------------------------
create table if not exists public.depenses (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  date        date not null default current_date,
  categorie   text not null default 'autre'
              check (categorie in ('tissu', 'fournitures', 'loyer', 'electricite', 'transport',
                                   'salaire', 'materiel', 'autre')),
  libelle     text not null check (length(trim(libelle)) > 0),
  montant     numeric not null check (montant > 0),
  mode        text not null default 'especes'
              check (mode in ('especes', 'mobile_money', 'carte', 'virement', 'autre')),
  membre_id   uuid references auth.users(id) on delete set null,   -- bénéficiaire d'un salaire
  periode     text,                                                -- ex. 2026-10 pour une paie
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists depenses_idx on public.depenses(atelier_id, date desc);

-- Même règles que les autres tables métier : membres de l'atelier actif,
-- suppression réservée au propriétaire et au gérant.
do $$
declare t text;
begin
  foreach t in array array['photos', 'depenses'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_lecture', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.est_membre(atelier_id))', t || '_lecture', t);
    execute format('drop policy if exists %I on public.%I', t || '_ajout', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (public.est_membre(atelier_id))', t || '_ajout', t);
    execute format('drop policy if exists %I on public.%I', t || '_modif', t);
    execute format('create policy %I on public.%I for update to authenticated using (public.est_membre(atelier_id)) with check (public.est_membre(atelier_id))', t || '_modif', t);
    execute format('drop policy if exists %I on public.%I', t || '_suppression', t);
    execute format('create policy %I on public.%I for delete to authenticated using (public.est_gestionnaire(atelier_id) or created_by = auth.uid())', t || '_suppression', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Paie des couturiers : à la pièce (montant par vêtement) ou en
-- pourcentage du prix de façon
-- ---------------------------------------------------------------------
alter table public.membres add column if not exists paie_mode text not null default 'aucun'
  check (paie_mode in ('aucun', 'piece', 'pourcentage'));
alter table public.membres add column if not exists paie_valeur numeric not null default 0
  check (paie_valeur >= 0);

-- ---------------------------------------------------------------------
-- Suivi public : lien secret à envoyer au client (sans compte)
-- ---------------------------------------------------------------------
alter table public.commandes add column if not exists suivi_token uuid not null default gen_random_uuid();
create unique index if not exists commandes_suivi_token_idx on public.commandes(suivi_token);

-- Ne renvoie que le strict nécessaire : prénom du client, étapes, date, reste à payer.
create or replace function public.suivi_commande(t uuid) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'numero', c.numero,
    'statut', c.statut,
    'date_commande', c.date_commande,
    'date_livraison', c.date_livraison,
    'client', split_part(trim(cl.nom), ' ', 1),
    'articles', (select coalesce(json_agg(json_build_object('designation', x->>'designation',
                                                            'quantite', x->>'quantite')), '[]'::json)
                   from jsonb_array_elements(c.articles) x),
    'reste', (select coalesce(sum(d.total - d.montant_paye), 0) from public.documents d
               where d.commande_id = c.id and d.type = 'facture' and d.statut <> 'annulee'),
    'atelier', a.nom,
    'telephone', a.telephone,
    'adresse', concat_ws(', ', nullif(a.adresse, ''), nullif(a.ville, '')),
    'logo', a.logo_url,
    'couleur', a.couleur,
    'devise', a.devise
  )
  from public.commandes c
  join public.ateliers a on a.id = c.atelier_id
  join public.clients cl on cl.id = c.client_id
  where c.suivi_token = t;
$$;

grant execute on function public.suivi_commande(uuid) to anon, authenticated;
