-- =====================================================================
-- Motore unico ATTIVAZIONI (esercitazioni + emergenze) – passo A
-- Rinomina e generalizza lo schema delle esercitazioni SENZA cambiare il
-- comportamento: le esercitazioni continuano a funzionare come prima.
--   - esercitazioni → attivazioni, con tipo ('esercitazione' | 'emergenza')
--   - data_fine facoltativa per le emergenze + fine_finestra (estendibile)
--   - tabelle figlie esercitazione_* → attivazione_*, liste esercitazioni_* → attivazioni_*
--   - colonne esercitazione_id → attivazione_id (esercitazione_sezione_id → attivazione_sezione_id)
--   - permessi separati per tipo: 'esercitazioni' / 'emergenze'
--     (funzioni permesso_tipo, attivazione_accesso, attivazione_permesso)
--   - RPC, vista e funzioni ricreate con i nomi nuovi
--     (esercitazione_link → attivazione_link, esercitazione_cucina → attivazione_cucina)
-- I dati dell'emergenza (tipologia, art. 39, disponibilità con orari, mezzi,
-- materiali) arrivano nel passo B.
-- Da applicare in un'unica transazione, subito seguita dal push del codice.
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Tabelle e colonne
-- ---------------------------------------------------------------------
alter table public.esercitazioni                rename to attivazioni;
alter table public.esercitazione_servizi        rename to attivazione_servizi;
alter table public.esercitazione_sezioni        rename to attivazione_sezioni;
alter table public.esercitazione_ospiti         rename to attivazione_ospiti;
alter table public.esercitazione_ospiti_servizi rename to attivazione_ospiti_servizi;
alter table public.esercitazione_extra          rename to attivazione_extra;
alter table public.esercitazioni_patenti        rename to attivazioni_patenti;
alter table public.esercitazioni_abilitazioni   rename to attivazioni_abilitazioni;
alter table public.esercitazioni_esigenze       rename to attivazioni_esigenze;

alter table public.attivazione_servizi        rename column esercitazione_id to attivazione_id;
alter table public.attivazione_sezioni        rename column esercitazione_id to attivazione_id;
alter table public.adesioni                   rename column esercitazione_id to attivazione_id;
alter table public.adesioni                   rename column esercitazione_sezione_id to attivazione_sezione_id;
alter table public.attivazione_ospiti         rename column esercitazione_id to attivazione_id;
alter table public.attivazione_ospiti_servizi rename column esercitazione_id to attivazione_id;
alter table public.attivazione_extra          rename column esercitazione_id to attivazione_id;

-- tipo, data fine facoltativa (emergenze), finestra di date estendibile
alter table public.attivazioni
  add column tipo text not null default 'esercitazione' check (tipo in ('esercitazione','emergenza')),
  add column fine_finestra date,
  alter column data_fine drop not null,
  drop constraint esercitazioni_date_check,
  add constraint attivazioni_date_check check (
        (data_fine is null or data_fine >= data_inizio)
    and (fine_finestra is null or fine_finestra >= data_inizio)
    and (tipo = 'emergenza' or data_fine is not null)          -- un'esercitazione ha sempre la data fine
    and (data_fine is not null or fine_finestra is not null)); -- un'emergenza aperta ha almeno la finestra

alter function public.campi_esercitazione_validi(jsonb) rename to campi_attivazione_validi;

-- ---------------------------------------------------------------------
-- 2. Permessi per tipo
-- ---------------------------------------------------------------------
create function public.permesso_tipo(p_tipo text)
returns text
language sql
immutable
set search_path = public
as $$
  select case p_tipo when 'emergenza' then 'emergenze' else 'esercitazioni' end;
$$;

-- lettura (base o completo) dell'attivazione indicata, secondo il suo tipo
create function public.attivazione_accesso(p_attivazione_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select public.ha_accesso(public.permesso_tipo(a.tipo)) from public.attivazioni a where a.id = p_attivazione_id), false);
$$;

-- gestione (completo) dell'attivazione indicata, secondo il suo tipo
create function public.attivazione_permesso(p_attivazione_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select public.ha_permesso(public.permesso_tipo(a.tipo)) from public.attivazioni a where a.id = p_attivazione_id), false);
$$;

-- gestione delle liste condivise (patenti, abilitazioni, esigenze, mail Sezioni)
create function public.gestisce_attivazioni()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.ha_permesso('esercitazioni') or public.ha_permesso('emergenze');
$$;

-- ---------------------------------------------------------------------
-- 3. RLS: tolgo le policy precedenti e le ricreo per tipo
-- ---------------------------------------------------------------------
do $$
declare p record;
begin
  for p in select tablename, policyname from pg_policies
            where schemaname = 'public'
              and tablename in ('attivazioni','attivazione_servizi','attivazione_sezioni','adesioni','adesione_servizi',
                                'attivazione_ospiti','attivazione_ospiti_servizi','attivazione_extra',
                                'attivazioni_patenti','attivazioni_abilitazioni','attivazioni_esigenze','sezioni_ana')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- attivazioni: lettura/scrittura secondo il permesso del suo tipo
create policy "attivazioni: lettura" on public.attivazioni
  for select to authenticated using (public.ha_accesso(public.permesso_tipo(tipo)));
create policy "attivazioni: scrittura" on public.attivazioni
  for all to authenticated
  using (public.ha_permesso(public.permesso_tipo(tipo)))
  with check (public.ha_permesso(public.permesso_tipo(tipo)));

-- figlie con attivazione_id: lettura base/completo, scrittura completo
create policy "attivazioni: lettura" on public.attivazione_servizi
  for select to authenticated using (public.attivazione_accesso(attivazione_id));
create policy "attivazioni: scrittura" on public.attivazione_servizi
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));

create policy "attivazioni: lettura" on public.attivazione_sezioni
  for select to authenticated using (public.attivazione_accesso(attivazione_id));
create policy "attivazioni: scrittura" on public.attivazione_sezioni
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));

-- dati personali e ospiti/extra: solo completo
create policy "attivazioni: completo" on public.adesioni
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));
create policy "attivazioni: completo" on public.adesione_servizi
  for all to authenticated
  using (exists (select 1 from public.adesioni a where a.id = adesione_id and public.attivazione_permesso(a.attivazione_id)))
  with check (exists (select 1 from public.adesioni a where a.id = adesione_id and public.attivazione_permesso(a.attivazione_id)));
create policy "attivazioni: completo" on public.attivazione_ospiti
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));
create policy "attivazioni: completo" on public.attivazione_ospiti_servizi
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));
create policy "attivazioni: completo" on public.attivazione_extra
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));

-- liste e Sezioni: lettura per tutti gli autenticati, gestione con uno dei due permessi
create policy "liste: lettura" on public.attivazioni_patenti     for select to authenticated using (true);
create policy "liste: scrittura" on public.attivazioni_patenti   for all to authenticated using (public.gestisce_attivazioni()) with check (public.gestisce_attivazioni());
create policy "liste: lettura" on public.attivazioni_abilitazioni   for select to authenticated using (true);
create policy "liste: scrittura" on public.attivazioni_abilitazioni for all to authenticated using (public.gestisce_attivazioni()) with check (public.gestisce_attivazioni());
create policy "liste: lettura" on public.attivazioni_esigenze    for select to authenticated using (true);
create policy "liste: scrittura" on public.attivazioni_esigenze  for all to authenticated using (public.gestisce_attivazioni()) with check (public.gestisce_attivazioni());
create policy "sezioni_ana: lettura" on public.sezioni_ana       for select to authenticated using (true);
create policy "sezioni_ana: scrittura" on public.sezioni_ana     for all to authenticated using (public.gestisce_attivazioni()) with check (public.gestisce_attivazioni());

-- ---------------------------------------------------------------------
-- 4. Vista per il livello base (senza CF, cellulare, note)
-- ---------------------------------------------------------------------
drop view public.v_adesioni_base;
create view public.v_adesioni_base
with (security_barrier = true)
as
select a.id,
       a.attivazione_id,
       a.attivazione_sezione_id,
       s.sezione,
       a.cognome,
       a.nome,
       a.patenti,
       a.abilitazioni,
       a.created_at,
       coalesce((select array_agg(x.servizio_id order by x.servizio_id)
                 from public.adesione_servizi x where x.adesione_id = a.id), '{}') as servizi
from public.adesioni a
join public.attivazione_sezioni s on s.id = a.attivazione_sezione_id
where public.attivazione_accesso(a.attivazione_id);

revoke all on public.v_adesioni_base from public;
revoke all on public.v_adesioni_base from anon;
revoke all on public.v_adesioni_base from authenticated;
grant select on public.v_adesioni_base to authenticated;

-- ---------------------------------------------------------------------
-- 5. Funzioni ricreate con i nomi nuovi
-- ---------------------------------------------------------------------
drop function public.esercitazione_link(bigint);
drop function public.esercitazione_cucina(bigint);

CREATE OR REPLACE FUNCTION public.adesione_get(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sez  public.attivazione_sezioni%rowtype;
  v_es   public.attivazioni%rowtype;
begin
  select * into v_sez from public.attivazione_sezioni where token = p_token;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.attivazioni where id = v_sez.attivazione_id;
  if v_es.stato = 'bozza' then
    raise exception 'Le adesioni per questo evento non sono ancora aperte.';
  end if;

  return jsonb_build_object(
    'attivazione', jsonb_build_object(
      'tipo', v_es.tipo, 'fine_finestra', v_es.fine_finestra,
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
                         from public.attivazione_servizi s where s.attivazione_id = v_es.id), '[]'::jsonb),
    'patenti', coalesce((select jsonb_agg(nome order by ordine, nome) from public.attivazioni_patenti), '[]'::jsonb),
    'abilitazioni', coalesce((select jsonb_agg(nome order by ordine, nome) from public.attivazioni_abilitazioni), '[]'::jsonb),
    'esigenze', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'con_nota', con_nota) order by ordine, nome)
                          from public.attivazioni_esigenze), '[]'::jsonb),
    'volontari', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'cognome', a.cognome, 'nome', a.nome, 'codice_fiscale', a.codice_fiscale,
                 'cellulare', a.cellulare, 'patenti', a.patenti, 'abilitazioni', a.abilitazioni,
                 'note', a.note, 'esigenze', a.esigenze, 'esigenze_note', a.esigenze_note,
                 'servizi', coalesce((select jsonb_agg(x.servizio_id) from public.adesione_servizi x
                                      where x.adesione_id = a.id), '[]'::jsonb))
               order by a.cognome, a.nome)
        from public.adesioni a where a.attivazione_sezione_id = v_sez.id), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.adesione_salva(p_token uuid, p_volontari jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_max_volontari constant int := 150;
  v_sez       public.attivazione_sezioni%rowtype;
  v_es        public.attivazioni%rowtype;
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
  select * into v_sez from public.attivazione_sezioni where token = p_token for update;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.attivazioni where id = v_sez.attivazione_id;
  if v_es.stato <> 'aperta' or (v_es.chiusura_adesioni is not null and now() > v_es.chiusura_adesioni) then
    raise exception 'Le adesioni per questo evento sono chiuse.';
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
                 where x not in (select nome from public.attivazioni_patenti)) then
        raise exception 'Volontario n. %: patente non riconosciuta.', n;
      end if;
    end if;
    -- abilitazioni
    if l_abil <> 'non_richiesto' then
      if l_abil = 'obbligatorio' and jsonb_array_length(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) = 0 then
        raise exception 'Volontario n. % (% %): indica almeno un''abilitazione.', n, v_cognome, v_nome;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'abilitazioni', 'null'::jsonb), '[]')) p(x)
                 where x not in (select nome from public.attivazioni_abilitazioni)) then
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
                            then x::bigint not in (select id from public.attivazione_servizi
                                                   where attivazione_id = v_es.id)
                            else true end) then
        raise exception 'Volontario n. %: servizio non valido per questo evento.', n;
      end if;
    end if;
    -- esigenze alimentari
    if l_esig <> 'non_richiesto' then
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'esigenze', 'null'::jsonb), '[]')) p(x)
                 where x not in (select nome from public.attivazioni_esigenze)) then
        raise exception 'Volontario n. %: esigenza alimentare non riconosciuta.', n;
      end if;
      if length(coalesce(v->>'esigenze_note', '')) > 300 then
        raise exception 'Volontario n. %: nota sulle esigenze alimentari troppo lunga (max 300 caratteri).', n;
      end if;
      if trim(coalesce(v->>'esigenze_note', '')) = ''
         and exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'esigenze', 'null'::jsonb), '[]')) p(x)
                      join public.attivazioni_esigenze q on q.nome = x and q.con_nota) then
        raise exception 'Volontario n. % (% %): descrivi l''esigenza alimentare nella nota (es. a cosa è allergico).', n, v_cognome, v_nome;
      end if;
    end if;
  end loop;

  -- 2) CF già iscritti da un'ALTRA Sezione della stessa esercitazione
  select string_agg(a.codice_fiscale, ', ' order by a.codice_fiscale) into v_doppi
  from public.adesioni a
  where a.attivazione_id = v_es.id
    and a.attivazione_sezione_id <> v_sez.id
    and a.codice_fiscale = any(v_cf_visti);
  if v_doppi is not null then
    raise exception 'Questi codici fiscali risultano già iscritti da un''altra Sezione: %', v_doppi;
  end if;

  -- 3) tolgo solo i volontari non più in elenco
  delete from public.adesioni
   where attivazione_sezione_id = v_sez.id
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
     where attivazione_id = v_es.id and codice_fiscale = v_cf
     for update;

    if found then
      if v_esist.attivazione_sezione_id <> v_sez.id then
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
        insert into public.adesioni (attivazione_id, attivazione_sezione_id, volontario_id,
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

  update public.attivazione_sezioni
     set stato = 'risposto', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true, 'volontari', jsonb_array_length(p_volontari));
end;
$function$;

CREATE OR REPLACE FUNCTION public.adesione_nessuna(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sez public.attivazione_sezioni%rowtype;
  v_es  public.attivazioni%rowtype;
begin
  select * into v_sez from public.attivazione_sezioni where token = p_token for update;
  if not found then
    raise exception 'Link non valido o scaduto.';
  end if;
  select * into v_es from public.attivazioni where id = v_sez.attivazione_id;
  if v_es.stato <> 'aperta' or (v_es.chiusura_adesioni is not null and now() > v_es.chiusura_adesioni) then
    raise exception 'Le adesioni per questo evento sono chiuse.';
  end if;

  delete from public.adesioni where attivazione_sezione_id = v_sez.id;
  update public.attivazione_sezioni
     set stato = 'non_partecipa', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.attivazione_link(p_attivazione_id bigint)
 RETURNS TABLE(attivazione_sezione_id bigint, sezione text, token uuid, email_pc text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.attivazione_permesso(p_attivazione_id) then
    raise exception 'Permesso negato.';
  end if;
  return query
    select s.id, s.sezione, s.token, z.email_pc
      from public.attivazione_sezioni s
      join public.sezioni_ana z on z.nome = s.sezione
     where s.attivazione_id = p_attivazione_id
     order by z.ordine, s.sezione;
end;
$function$;

CREATE OR REPLACE FUNCTION public.attivazione_cucina(p_attivazione_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v jsonb;
begin
  if not public.attivazione_accesso(p_attivazione_id) then
    raise exception 'Permesso negato.';
  end if;

  with persone as (
    select 'volontario'::text as tipo, (a.cognome || ' ' || a.nome) as nome, s.sezione as provenienza,
           a.esigenze, a.esigenze_note, x.servizio_id
      from public.adesioni a
      join public.attivazione_sezioni s on s.id = a.attivazione_sezione_id
      join public.adesione_servizi x on x.adesione_id = a.id
     where a.attivazione_id = p_attivazione_id
    union all
    select 'ospite', o.nome, o.ente_ruolo, o.esigenze, o.esigenze_note, y.servizio_id
      from public.attivazione_ospiti o
      join public.attivazione_ospiti_servizi y on y.ospite_id = o.id
     where o.attivazione_id = p_attivazione_id
  )
  select jsonb_build_object(
    'esigenze', (select coalesce(jsonb_agg(jsonb_build_object('nome', q.nome, 'con_nota', q.con_nota) order by q.ordine, q.nome), '[]'::jsonb)
                   from public.attivazioni_esigenze q),
    'servizi', coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'giorno', s.giorno, 'tipo', s.tipo,
        'volontari', (select count(*) from persone p where p.servizio_id = s.id and p.tipo = 'volontario'),
        'ospiti',    (select count(*) from persone p where p.servizio_id = s.id and p.tipo = 'ospite'),
        'extra',     coalesce((select sum(e.quantita) from public.attivazione_extra e where e.servizio_id = s.id), 0),
        'extra_dettaglio', coalesce((select jsonb_agg(jsonb_build_object('descrizione', e.descrizione, 'quantita', e.quantita) order by e.id)
                                       from public.attivazione_extra e where e.servizio_id = s.id), '[]'::jsonb),
        'esigenze',  coalesce((select jsonb_object_agg(z.esig, z.n)
                                 from (select unnest(p.esigenze) as esig, count(*) as n
                                         from persone p where p.servizio_id = s.id group by 1) z), '{}'::jsonb),
        'con_nota',  coalesce((select jsonb_agg(jsonb_build_object('tipo', p.tipo, 'nome', p.nome, 'provenienza', p.provenienza,
                                                                   'esigenze', p.esigenze, 'nota', p.esigenze_note) order by p.nome)
                                 from persone p
                                where p.servizio_id = s.id
                                  and exists (select 1 from public.attivazioni_esigenze q
                                               where q.con_nota and q.nome = any(p.esigenze))), '[]'::jsonb)
      ) order by s.giorno, array_position(array['colazione','pranzo','cena','pernotto'], s.tipo)), '[]'::jsonb)
  ) into v
  from public.attivazione_servizi s
  where s.attivazione_id = p_attivazione_id;

  return v;
end;
$function$;

-- ---------------------------------------------------------------------
-- 6. Privilegi (le funzioni nuove sarebbero eseguibili da anon per default)
-- ---------------------------------------------------------------------
revoke all on function public.permesso_tipo(text)               from public, anon;
revoke all on function public.attivazione_accesso(bigint)       from public, anon;
revoke all on function public.attivazione_permesso(bigint)      from public, anon;
revoke all on function public.gestisce_attivazioni()            from public, anon;
revoke all on function public.attivazione_link(bigint)          from public, anon;
revoke all on function public.attivazione_cucina(bigint)        from public, anon;
revoke all on function public.campi_attivazione_validi(jsonb)   from public, anon;
grant execute on function public.permesso_tipo(text)             to authenticated, service_role;
grant execute on function public.attivazione_accesso(bigint)     to authenticated, service_role;
grant execute on function public.attivazione_permesso(bigint)    to authenticated, service_role;
grant execute on function public.gestisce_attivazioni()          to authenticated, service_role;
grant execute on function public.attivazione_link(bigint)        to authenticated, service_role;
grant execute on function public.attivazione_cucina(bigint)      to authenticated, service_role;
grant execute on function public.campi_attivazione_validi(jsonb) to authenticated, service_role;

revoke all on function public.adesione_get(uuid)          from public;
revoke all on function public.adesione_salva(uuid, jsonb) from public;
revoke all on function public.adesione_nessuna(uuid)      from public;
grant execute on function public.adesione_get(uuid)          to anon, authenticated, service_role;
grant execute on function public.adesione_salva(uuid, jsonb) to anon, authenticated, service_role;
grant execute on function public.adesione_nessuna(uuid)      to anon, authenticated, service_role;

commit;

-- ---------------------------------------------------------------------
-- Annullamento: non previsto come script automatico (rinomine inverse +
-- funzioni delle migration 20261026/27/28). In caso di problemi si ripristina
-- da backup Supabase o si scrive una migration correttiva.
-- ---------------------------------------------------------------------
