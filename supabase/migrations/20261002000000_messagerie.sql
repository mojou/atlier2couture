-- =====================================================================
-- Messagerie interne (inspirée d'Odoo Discuss)
--
-- - canal    : visible par tous les membres de l'atelier (dont « Général »)
-- - direct   : conversation privée entre deux membres
-- - commande : discussion attachée à une commande (comme le chatter d'Odoo)
-- Les messages arrivent en temps réel (Supabase Realtime, filtré par RLS).
-- =====================================================================

create table if not exists public.conversations (
  id          uuid primary key default gen_random_uuid(),
  atelier_id  uuid not null references public.ateliers(id) on delete cascade,
  type        text not null check (type in ('canal', 'direct', 'commande')),
  nom         text,
  commande_id uuid references public.commandes(id) on delete cascade,
  cle_directe text,   -- « userA:userB » triés, pour retrouver une conversation privée
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (atelier_id, cle_directe),
  unique (commande_id)
);
create index if not exists conversations_atelier_idx on public.conversations(atelier_id);
create unique index if not exists conversations_general_idx
  on public.conversations(atelier_id) where type = 'canal' and nom = 'Général';

-- Participants (conversations privées) et suivi de lecture (toutes conversations).
create table if not exists public.conversation_membres (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  dernier_lu      timestamptz,
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id              uuid primary key default gen_random_uuid(),
  atelier_id      uuid not null references public.ateliers(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  auteur_id       uuid default auth.uid() references auth.users(id) on delete set null,
  auteur_nom      text,
  contenu         text not null check (length(trim(contenu)) between 1 and 4000),
  created_at      timestamptz not null default now()
);
create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at desc);

-- ---------------------------------------------------------------------
-- Droits
-- ---------------------------------------------------------------------
create or replace function public.peut_voir_conversation(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversations v
     where v.id = c
       and public.est_membre(v.atelier_id)
       and (v.type <> 'direct'
            or exists (select 1 from public.conversation_membres m
                        where m.conversation_id = v.id and m.user_id = auth.uid()))
  );
$$;

alter table public.conversations enable row level security;
alter table public.conversation_membres enable row level security;
alter table public.messages enable row level security;

drop policy if exists conversations_lecture on public.conversations;
create policy conversations_lecture on public.conversations for select to authenticated
  using (public.peut_voir_conversation(id));
drop policy if exists conversations_suppression on public.conversations;
create policy conversations_suppression on public.conversations for delete to authenticated
  using (type = 'canal' and nom <> 'Général' and public.est_gestionnaire(atelier_id));

drop policy if exists conversation_membres_lecture on public.conversation_membres;
create policy conversation_membres_lecture on public.conversation_membres for select to authenticated
  using (public.peut_voir_conversation(conversation_id));

drop policy if exists messages_lecture on public.messages;
create policy messages_lecture on public.messages for select to authenticated
  using (public.peut_voir_conversation(conversation_id));
drop policy if exists messages_ajout on public.messages;
create policy messages_ajout on public.messages for insert to authenticated
  with check (auteur_id = auth.uid() and public.peut_voir_conversation(conversation_id));
drop policy if exists messages_suppression on public.messages;
create policy messages_suppression on public.messages for delete to authenticated
  using (auteur_id = auth.uid() or public.est_gestionnaire(atelier_id));

-- Atelier et nom de l'auteur renseignés par la base (pas par l'application).
create or replace function public.tg_message_avant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select atelier_id into new.atelier_id from public.conversations where id = new.conversation_id;
  new.auteur_id := auth.uid();
  select coalesce(m.nom, u.email) into new.auteur_nom
    from auth.users u
    left join public.membres m on m.user_id = u.id and m.atelier_id = new.atelier_id
   where u.id = auth.uid();
  new.contenu := trim(new.contenu);
  new.created_at := now();
  return new;
end $$;

drop trigger if exists messages_avant on public.messages;
create trigger messages_avant before insert on public.messages
  for each row execute function public.tg_message_avant();

-- ---------------------------------------------------------------------
-- Fonctions appelées par l'application
-- ---------------------------------------------------------------------

-- Crée le canal « Général » de l'atelier s'il n'existe pas.
create or replace function public.messagerie_initialiser(a uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  if not public.est_membre(a) then raise exception 'Accès refusé'; end if;
  select id into c from public.conversations where atelier_id = a and type = 'canal' and nom = 'Général';
  if c is null then
    insert into public.conversations (atelier_id, type, nom) values (a, 'canal', 'Général')
    on conflict do nothing returning id into c;
    if c is null then
      select id into c from public.conversations where atelier_id = a and type = 'canal' and nom = 'Général';
    end if;
  end if;
  return c;
end $$;

create or replace function public.creer_canal(a uuid, n text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  if not public.est_gestionnaire(a) then raise exception 'Réservé au propriétaire ou au gérant'; end if;
  if coalesce(trim(n), '') = '' then raise exception 'Nom du canal obligatoire'; end if;
  insert into public.conversations (atelier_id, type, nom) values (a, 'canal', trim(n)) returning id into c;
  return c;
end $$;

-- Retrouve ou crée la conversation privée avec un autre membre de l'atelier.
create or replace function public.conversation_directe(a uuid, autre uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  moi uuid := auth.uid();
  cle text;
  c uuid;
begin
  if not public.est_membre(a) then raise exception 'Accès refusé'; end if;
  if autre = moi then raise exception 'Choisissez un autre membre'; end if;
  if not exists (select 1 from public.membres where atelier_id = a and user_id = autre) then
    raise exception 'Cette personne ne fait pas partie de l''atelier';
  end if;
  cle := least(moi::text, autre::text) || ':' || greatest(moi::text, autre::text);
  select id into c from public.conversations where atelier_id = a and cle_directe = cle;
  if c is null then
    insert into public.conversations (atelier_id, type, cle_directe) values (a, 'direct', cle) returning id into c;
    insert into public.conversation_membres (conversation_id, user_id) values (c, moi), (c, autre);
  end if;
  return c;
end $$;

-- Retrouve ou crée la discussion d'une commande.
create or replace function public.conversation_commande(cmd uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid;
  c uuid;
begin
  select atelier_id into a from public.commandes where id = cmd;
  if a is null or not public.est_membre(a) then raise exception 'Accès refusé'; end if;
  select id into c from public.conversations where commande_id = cmd;
  if c is null then
    insert into public.conversations (atelier_id, type, commande_id) values (a, 'commande', cmd)
    on conflict (commande_id) do nothing returning id into c;
    if c is null then select id into c from public.conversations where commande_id = cmd; end if;
  end if;
  return c;
end $$;

create or replace function public.marquer_lu(c uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.peut_voir_conversation(c) then raise exception 'Accès refusé'; end if;
  insert into public.conversation_membres (conversation_id, user_id, dernier_lu) values (c, auth.uid(), now())
  on conflict (conversation_id, user_id) do update set dernier_lu = now();
end $$;

-- Liste des conversations visibles, avec dernier message et nombre de non-lus.
create or replace function public.messagerie_liste(a uuid)
returns table (
  id uuid, type text, nom text, commande_id uuid, commande_numero text, client_nom text,
  autre_id uuid, autre_nom text, dernier_message text, dernier_auteur text,
  dernier_le timestamptz, non_lus bigint
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.est_membre(a) then raise exception 'Accès refusé'; end if;
  return query
  select v.id, v.type, v.nom, v.commande_id, cmd.numero, cl.nom,
         au.user_id, coalesce(mb.nom, u.email::text),
         dm.contenu, dm.auteur_nom, dm.created_at,
         (select count(*) from public.messages x
           where x.conversation_id = v.id
             and x.auteur_id is distinct from auth.uid()
             and x.created_at > coalesce(lu.dernier_lu, '-infinity'::timestamptz))
    from public.conversations v
    left join public.commandes cmd on cmd.id = v.commande_id
    left join public.clients cl on cl.id = cmd.client_id
    left join public.conversation_membres lu on lu.conversation_id = v.id and lu.user_id = auth.uid()
    left join lateral (
      select m.user_id from public.conversation_membres m
       where v.type = 'direct' and m.conversation_id = v.id and m.user_id <> auth.uid() limit 1
    ) au on true
    left join public.membres mb on mb.atelier_id = a and mb.user_id = au.user_id
    left join auth.users u on u.id = au.user_id
    left join lateral (
      select x.contenu, x.auteur_nom, x.created_at from public.messages x
       where x.conversation_id = v.id order by x.created_at desc limit 1
    ) dm on true
   where v.atelier_id = a
     and public.peut_voir_conversation(v.id)
     and (v.type <> 'commande' or dm.created_at is not null)
   order by (v.type = 'canal' and v.nom = 'Général') desc, coalesce(dm.created_at, v.created_at) desc;
end $$;

create or replace function public.messagerie_non_lus(a uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select count(*) from public.messages x
    join public.conversations v on v.id = x.conversation_id
    left join public.conversation_membres lu on lu.conversation_id = v.id and lu.user_id = auth.uid()
   where v.atelier_id = a
     and public.peut_voir_conversation(v.id)
     and x.auteur_id is distinct from auth.uid()
     and x.created_at > coalesce(lu.dernier_lu, '-infinity'::timestamptz);
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.messagerie_initialiser(uuid)', 'public.creer_canal(uuid, text)',
    'public.conversation_directe(uuid, uuid)', 'public.conversation_commande(uuid)',
    'public.marquer_lu(uuid)', 'public.messagerie_liste(uuid)', 'public.messagerie_non_lus(uuid)',
    'public.peut_voir_conversation(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- Temps réel : les nouveaux messages sont poussés aux membres autorisés.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
