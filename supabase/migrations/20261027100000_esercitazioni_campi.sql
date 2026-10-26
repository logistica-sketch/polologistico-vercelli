-- =====================================================================
-- Esercitazioni – campi configurabili e referente
--   1) esercitazioni.campi (jsonb): per cellulare, patenti, abilitazioni,
--      servizi, note → 'non_richiesto' | 'facoltativo' | 'obbligatorio'.
--      Cognome, nome e CF restano SEMPRE obbligatori.
--   2) esercitazioni.referente: contatto mostrato nella mail e nella pagina pubblica.
--   3) adesione_get restituisce campi e referente; adesione_salva fa
--      rispettare i campi lato server.
-- Da applicare in un'unica transazione.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Campi configurabili
-- ---------------------------------------------------------------------
create function public.campi_esercitazione_validi(p jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
        where e.key not in ('cellulare','patenti','abilitazioni','servizi','note')
           or jsonb_typeof(e.value) <> 'string'
           or (e.value #>> '{}') not in ('non_richiesto','facoltativo','obbligatorio'));
$$;

alter table public.esercitazioni
  add column campi jsonb not null
    default '{"cellulare":"facoltativo","patenti":"facoltativo","abilitazioni":"facoltativo","servizi":"facoltativo","note":"non_richiesto"}'::jsonb,
  add constraint esercitazioni_campi_check check (public.campi_esercitazione_validi(campi));

-- ---------------------------------------------------------------------
-- 2. Referente / contatto
-- ---------------------------------------------------------------------
alter table public.esercitazioni
  add column referente text check (referente is null or length(referente) <= 300);

-- ---------------------------------------------------------------------
-- 3. adesione_get: + campi, referente
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

-- ---------------------------------------------------------------------
-- 4. adesione_salva: rispetta i campi dell'esercitazione
--    obbligatorio  → vuoto = errore
--    facoltativo   → salvato com'è
--    non_richiesto → ignorato: in inserimento resta vuoto, in modifica si
--                    conserva il valore già presente (es. note scritte dal Polo)
--    Upsert per CF dentro la Sezione: id delle adesioni invariati.
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
  v           jsonb;
  v_cf        text;
  v_cognome   text;
  v_nome      text;
  v_cell      text;
  v_note      text;
  v_patenti   text[];
  v_abil      text[];
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
    or (v ? 'servizi'      and jsonb_typeof(v->'servizi')      not in ('array','null')) then
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
    v_cf      := upper(regexp_replace(coalesce(v->>'codice_fiscale', ''), '\s', '', 'g'));
    v_cognome := upper(trim(v->>'cognome'));
    v_nome    := upper(trim(v->>'nome'));
    v_cell    := case when l_cell = 'non_richiesto' then null else nullif(trim(coalesce(v->>'cellulare', '')), '') end;
    v_note    := case when l_note = 'non_richiesto' then null else nullif(trim(coalesce(v->>'note', '')), '') end;
    v_patenti := '{}';
    v_abil    := '{}';
    v_servizi := '{}';
    if l_pat <> 'non_richiesto' then
      select coalesce(array_agg(distinct x order by x), '{}') into v_patenti
        from jsonb_array_elements_text(coalesce(nullif(v->'patenti', 'null'::jsonb), '[]')) p(x);
    end if;
    if l_abil <> 'non_richiesto' then
      select coalesce(array_agg(distinct x order by x), '{}') into v_abil
        from jsonb_array_elements_text(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) p(x);
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
      if l_cell = 'non_richiesto' then v_cell    := v_esist.cellulare;    end if;
      if l_note = 'non_richiesto' then v_note    := v_esist.note;         end if;
      if l_pat  = 'non_richiesto' then v_patenti := v_esist.patenti;      end if;
      if l_abil = 'non_richiesto' then v_abil    := v_esist.abilitazioni; end if;

      if (v_esist.volontario_id, v_esist.cognome, v_esist.nome, v_esist.cellulare,
          v_esist.patenti, v_esist.abilitazioni, v_esist.note)
         is distinct from
         (v_vol_id, v_cognome, v_nome, v_cell, v_patenti, v_abil, v_note) then
        update public.adesioni
           set volontario_id = v_vol_id, cognome = v_cognome, nome = v_nome, cellulare = v_cell,
               patenti = v_patenti, abilitazioni = v_abil, note = v_note
         where id = v_esist.id;
      end if;
      v_id := v_esist.id;
    else
      begin
        insert into public.adesioni (esercitazione_id, esercitazione_sezione_id, volontario_id,
                                     cognome, nome, codice_fiscale, cellulare, patenti, abilitazioni, note)
        values (v_es.id, v_sez.id, v_vol_id, v_cognome, v_nome, v_cf, v_cell, v_patenti, v_abil, v_note)
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
-- 5. Privilegi (le funzioni nuove sarebbero eseguibili da anon per default)
-- ---------------------------------------------------------------------
revoke all on function public.campi_esercitazione_validi(jsonb) from public, anon;
grant execute on function public.campi_esercitazione_validi(jsonb) to authenticated, service_role;

-- create or replace mantiene i grant esistenti, li ribadisco per chiarezza
revoke all on function public.adesione_get(uuid)          from public;
revoke all on function public.adesione_salva(uuid, jsonb) from public;
grant execute on function public.adesione_get(uuid)          to anon, authenticated, service_role;
grant execute on function public.adesione_salva(uuid, jsonb) to anon, authenticated, service_role;

commit;

-- ---------------------------------------------------------------------
-- Annullamento (solo se serve tornare indietro, NON fa parte della migration):
--   ripristinare adesione_get / adesione_salva dalla migration 20261026120000, poi:
--   alter table public.esercitazioni drop column referente, drop column campi;
--   drop function public.campi_esercitazione_validi(jsonb);
-- ---------------------------------------------------------------------
