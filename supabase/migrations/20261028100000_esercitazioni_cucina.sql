-- =====================================================================
-- Esercitazioni – colazioni, ospiti, extra, esigenze alimentari, cucina
--   4) servizio 'colazione' (ordine nel giorno: colazione, pranzo, cena, pernotto)
--   5) esercitazione_ospiti (+ servizi) ed esercitazione_extra: solo admin "completo"
--   6) esigenze alimentari: lista configurabile + campo 'esigenze' per volontari e ospiti
--   7) esercitazione_cucina(): dati per la cucina (anche livello base), senza CF né cellulari
-- I punti 1 e 3 sono nella migration 20261027100000 (già applicata); il 2 (mail) è sospeso.
-- Da applicare in un'unica transazione.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 4. Colazione
-- ---------------------------------------------------------------------
alter table public.esercitazione_servizi drop constraint esercitazione_servizi_tipo_check;
alter table public.esercitazione_servizi
  add constraint esercitazione_servizi_tipo_check check (tipo in ('colazione','pranzo','cena','pernotto')),
  add constraint esercitazione_servizi_id_esercitazione_key unique (id, esercitazione_id); -- per le FK composte sotto

-- ---------------------------------------------------------------------
-- 6. Esigenze alimentari: lista configurabile (Impostazioni)
--    con_nota = la cucina vede nome e nota della persona (allergie, altro)
-- ---------------------------------------------------------------------
create table public.esercitazioni_esigenze (
  id          bigint generated always as identity primary key,
  nome        text not null unique check (length(trim(nome)) between 1 and 60),
  con_nota    boolean not null default false,
  ordine      integer not null default 0,
  created_at  timestamptz not null default now()
);
insert into public.esercitazioni_esigenze (nome, con_nota, ordine) values
  ('Vegetariano', false, 1),
  ('Celiaco',     false, 2),
  ('Allergie',    true,  3),
  ('Altro',       true,  4);

alter table public.adesioni
  add column esigenze      text[] not null default '{}',
  add column esigenze_note text check (esigenze_note is null or length(esigenze_note) <= 300);

-- campo configurabile 'esigenze' (come cellulare, patenti, …)
create or replace function public.campi_esercitazione_validi(p jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
        where e.key not in ('cellulare','patenti','abilitazioni','servizi','note','esigenze')
           or jsonb_typeof(e.value) <> 'string'
           or (e.value #>> '{}') not in ('non_richiesto','facoltativo','obbligatorio'));
$$;

alter table public.esercitazioni alter column campi set default
  '{"cellulare":"facoltativo","patenti":"facoltativo","abilitazioni":"facoltativo","servizi":"facoltativo","note":"non_richiesto","esigenze":"facoltativo"}'::jsonb;
-- esercitazioni già create: le esigenze partono "non richieste" (nessun cambiamento per chi sta compilando)
update public.esercitazioni set campi = campi || '{"esigenze":"non_richiesto"}'::jsonb where not (campi ? 'esigenze');

-- ---------------------------------------------------------------------
-- 5. Ospiti (con nome, senza CF) ed extra (solo conteggi) – gestiti dall'admin
-- ---------------------------------------------------------------------
create table public.esercitazione_ospiti (
  id                bigint generated always as identity primary key,
  esercitazione_id  bigint not null references public.esercitazioni(id) on delete cascade,
  nome              text not null check (length(trim(nome)) between 1 and 120),
  ente_ruolo        text check (ente_ruolo is null or length(ente_ruolo) <= 150),
  note              text check (note is null or length(note) <= 500),
  esigenze          text[] not null default '{}',
  esigenze_note     text check (esigenze_note is null or length(esigenze_note) <= 300),
  created_by        uuid references auth.users(id) default auth.uid(),
  created_at        timestamptz not null default now(),
  unique (id, esercitazione_id)
);
create index esercitazione_ospiti_es_idx on public.esercitazione_ospiti (esercitazione_id);

-- servizi dell'ospite: le FK composte garantiscono che ospite e servizio siano della stessa esercitazione
create table public.esercitazione_ospiti_servizi (
  ospite_id         bigint not null,
  servizio_id       bigint not null,
  esercitazione_id  bigint not null,
  primary key (ospite_id, servizio_id),
  foreign key (ospite_id, esercitazione_id)
    references public.esercitazione_ospiti(id, esercitazione_id) on delete cascade,
  foreign key (servizio_id, esercitazione_id)
    references public.esercitazione_servizi(id, esercitazione_id) on delete cascade
);
create index esercitazione_ospiti_servizi_srv_idx on public.esercitazione_ospiti_servizi (servizio_id);

create table public.esercitazione_extra (
  id                bigint generated always as identity primary key,
  esercitazione_id  bigint not null references public.esercitazioni(id) on delete cascade,
  servizio_id       bigint not null,
  quantita          integer not null check (quantita between 1 and 1000),
  descrizione       text not null check (length(trim(descrizione)) between 1 and 150),
  created_at        timestamptz not null default now(),
  foreign key (servizio_id, esercitazione_id)
    references public.esercitazione_servizi(id, esercitazione_id) on delete cascade
);
create index esercitazione_extra_srv_idx on public.esercitazione_extra (servizio_id);

-- audit come negli altri moduli (niente audit sulle righe di servizio degli ospiti)
create trigger trg_log_attivita after insert or update or delete on public.esercitazioni_esigenze
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazione_ospiti
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.esercitazione_extra
  for each row execute function public.fn_log_attivita();

-- RLS: esigenze leggibili da tutti gli autenticati; ospiti ed extra SOLO "completo" (come adesioni)
alter table public.esercitazioni_esigenze       enable row level security;
alter table public.esercitazione_ospiti         enable row level security;
alter table public.esercitazione_ospiti_servizi enable row level security;
alter table public.esercitazione_extra          enable row level security;

revoke all on public.esercitazioni_esigenze, public.esercitazione_ospiti,
              public.esercitazione_ospiti_servizi, public.esercitazione_extra
  from anon;

create policy "sezione: lettura" on public.esercitazioni_esigenze
  for select to authenticated using (true);
create policy "sezione: scrittura" on public.esercitazioni_esigenze
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

create policy "sezione: completo" on public.esercitazione_ospiti
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));
create policy "sezione: completo" on public.esercitazione_ospiti_servizi
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));
create policy "sezione: completo" on public.esercitazione_extra
  for all to authenticated using (public.ha_permesso('esercitazioni')) with check (public.ha_permesso('esercitazioni'));

-- ---------------------------------------------------------------------
-- 7. Cucina: per ogni servizio volontari + ospiti + extra, esigenze per tipo,
--    nomi (con Sezione o ente) solo per le esigenze "con nota" (allergie, altro).
--    Nessun CF, nessun cellulare. Accessibile con livello base o completo.
-- ---------------------------------------------------------------------
create function public.esercitazione_cucina(p_esercitazione_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.ha_accesso('esercitazioni') then
    raise exception 'Permesso negato.';
  end if;

  with persone as (
    select 'volontario'::text as tipo, (a.cognome || ' ' || a.nome) as nome, s.sezione as provenienza,
           a.esigenze, a.esigenze_note, x.servizio_id
      from public.adesioni a
      join public.esercitazione_sezioni s on s.id = a.esercitazione_sezione_id
      join public.adesione_servizi x on x.adesione_id = a.id
     where a.esercitazione_id = p_esercitazione_id
    union all
    select 'ospite', o.nome, o.ente_ruolo, o.esigenze, o.esigenze_note, y.servizio_id
      from public.esercitazione_ospiti o
      join public.esercitazione_ospiti_servizi y on y.ospite_id = o.id
     where o.esercitazione_id = p_esercitazione_id
  )
  select jsonb_build_object(
    'esigenze', (select coalesce(jsonb_agg(jsonb_build_object('nome', q.nome, 'con_nota', q.con_nota) order by q.ordine, q.nome), '[]'::jsonb)
                   from public.esercitazioni_esigenze q),
    'servizi', coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'giorno', s.giorno, 'tipo', s.tipo,
        'volontari', (select count(*) from persone p where p.servizio_id = s.id and p.tipo = 'volontario'),
        'ospiti',    (select count(*) from persone p where p.servizio_id = s.id and p.tipo = 'ospite'),
        'extra',     coalesce((select sum(e.quantita) from public.esercitazione_extra e where e.servizio_id = s.id), 0),
        'extra_dettaglio', coalesce((select jsonb_agg(jsonb_build_object('descrizione', e.descrizione, 'quantita', e.quantita) order by e.id)
                                       from public.esercitazione_extra e where e.servizio_id = s.id), '[]'::jsonb),
        'esigenze',  coalesce((select jsonb_object_agg(z.esig, z.n)
                                 from (select unnest(p.esigenze) as esig, count(*) as n
                                         from persone p where p.servizio_id = s.id group by 1) z), '{}'::jsonb),
        'con_nota',  coalesce((select jsonb_agg(jsonb_build_object('tipo', p.tipo, 'nome', p.nome, 'provenienza', p.provenienza,
                                                                   'esigenze', p.esigenze, 'nota', p.esigenze_note) order by p.nome)
                                 from persone p
                                where p.servizio_id = s.id
                                  and exists (select 1 from public.esercitazioni_esigenze q
                                               where q.con_nota and q.nome = any(p.esigenze))), '[]'::jsonb)
      ) order by s.giorno, array_position(array['colazione','pranzo','cena','pernotto'], s.tipo)), '[]'::jsonb)
  ) into v
  from public.esercitazione_servizi s
  where s.esercitazione_id = p_esercitazione_id;

  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- adesione_get: + colazione nell'ordine, lista esigenze, esigenze dei volontari
-- ---------------------------------------------------------------------
create or replace function public.adesione_get(p_token uuid)
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
      'referente', v_es.referente, 'stato', v_es.stato),
    'campi', v_es.campi,
    'sezione', v_sez.sezione,
    'stato_sezione', v_sez.stato,
    'risposto_at', v_sez.risposto_at,
    'modificabile', (v_es.stato = 'aperta'
                     and (v_es.chiusura_adesioni is null or now() <= v_es.chiusura_adesioni)),
    'servizi', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'giorno', s.giorno, 'tipo', s.tipo)
                                          order by s.giorno, array_position(array['colazione','pranzo','cena','pernotto'], s.tipo))
                         from public.esercitazione_servizi s where s.esercitazione_id = v_es.id), '[]'::jsonb),
    'patenti', coalesce((select jsonb_agg(nome order by ordine, nome) from public.esercitazioni_patenti), '[]'::jsonb),
    'abilitazioni', coalesce((select jsonb_agg(nome order by ordine, nome) from public.esercitazioni_abilitazioni), '[]'::jsonb),
    'esigenze', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'con_nota', con_nota) order by ordine, nome)
                          from public.esercitazioni_esigenze), '[]'::jsonb),
    'volontari', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'cognome', a.cognome, 'nome', a.nome, 'codice_fiscale', a.codice_fiscale,
                 'cellulare', a.cellulare, 'patenti', a.patenti, 'abilitazioni', a.abilitazioni,
                 'note', a.note, 'esigenze', a.esigenze, 'esigenze_note', a.esigenze_note,
                 'servizi', coalesce((select jsonb_agg(x.servizio_id) from public.adesione_servizi x
                                      where x.adesione_id = a.id), '[]'::jsonb))
               order by a.cognome, a.nome)
        from public.adesioni a where a.esercitazione_sezione_id = v_sez.id), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------
-- adesione_salva: + esigenze alimentari (campo 'esigenze')
--   valori ammessi = lista esercitazioni_esigenze; per le esigenze "con nota"
--   (allergie, altro) la nota è obbligatoria. 'obbligatorio' vale come
--   'facoltativo' (chi non ha esigenze non indica nulla).
--   Nessuna regola automatica su colazione/pernotto lato server.
-- ---------------------------------------------------------------------
create or replace function public.adesione_salva(p_token uuid, p_volontari jsonb)
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
  v_esist     public.adesioni%rowtype;
  l_cell      text;
  l_pat       text;
  l_abil      text;
  l_serv      text;
  l_note      text;
  l_esig      text;
  v           jsonb;
  v_cf        text;
  v_cognome   text;
  v_nome      text;
  v_cell      text;
  v_note      text;
  v_esig_note text;
  v_patenti   text[];
  v_abil      text[];
  v_esig      text[];
  v_servizi   bigint[];
  v_vol_id    bigint;
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

  l_cell := coalesce(v_es.campi->>'cellulare',    'facoltativo');
  l_pat  := coalesce(v_es.campi->>'patenti',      'facoltativo');
  l_abil := coalesce(v_es.campi->>'abilitazioni', 'facoltativo');
  l_serv := coalesce(v_es.campi->>'servizi',      'facoltativo');
  l_note := coalesce(v_es.campi->>'note',         'facoltativo');
  l_esig := coalesce(v_es.campi->>'esigenze',     'non_richiesto');

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
    if jsonb_typeof(v) <> 'object' then
      raise exception 'Volontario n. %: dati non validi.', n;
    end if;
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

    -- i campi multipli, se presenti, devono essere elenchi
    if (v ? 'patenti'      and jsonb_typeof(v->'patenti')      not in ('array','null'))
    or (v ? 'abilitazioni' and jsonb_typeof(v->'abilitazioni') not in ('array','null'))
    or (v ? 'servizi'      and jsonb_typeof(v->'servizi')      not in ('array','null'))
    or (v ? 'esigenze'     and jsonb_typeof(v->'esigenze')     not in ('array','null')) then
      raise exception 'Volontario n. %: dati non validi.', n;
    end if;

    -- cellulare
    if l_cell = 'obbligatorio' and trim(coalesce(v->>'cellulare', '')) = '' then
      raise exception 'Volontario n. % (% %): il cellulare è obbligatorio.', n, v_cognome, v_nome;
    end if;
    if l_cell <> 'non_richiesto' and length(coalesce(v->>'cellulare', '')) > 30 then
      raise exception 'Volontario n. %: numero di cellulare troppo lungo.', n;
    end if;
    -- note
    if l_note = 'obbligatorio' and trim(coalesce(v->>'note', '')) = '' then
      raise exception 'Volontario n. % (% %): le note sono obbligatorie.', n, v_cognome, v_nome;
    end if;
    if l_note <> 'non_richiesto' and length(coalesce(v->>'note', '')) > 500 then
      raise exception 'Volontario n. %: note troppo lunghe (max 500 caratteri).', n;
    end if;
    -- patenti
    if l_pat <> 'non_richiesto' then
      if l_pat = 'obbligatorio' and jsonb_array_length(coalesce(nullif(v->'patenti', 'null'::jsonb), '[]')) = 0 then
        raise exception 'Volontario n. % (% %): indica almeno una patente.', n, v_cognome, v_nome;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'patenti', 'null'::jsonb), '[]')) p(x)
                 where x not in (select nome from public.esercitazioni_patenti)) then
        raise exception 'Volontario n. %: patente non riconosciuta.', n;
      end if;
    end if;
    -- abilitazioni
    if l_abil <> 'non_richiesto' then
      if l_abil = 'obbligatorio' and jsonb_array_length(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) = 0 then
        raise exception 'Volontario n. % (% %): indica almeno un''abilitazione.', n, v_cognome, v_nome;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) p(x)
                 where x not in (select nome from public.esercitazioni_abilitazioni)) then
        raise exception 'Volontario n. %: abilitazione non riconosciuta.', n;
      end if;
    end if;
    -- servizi
    if l_serv <> 'non_richiesto' then
      if l_serv = 'obbligatorio' and jsonb_array_length(coalesce(nullif(v->'servizi', 'null'::jsonb), '[]')) = 0 then
        raise exception 'Volontario n. % (% %): indica almeno un pasto o pernotto.', n, v_cognome, v_nome;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'servizi', 'null'::jsonb), '[]')) p(x)
                 where case when x ~ '^[0-9]{1,18}$'
                            then x::bigint not in (select id from public.esercitazione_servizi
                                                   where esercitazione_id = v_es.id)
                            else true end) then
        raise exception 'Volontario n. %: servizio non valido per questa esercitazione.', n;
      end if;
    end if;
    -- esigenze alimentari
    if l_esig <> 'non_richiesto' then
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'esigenze', 'null'::jsonb), '[]')) p(x)
                 where x not in (select nome from public.esercitazioni_esigenze)) then
        raise exception 'Volontario n. %: esigenza alimentare non riconosciuta.', n;
      end if;
      if length(coalesce(v->>'esigenze_note', '')) > 300 then
        raise exception 'Volontario n. %: nota sulle esigenze alimentari troppo lunga (max 300 caratteri).', n;
      end if;
      if trim(coalesce(v->>'esigenze_note', '')) = ''
         and exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'esigenze', 'null'::jsonb), '[]')) p(x)
                      join public.esercitazioni_esigenze q on q.nome = x and q.con_nota) then
        raise exception 'Volontario n. % (% %): descrivi l''esigenza alimentare nella nota (es. a cosa è allergico).', n, v_cognome, v_nome;
      end if;
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

  -- 3) tolgo solo i volontari non più in elenco
  delete from public.adesioni
   where esercitazione_sezione_id = v_sez.id
     and codice_fiscale <> all(v_cf_visti);

  -- 4) inserimento / aggiornamento per CF
  for v in select * from jsonb_array_elements(p_volontari) loop
    v_cf        := upper(regexp_replace(coalesce(v->>'codice_fiscale', ''), '\s', '', 'g'));
    v_cognome   := upper(trim(v->>'cognome'));
    v_nome      := upper(trim(v->>'nome'));
    v_cell      := case when l_cell = 'non_richiesto' then null else nullif(trim(coalesce(v->>'cellulare', '')), '') end;
    v_note      := case when l_note = 'non_richiesto' then null else nullif(trim(coalesce(v->>'note', '')), '') end;
    v_esig_note := case when l_esig = 'non_richiesto' then null else nullif(trim(coalesce(v->>'esigenze_note', '')), '') end;
    v_patenti := '{}';
    v_abil    := '{}';
    v_esig    := '{}';
    v_servizi := '{}';
    if l_pat <> 'non_richiesto' then
      select coalesce(array_agg(distinct x order by x), '{}') into v_patenti
        from jsonb_array_elements_text(coalesce(nullif(v->'patenti', 'null'::jsonb), '[]')) p(x);
    end if;
    if l_abil <> 'non_richiesto' then
      select coalesce(array_agg(distinct x order by x), '{}') into v_abil
        from jsonb_array_elements_text(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) p(x);
    end if;
    if l_esig <> 'non_richiesto' then
      select coalesce(array_agg(distinct x order by x), '{}') into v_esig
        from jsonb_array_elements_text(coalesce(nullif(v->'esigenze', 'null'::jsonb), '[]')) p(x);
    end if;
    if l_serv <> 'non_richiesto' then
      select coalesce(array_agg(distinct x::bigint), '{}') into v_servizi
        from jsonb_array_elements_text(coalesce(nullif(v->'servizi', 'null'::jsonb), '[]')) p(x);
    end if;
    select vf.id into v_vol_id from public.volontari_formazione vf where vf.codice_fiscale = v_cf;

    select * into v_esist from public.adesioni
     where esercitazione_id = v_es.id and codice_fiscale = v_cf
     for update;

    if found then
      if v_esist.esercitazione_sezione_id <> v_sez.id then
        raise exception 'Il codice fiscale % risulta già iscritto da un''altra Sezione.', v_cf;
      end if;
      -- campi non richiesti: si conserva quanto già presente
      if l_cell = 'non_richiesto' then v_cell      := v_esist.cellulare;     end if;
      if l_note = 'non_richiesto' then v_note      := v_esist.note;          end if;
      if l_pat  = 'non_richiesto' then v_patenti   := v_esist.patenti;       end if;
      if l_abil = 'non_richiesto' then v_abil      := v_esist.abilitazioni;  end if;
      if l_esig = 'non_richiesto' then v_esig      := v_esist.esigenze;
                                       v_esig_note := v_esist.esigenze_note; end if;

      if (v_esist.volontario_id, v_esist.cognome, v_esist.nome, v_esist.cellulare,
          v_esist.patenti, v_esist.abilitazioni, v_esist.note, v_esist.esigenze, v_esist.esigenze_note)
         is distinct from
         (v_vol_id, v_cognome, v_nome, v_cell, v_patenti, v_abil, v_note, v_esig, v_esig_note) then
        update public.adesioni
           set volontario_id = v_vol_id, cognome = v_cognome, nome = v_nome, cellulare = v_cell,
               patenti = v_patenti, abilitazioni = v_abil, note = v_note,
               esigenze = v_esig, esigenze_note = v_esig_note
         where id = v_esist.id;
      end if;
      v_id := v_esist.id;
    else
      begin
        insert into public.adesioni (esercitazione_id, esercitazione_sezione_id, volontario_id,
                                     cognome, nome, codice_fiscale, cellulare, patenti, abilitazioni, note,
                                     esigenze, esigenze_note)
        values (v_es.id, v_sez.id, v_vol_id, v_cognome, v_nome, v_cf, v_cell, v_patenti, v_abil, v_note,
                v_esig, v_esig_note)
        returning id into v_id;
      exception when unique_violation then
        raise exception 'Il codice fiscale % risulta già iscritto da un''altra Sezione.', v_cf;
      end;
    end if;

    -- servizi: solo le differenze (se il campo non è richiesto non si toccano)
    if l_serv <> 'non_richiesto' then
      delete from public.adesione_servizi
       where adesione_id = v_id
         and servizio_id <> all(v_servizi);
      insert into public.adesione_servizi (adesione_id, servizio_id)
      select v_id, unnest(v_servizi)
      on conflict (adesione_id, servizio_id) do nothing;
    end if;
  end loop;

  update public.esercitazione_sezioni
     set stato = 'risposto', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true, 'volontari', jsonb_array_length(p_volontari));
end;
$$;

-- ---------------------------------------------------------------------
-- Privilegi (le funzioni nuove sarebbero eseguibili da anon per default)
-- ---------------------------------------------------------------------
revoke all on function public.esercitazione_cucina(bigint) from public, anon;
grant execute on function public.esercitazione_cucina(bigint) to authenticated, service_role;

revoke all on function public.campi_esercitazione_validi(jsonb) from public, anon;
grant execute on function public.campi_esercitazione_validi(jsonb) to authenticated, service_role;

revoke all on function public.adesione_get(uuid)          from public;
revoke all on function public.adesione_salva(uuid, jsonb) from public;
grant execute on function public.adesione_get(uuid)          to anon, authenticated, service_role;
grant execute on function public.adesione_salva(uuid, jsonb) to anon, authenticated, service_role;

commit;

-- ---------------------------------------------------------------------
-- Annullamento (solo se serve tornare indietro, NON fa parte della migration):
--   ripristinare adesione_get / adesione_salva / campi_esercitazione_validi dalla migration 20261027100000, poi:
--   drop function public.esercitazione_cucina(bigint);
--   drop table public.esercitazione_extra, public.esercitazione_ospiti_servizi,
--              public.esercitazione_ospiti, public.esercitazioni_esigenze;
--   alter table public.adesioni drop column esigenze_note, drop column esigenze;
--   delete from public.esercitazione_servizi where tipo = 'colazione';
--   alter table public.esercitazione_servizi drop constraint esercitazione_servizi_id_esercitazione_key,
--     drop constraint esercitazione_servizi_tipo_check,
--     add constraint esercitazione_servizi_tipo_check check (tipo in ('pranzo','cena','pernotto'));
-- ---------------------------------------------------------------------
