-- =====================================================================
-- Modulo ESERCITAZIONI (MVP)
--   - anagrafica Sezioni canonica (CAP / 1° RGPT, mail PC)
--   - liste configurabili patenti / abilitazioni
--   - esercitazioni, servizi giornalieri, Sezioni invitate (token), adesioni
--   - vista senza CF/cellulare per il livello "base"
--   - RPC pubbliche per il link della Sezione (unico accesso di anon)
-- Permesso app: chiave 'esercitazioni' (livelli 'completo' / 'base').
-- Da applicare in un'unica transazione.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Sezioni ANA canoniche (chiave = stessi nomi di SEZIONI_ANA in index.html)
-- ---------------------------------------------------------------------
create table public.sezioni_ana (
  nome        text primary key,
  in_cap      boolean not null default false,
  in_rgpt     boolean not null default true,
  email_pc    text,
  ordine      integer not null default 0,
  created_at  timestamptz not null default now()
);

insert into public.sezioni_ana (nome, in_cap, in_rgpt, email_pc, ordine) values
  ('ACQUI TERME',       true,  true, 'pc.acquiterme@ana.it',  1),
  ('ALESSANDRIA',       true,  true, 'pc.alessandria@ana.it', 2),
  ('ASTI',              true,  true, 'pc.asti@ana.it',        3),
  ('BIELLA',            true,  true, 'pc.biella@ana.it',      4),
  ('CASALE MONFERRATO', true,  true, 'pc.casale@ana.it',      5),
  ('CEVA',              true,  true, 'pc.ceva@ana.it',        6),
  ('CUNEO',             true,  true, 'pc.cuneo@ana.it',       7),
  ('DOMODOSSOLA',       true,  true, 'pc.domodossola@ana.it', 8),
  ('INTRA',             true,  true, 'pc.intra@ana.it',       9),
  ('IVREA',             true,  true, 'pc.ivrea@ana.it',       10),
  ('MONDOVI',           true,  true, 'pc.mondovi@ana.it',     11),
  ('NOVARA',            true,  true, 'pc.novara@ana.it',      12),
  ('OMEGNA',            true,  true, 'pc.omegna@ana.it',      13),
  ('PINEROLO',          true,  true, 'pc.pinerolo@ana.it',    14),
  ('SALUZZO',           true,  true, 'pc.saluzzo@ana.it',     15),
  ('TORINO',            true,  true, 'pc.torino@ana.it',      16),
  ('VALSESIANA',        true,  true, 'pc.valsesiana@ana.it',  17),
  ('VALSUSA',           true,  true, 'pc.valsusa@ana.it',     18),
  ('VERCELLI',          true,  true, 'pc.vercelli@ana.it',    19),
  ('GENOVA',            false, true, 'pc.genova@ana.it',      20),
  ('IMPERIA',           false, true, 'pc.imperia@ana.it',     21),
  ('LA SPEZIA',         false, true, 'pc.laspezia@ana.it',    22),
  ('SAVONA',            false, true, 'pc.savona@ana.it',      23),
  ('AOSTA',             false, true, 'pc.aosta@ana.it',       24);

-- ---------------------------------------------------------------------
-- 2. Liste configurabili (stesso modello di tlc_categorie)
-- ---------------------------------------------------------------------
create table public.esercitazioni_patenti (
  id          bigint generated always as identity primary key,
  nome        text not null unique,
  ordine      integer not null default 0,
  created_at  timestamptz not null default now()
);
insert into public.esercitazioni_patenti (nome, ordine) values
  ('B',1), ('BE',2), ('C',3), ('CE',4), ('D',5), ('DE',6);

create table public.esercitazioni_abilitazioni (
  id          bigint generated always as identity primary key,
  nome        text not null unique,
  ordine      integer not null default 0,
  created_at  timestamptz not null default now()
);
insert into public.esercitazioni_abilitazioni (nome, ordine) values
  ('MMT',1), ('TRIS',2);

-- ---------------------------------------------------------------------
-- 3. Validazione codice fiscale (formato + carattere di controllo, omocodia ammessa)
-- ---------------------------------------------------------------------
create function public.cf_valido(p_cf text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  dispari int[] := array[1,0,5,7,9,13,15,17,19,21,2,4,18,20,11,3,6,8,12,14,16,10,22,25,24,23];
  s int := 0;
  c text;
  v int;
begin
  if p_cf is null
     or p_cf !~ '^[A-Z]{6}[0-9LMNPQRSTUV]{2}[ABCDEHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]$' then
    return false;
  end if;
  for i in 1..15 loop
    c := substr(p_cf, i, 1);
    v := case when c ~ '[0-9]' then ascii(c) - 48 else ascii(c) - 65 end;
    s := s + case when i % 2 = 1 then dispari[v + 1] else v end;
  end loop;
  return substr(p_cf, 16, 1) = chr(65 + (s % 26));
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Esercitazioni
-- ---------------------------------------------------------------------
create table public.esercitazioni (
  id                 bigint generated always as identity primary key,
  titolo             text not null,
  ente               text not null check (ente in ('CAP','1RGPT')),
  luogo              text,
  data_inizio        date not null,
  data_fine          date not null,
  chiusura_adesioni  timestamptz,
  descrizione        text,
  stato              text not null default 'bozza' check (stato in ('bozza','aperta','chiusa','conclusa')),
  created_by         uuid references auth.users(id) default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint esercitazioni_date_check check (data_fine >= data_inizio)
);

-- servizi giornalieri (generati dall'app in base alle date, modificabili)
create table public.esercitazione_servizi (
  id                bigint generated always as identity primary key,
  esercitazione_id  bigint not null references public.esercitazioni(id) on delete cascade,
  giorno            date not null,
  tipo              text not null check (tipo in ('pranzo','cena','pernotto')),
  unique (esercitazione_id, giorno, tipo)
);

-- una riga per Sezione invitata, con token per il link pubblico
create table public.esercitazione_sezioni (
  id                bigint generated always as identity primary key,
  esercitazione_id  bigint not null references public.esercitazioni(id) on delete cascade,
  sezione           text not null references public.sezioni_ana(nome) on update cascade,
  token             uuid not null unique default gen_random_uuid(),
  stato             text not null default 'in_attesa' check (stato in ('in_attesa','risposto','non_partecipa')),
  risposto_at       timestamptz,
  unique (esercitazione_id, sezione),
  unique (id, esercitazione_id)          -- per la FK composta di adesioni
);

create table public.adesioni (
  id                        bigint generated always as identity primary key,
  esercitazione_id          bigint not null references public.esercitazioni(id) on delete cascade,
  esercitazione_sezione_id  bigint not null,
  volontario_id             bigint references public.volontari_formazione(id) on delete set null,
  cognome                   text not null check (length(trim(cognome)) between 1 and 80),
  nome                      text not null check (length(trim(nome)) between 1 and 80),
  codice_fiscale            text not null check (public.cf_valido(codice_fiscale)),
  cellulare                 text check (cellulare is null or length(cellulare) <= 30),
  patenti                   text[] not null default '{}',
  abilitazioni              text[] not null default '{}',
  note                      text check (note is null or length(note) <= 500),
  created_at                timestamptz not null default now(),
  unique (esercitazione_id, codice_fiscale),
  -- la Sezione deve appartenere alla stessa esercitazione
  foreign key (esercitazione_sezione_id, esercitazione_id)
    references public.esercitazione_sezioni(id, esercitazione_id) on delete cascade
);
create index adesioni_sezione_idx on public.adesioni (esercitazione_sezione_id);
create index adesioni_volontario_idx on public.adesioni (volontario_id);

create table public.adesione_servizi (
  adesione_id  bigint not null references public.adesioni(id) on delete cascade,
  servizio_id  bigint not null references public.esercitazione_servizi(id) on delete cascade,
  primary key (adesione_id, servizio_id)
);
create index adesione_servizi_servizio_idx on public.adesione_servizi (servizio_id);

-- ---------------------------------------------------------------------
-- 5. Trigger: updated_at e audit (stesso fn_log_attivita degli altri moduli).
--    Niente audit su esercitazione_servizi / adesione_servizi (righe di servizio, molto rumore).
-- ---------------------------------------------------------------------
create trigger trg_esercitazioni_updated_at before update on public.esercitazioni
  for each row execute function public.set_updated_at();

create trigger trg_log_attivita after insert or update or delete on public.sezioni_ana
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazioni_patenti
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazioni_abilitazioni
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazioni
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazione_sezioni
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.adesioni
  for each row execute function public.fn_log_attivita();

-- ---------------------------------------------------------------------
-- 6. RLS e permessi
--    lettura: ha_accesso('esercitazioni')  (completo o base)
--    scrittura: ha_permesso('esercitazioni') (completo; it_admin sempre)
--    adesioni / adesione_servizi: solo completo (contengono CF e cellulare)
--    anon: nessun accesso alle tabelle
-- ---------------------------------------------------------------------
alter table public.sezioni_ana               enable row level security;
alter table public.esercitazioni_patenti     enable row level security;
alter table public.esercitazioni_abilitazioni enable row level security;
alter table public.esercitazioni             enable row level security;
alter table public.esercitazione_servizi     enable row level security;
alter table public.esercitazione_sezioni     enable row level security;
alter table public.adesioni                  enable row level security;
alter table public.adesione_servizi          enable row level security;

revoke all on public.sezioni_ana, public.esercitazioni_patenti, public.esercitazioni_abilitazioni,
              public.esercitazioni, public.esercitazione_servizi, public.esercitazione_sezioni,
              public.adesioni, public.adesione_servizi
  from anon;

-- Anagrafiche condivise: leggibili da tutti gli utenti autenticati
create policy "sezioni_ana: lettura" on public.sezioni_ana
  for select to authenticated using (true);
create policy "sezioni_ana: scrittura" on public.sezioni_ana
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

create policy "sezione: lettura" on public.esercitazioni_patenti
  for select to authenticated using (true);
create policy "sezione: scrittura" on public.esercitazioni_patenti
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

create policy "sezione: lettura" on public.esercitazioni_abilitazioni
  for select to authenticated using (true);
create policy "sezione: scrittura" on public.esercitazioni_abilitazioni
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

-- Esercitazioni, servizi, Sezioni invitate: lettura completo/base, scrittura completo
create policy "sezione: lettura" on public.esercitazioni
  for select to authenticated using (public.ha_accesso('esercitazioni'));
create policy "sezione: scrittura" on public.esercitazioni
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

create policy "sezione: lettura" on public.esercitazione_servizi
  for select to authenticated using (public.ha_accesso('esercitazioni'));
create policy "sezione: scrittura" on public.esercitazione_servizi
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

create policy "sezione: lettura" on public.esercitazione_sezioni
  for select to authenticated using (public.ha_accesso('esercitazioni'));
create policy "sezione: scrittura" on public.esercitazione_sezioni
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

-- Adesioni: SOLO completo (lettura compresa). Il livello base usa la vista sotto.
create policy "sezione: completo" on public.adesioni
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));
create policy "sezione: completo" on public.adesione_servizi
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

-- Token del link pubblico: NON leggibile direttamente dagli utenti autenticati.
-- Una revoke sulla sola colonna non basta se resta il SELECT sulla tabella, quindi:
-- tolgo il SELECT di tabella e lo ridò colonna per colonna, token escluso.
-- (L'app deve selezionare colonne esplicite: niente select('*') né returning del token.)
revoke select on public.esercitazione_sezioni from authenticated;
grant select (id, esercitazione_id, sezione, stato, risposto_at) on public.esercitazione_sezioni to authenticated;

-- Sezione + token + mail PC, solo per chi ha "completo" (copia link / mailto / dopo una rigenerazione).
create function public.esercitazione_link(p_esercitazione_id bigint)
returns table (esercitazione_sezione_id bigint, sezione text, token uuid, email_pc text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.ha_permesso('esercitazioni') then
    raise exception 'Permesso negato.';
  end if;
  return query
    select s.id, s.sezione, s.token, z.email_pc
      from public.esercitazione_sezioni s
      join public.sezioni_ana z on z.nome = s.sezione
     where s.esercitazione_id = p_esercitazione_id
     order by z.ordine, s.sezione;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. Vista per il livello "base": adesioni SENZA codice fiscale e cellulare.
--    Gira con i privilegi del proprietario (non security_invoker) perché il livello
--    base non può leggere la tabella adesioni; il filtro ha_accesso() limita chi la vede.
-- ---------------------------------------------------------------------
create view public.v_adesioni_base
with (security_barrier = true)
as
select a.id,
       a.esercitazione_id,
       a.esercitazione_sezione_id,
       s.sezione,
       a.cognome,
       a.nome,
       a.patenti,
       a.abilitazioni,
       a.created_at,
       coalesce((select array_agg(x.servizio_id order by x.servizio_id)
                 from public.adesione_servizi x where x.adesione_id = a.id), '{}') as servizi
from public.adesioni a
join public.esercitazione_sezioni s on s.id = a.esercitazione_sezione_id
where public.ha_accesso('esercitazioni');

revoke all on public.v_adesioni_base from public;
revoke all on public.v_adesioni_base from anon;
revoke all on public.v_adesioni_base from authenticated;
grant select on public.v_adesioni_base to authenticated;

-- ---------------------------------------------------------------------
-- 8. RPC pubbliche per il link della Sezione (security definer, unico accesso di anon)
-- ---------------------------------------------------------------------

-- Dati per la pagina adesione.html: esercitazione, Sezione, servizi, liste,
-- volontari GIÀ INSERITI DA QUELLA SEZIONE. Nessun dato dall'anagrafica volontari.
create function public.adesione_get(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_sez  public.esercitazione_sezioni%rowtype;
  v_es   public.esercitazioni%rowtype;
begin
  select * into v_sez from public.esercitazione_sezioni where token = p_token;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.esercitazioni where id = v_sez.esercitazione_id;
  if v_es.stato = 'bozza' then
    raise exception 'Le adesioni per questa esercitazione non sono ancora aperte.';
  end if;

  return jsonb_build_object(
    'esercitazione', jsonb_build_object(
      'titolo', v_es.titolo, 'ente', v_es.ente, 'luogo', v_es.luogo,
      'data_inizio', v_es.data_inizio, 'data_fine', v_es.data_fine,
      'chiusura_adesioni', v_es.chiusura_adesioni, 'descrizione', v_es.descrizione,
      'stato', v_es.stato),
    'sezione', v_sez.sezione,
    'stato_sezione', v_sez.stato,
    'risposto_at', v_sez.risposto_at,
    'modificabile', (v_es.stato = 'aperta'
                     and (v_es.chiusura_adesioni is null or now() <= v_es.chiusura_adesioni)),
    'servizi', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'giorno', s.giorno, 'tipo', s.tipo)
                                          order by s.giorno, array_position(array['pranzo','cena','pernotto'], s.tipo))
                         from public.esercitazione_servizi s where s.esercitazione_id = v_es.id), '[]'::jsonb),
    'patenti', coalesce((select jsonb_agg(nome order by ordine, nome) from public.esercitazioni_patenti), '[]'::jsonb),
    'abilitazioni', coalesce((select jsonb_agg(nome order by ordine, nome) from public.esercitazioni_abilitazioni), '[]'::jsonb),
    'volontari', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'cognome', a.cognome, 'nome', a.nome, 'codice_fiscale', a.codice_fiscale,
                 'cellulare', a.cellulare, 'patenti', a.patenti, 'abilitazioni', a.abilitazioni,
                 'note', a.note,
                 'servizi', coalesce((select jsonb_agg(x.servizio_id) from public.adesione_servizi x
                                      where x.adesione_id = a.id), '[]'::jsonb))
               order by a.cognome, a.nome)
        from public.adesioni a where a.esercitazione_sezione_id = v_sez.id), '[]'::jsonb)
  );
end;
$$;

-- Sostituisce TUTTE le adesioni della Sezione con quelle inviate e imposta stato = 'risposto'.
-- p_volontari: [{cognome, nome, codice_fiscale, cellulare, patenti[], abilitazioni[], note, servizi[]}]
create function public.adesione_salva(p_token uuid, p_volontari jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  c_max_volontari constant int := 150;
  v_sez       public.esercitazione_sezioni%rowtype;
  v_es        public.esercitazioni%rowtype;
  v           jsonb;
  v_cf        text;
  v_cognome   text;
  v_nome      text;
  v_cell      text;
  v_note      text;
  v_patenti   text[];
  v_abil      text[];
  v_servizi   bigint[];
  v_cf_visti  text[] := '{}';
  v_doppi     text;
  v_id        bigint;
  n           int := 0;
begin
  -- blocco la riga della Sezione: due invii contemporanei non si sovrappongono
  select * into v_sez from public.esercitazione_sezioni where token = p_token for update;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.esercitazioni where id = v_sez.esercitazione_id;
  if v_es.stato <> 'aperta' or (v_es.chiusura_adesioni is not null and now() > v_es.chiusura_adesioni) then
    raise exception 'Le adesioni per questa esercitazione sono chiuse.';
  end if;

  if p_volontari is null or jsonb_typeof(p_volontari) <> 'array' then
    raise exception 'Dati non validi.';
  end if;
  if jsonb_array_length(p_volontari) = 0 then
    raise exception 'Inserisci almeno un volontario, oppure usa "La Sezione non partecipa".';
  end if;
  if jsonb_array_length(p_volontari) > c_max_volontari then
    raise exception 'Puoi inviare al massimo % volontari per Sezione.', c_max_volontari;
  end if;

  -- 1) validazione completa prima di toccare i dati
  for v in select * from jsonb_array_elements(p_volontari) loop
    n := n + 1;
    v_cognome := upper(trim(coalesce(v->>'cognome', '')));
    v_nome    := upper(trim(coalesce(v->>'nome', '')));
    v_cf      := upper(regexp_replace(coalesce(v->>'codice_fiscale', ''), '\s', '', 'g'));
    if v_cognome = '' or v_nome = '' then
      raise exception 'Volontario n. %: cognome e nome sono obbligatori.', n;
    end if;
    if length(v_cognome) > 80 or length(v_nome) > 80 then
      raise exception 'Volontario n. %: cognome o nome troppo lungo.', n;
    end if;
    if not public.cf_valido(v_cf) then
      raise exception 'Volontario n. % (% %): codice fiscale non valido.', n, v_cognome, v_nome;
    end if;
    if v_cf = any(v_cf_visti) then
      raise exception 'Il codice fiscale % è inserito due volte.', v_cf;
    end if;
    v_cf_visti := v_cf_visti || v_cf;
    if length(coalesce(v->>'cellulare', '')) > 30 then
      raise exception 'Volontario n. %: numero di cellulare troppo lungo.', n;
    end if;
    if length(coalesce(v->>'note', '')) > 500 then
      raise exception 'Volontario n. %: note troppo lunghe (max 500 caratteri).', n;
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(v->'patenti', '[]')) p(x)
               where x not in (select nome from public.esercitazioni_patenti)) then
      raise exception 'Volontario n. %: patente non riconosciuta.', n;
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(v->'abilitazioni', '[]')) p(x)
               where x not in (select nome from public.esercitazioni_abilitazioni)) then
      raise exception 'Volontario n. %: abilitazione non riconosciuta.', n;
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(v->'servizi', '[]')) p(x)
               where case when x ~ '^[0-9]{1,18}$'
                          then x::bigint not in (select id from public.esercitazione_servizi
                                                 where esercitazione_id = v_es.id)
                          else true end) then
      raise exception 'Volontario n. %: servizio non valido per questa esercitazione.', n;
    end if;
  end loop;

  -- 2) CF già iscritti da un'ALTRA Sezione della stessa esercitazione
  select string_agg(a.codice_fiscale, ', ' order by a.codice_fiscale) into v_doppi
  from public.adesioni a
  where a.esercitazione_id = v_es.id
    and a.esercitazione_sezione_id <> v_sez.id
    and a.codice_fiscale = any(v_cf_visti);
  if v_doppi is not null then
    raise exception 'Questi codici fiscali risultano già iscritti da un''altra Sezione: %', v_doppi;
  end if;

  -- 3) allineamento per CF dentro la Sezione (gli id delle adesioni restano stabili:
  --    serviranno per check-in e attestati). Tolgo solo i volontari non più in elenco.
  delete from public.adesioni
   where esercitazione_sezione_id = v_sez.id
     and codice_fiscale <> all(v_cf_visti);

  for v in select * from jsonb_array_elements(p_volontari) loop
    v_cf      := upper(regexp_replace(coalesce(v->>'codice_fiscale', ''), '\s', '', 'g'));
    v_cell    := nullif(trim(coalesce(v->>'cellulare', '')), '');
    v_note    := nullif(trim(coalesce(v->>'note', '')), '');
    select coalesce(array_agg(distinct x), '{}') into v_patenti
      from jsonb_array_elements_text(coalesce(v->'patenti', '[]')) p(x);
    select coalesce(array_agg(distinct x), '{}') into v_abil
      from jsonb_array_elements_text(coalesce(v->'abilitazioni', '[]')) p(x);
    select coalesce(array_agg(distinct x::bigint), '{}') into v_servizi
      from jsonb_array_elements_text(coalesce(v->'servizi', '[]')) p(x);

    -- Nuovo CF → insert; CF già della Sezione → update (solo se qualcosa è cambiato,
    -- così l'audit non registra modifiche vuote). Un CF di un'altra Sezione non viene toccato.
    insert into public.adesioni as a (esercitazione_id, esercitazione_sezione_id, volontario_id,
                                      cognome, nome, codice_fiscale, cellulare, patenti, abilitazioni, note)
    values (v_es.id, v_sez.id,
            (select vf.id from public.volontari_formazione vf where vf.codice_fiscale = v_cf),
            upper(trim(v->>'cognome')), upper(trim(v->>'nome')), v_cf, v_cell, v_patenti, v_abil, v_note)
    on conflict (esercitazione_id, codice_fiscale) do update
       set volontario_id = excluded.volontario_id,
           cognome       = excluded.cognome,
           nome          = excluded.nome,
           cellulare     = excluded.cellulare,
           patenti       = excluded.patenti,
           abilitazioni  = excluded.abilitazioni,
           note          = excluded.note
     where a.esercitazione_sezione_id = excluded.esercitazione_sezione_id
       and (a.volontario_id, a.cognome, a.nome, a.cellulare, a.patenti, a.abilitazioni, a.note)
           is distinct from
           (excluded.volontario_id, excluded.cognome, excluded.nome, excluded.cellulare,
            excluded.patenti, excluded.abilitazioni, excluded.note);

    select a.id into v_id
      from public.adesioni a
     where a.esercitazione_id = v_es.id
       and a.codice_fiscale = v_cf
       and a.esercitazione_sezione_id = v_sez.id;
    if v_id is null then
      -- inserito nel frattempo da un'altra Sezione
      raise exception 'Il codice fiscale % risulta già iscritto da un''altra Sezione.', v_cf;
    end if;

    -- servizi: tolgo/aggiungo solo le differenze
    delete from public.adesione_servizi
     where adesione_id = v_id
       and servizio_id <> all(v_servizi);
    insert into public.adesione_servizi (adesione_id, servizio_id)
    select v_id, unnest(v_servizi)
    on conflict (adesione_id, servizio_id) do nothing;
  end loop;

  update public.esercitazione_sezioni
     set stato = 'risposto', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true, 'volontari', jsonb_array_length(p_volontari));
end;
$$;

-- La Sezione dichiara di non partecipare: toglie eventuali adesioni già inviate.
create function public.adesione_nessuna(p_token uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_sez public.esercitazione_sezioni%rowtype;
  v_es  public.esercitazioni%rowtype;
begin
  select * into v_sez from public.esercitazione_sezioni where token = p_token for update;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.esercitazioni where id = v_sez.esercitazione_id;
  if v_es.stato <> 'aperta' or (v_es.chiusura_adesioni is not null and now() > v_es.chiusura_adesioni) then
    raise exception 'Le adesioni per questa esercitazione sono chiuse.';
  end if;

  delete from public.adesioni where esercitazione_sezione_id = v_sez.id;
  update public.esercitazione_sezioni
     set stato = 'non_partecipa', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Privilegi sulle funzioni
--    Le funzioni create da postgres sono eseguibili da anon per default: li tolgo.
--    anon può eseguire SOLO le tre RPC del link pubblico.
-- ---------------------------------------------------------------------
revoke all on function public.cf_valido(text) from public, anon;
grant execute on function public.cf_valido(text) to authenticated, service_role;

revoke all on function public.esercitazione_link(bigint) from public, anon;
grant execute on function public.esercitazione_link(bigint) to authenticated, service_role;

revoke all on function public.adesione_get(uuid)              from public;
revoke all on function public.adesione_salva(uuid, jsonb)     from public;
revoke all on function public.adesione_nessuna(uuid)          from public;
grant execute on function public.adesione_get(uuid)           to anon, authenticated, service_role;
grant execute on function public.adesione_salva(uuid, jsonb)  to anon, authenticated, service_role;
grant execute on function public.adesione_nessuna(uuid)       to anon, authenticated, service_role;

commit;

-- ---------------------------------------------------------------------
-- Annullamento (solo se serve tornare indietro, NON fa parte della migration):
--   begin;
--   drop function public.adesione_nessuna(uuid);
--   drop function public.adesione_salva(uuid, jsonb);
--   drop function public.adesione_get(uuid);
--   drop function public.esercitazione_link(bigint);
--   drop view public.v_adesioni_base;
--   drop table public.adesione_servizi, public.adesioni, public.esercitazione_sezioni,
--              public.esercitazione_servizi, public.esercitazioni,
--              public.esercitazioni_abilitazioni, public.esercitazioni_patenti, public.sezioni_ana;
--   drop function public.cf_valido(text);
--   commit;
-- ---------------------------------------------------------------------
