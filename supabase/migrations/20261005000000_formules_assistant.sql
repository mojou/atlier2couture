-- =====================================================================
-- Formule Gratuite recentrée sur l'essentiel + quota de l'assistant
--
-- Gratuit : clients et mesures, commandes, calculateur, factures Classique,
-- agenda. La messagerie interne, les photos, la caisse et le lien de suivi
-- client passent en formule Standard (contrôlé ici, par la base).
-- =====================================================================

create or replace function public.tg_reserve_standard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.formule_effective(new.atelier_id) = 'gratuit' then
    raise exception 'LIMITE_FORMULE: % est disponible à partir de la formule Standard.', tg_argv[0];
  end if;
  return new;
end $$;

-- « messages_formule » s'exécute après « messages_avant » (ordre alphabétique),
-- qui renseigne atelier_id.
drop trigger if exists messages_formule on public.messages;
create trigger messages_formule before insert on public.messages
  for each row execute function public.tg_reserve_standard('La messagerie interne');

drop trigger if exists photos_formule on public.photos;
create trigger photos_formule before insert on public.photos
  for each row execute function public.tg_reserve_standard('L''ajout de photos');

drop trigger if exists depenses_formule on public.depenses;
create trigger depenses_formule before insert on public.depenses
  for each row execute function public.tg_reserve_standard('La caisse et les dépenses');

-- Lien de suivi : réservé aux ateliers en formule Standard ou Premium.
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
  where c.suivi_token = t
    and public.formule_effective(c.atelier_id) <> 'gratuit';
$$;

-- ---------------------------------------------------------------------
-- Assistant : nombre de questions par utilisateur et par jour
--   Gratuit 10 · Standard 50 · Premium 150 (formule de l'atelier courant)
-- ---------------------------------------------------------------------
create table if not exists public.assistant_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  jour    date not null default current_date,
  nb      int  not null default 0,
  primary key (user_id, jour)
);
alter table public.assistant_usage enable row level security;   -- accès uniquement par la fonction

-- Réserve une question. Renvoie le nombre restant, ou -1 si le quota du jour est atteint.
create or replace function public.assistant_reserver(a uuid default null) returns int
language plpgsql security definer set search_path = public as $$
declare
  u      uuid := auth.uid();
  limite int  := 10;
  f      text;
  n      int;
begin
  if u is null then
    raise exception 'Non authentifié';
  end if;
  if a is not null and public.est_membre_atelier(a) then
    f := public.formule_effective(a);
    limite := case f when 'premium' then 150 when 'standard' then 50 else 10 end;
  end if;
  if public.est_super_admin() then
    limite := 1000;
  end if;

  insert into public.assistant_usage (user_id, jour, nb) values (u, current_date, 0)
  on conflict (user_id, jour) do nothing;
  update public.assistant_usage set nb = nb + 1
   where user_id = u and jour = current_date and nb < limite
  returning nb into n;
  if n is null then
    return -1;
  end if;
  return limite - n;
end $$;

revoke execute on function public.assistant_reserver(uuid) from public, anon;
grant execute on function public.assistant_reserver(uuid) to authenticated;
