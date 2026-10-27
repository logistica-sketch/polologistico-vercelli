-- =====================================================================
-- Motore unico ATTIVAZIONI – passo B: dati delle emergenze
--   - lista attivazioni_tipologie (GENERICO, CAPOSQUADRA, COORDINATORE)
--     + adesioni.tipologia
--   - adesioni.art39: la Sezione segnala che il volontario chiede i benefici
--     dell'art. 39 (i dati del datore di lavoro li gestisce la Sezione:
--     qui solo il flag). Visibile solo a "completo": non entra nella vista
--     base né nelle RPC di riepilogo.
--   - servizio 'disponibile' (giornata di disponibilità) con orari
--     facoltativi su adesione_servizi (ora_dalle / ora_alle; vuoti = giornata intera)
--   - mezzi e materiali messi a disposizione dalle Sezioni
--     (attivazione_mezzi, attivazione_materiali; niente legame col Libro Matricola)
--   - campi configurabili nuovi: tipologia, art39, orari, mezzi, materiali
--     (se assenti valgono 'non_richiesto': le esercitazioni non cambiano)
--   - adesione_salva accetta anche { volontari, mezzi, materiali }
--     (l'elenco semplice di volontari continua a funzionare)
--   - RPC attivazione_giorni(id): riepilogo per giorno, leggibile anche da "base"
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 1. Tipologia e art. 39
-- ---------------------------------------------------------------------
create table public.attivazioni_tipologie (
  id          bigint generated always as identity primary key,
  nome        text not null unique check (length(trim(nome)) between 1 and 60),
  ordine      integer not null default 0,
  created_at  timestamptz not null default now()
);
insert into public.attivazioni_tipologie (nome, ordine) values
  ('GENERICO',     1),
  ('CAPOSQUADRA',  2),
  ('COORDINATORE', 3);

alter table public.adesioni
  add column tipologia text references public.attivazioni_tipologie(nome) on update cascade on delete set null,
  add column art39 boolean not null default false;

-- ---------------------------------------------------------------------
-- 2. Giornate di disponibilità con orari facoltativi
-- ---------------------------------------------------------------------
alter table public.attivazione_servizi
  drop constraint esercitazione_servizi_tipo_check,
  add constraint attivazione_servizi_tipo_check
    check (tipo in ('disponibile','colazione','pranzo','cena','pernotto'));

alter table public.adesione_servizi
  add column ora_dalle time,
  add column ora_alle  time,
  add constraint adesione_servizi_orari_check
    check ((ora_dalle is null) = (ora_alle is null) and (ora_dalle is null or ora_dalle <> ora_alle));

-- ---------------------------------------------------------------------
-- 3. Mezzi e materiali delle Sezioni
-- ---------------------------------------------------------------------
create table public.attivazione_mezzi (
  id                      bigint generated always as identity primary key,
  attivazione_id          bigint not null references public.attivazioni(id) on delete cascade,
  attivazione_sezione_id  bigint not null,
  tipo                    text not null check (length(trim(tipo)) between 1 and 80),
  targa                   text check (targa is null or length(targa) <= 15),
  giorni                  date[] not null default '{}',
  note                    text check (note is null or length(note) <= 300),
  created_at              timestamptz not null default now(),
  foreign key (attivazione_sezione_id, attivazione_id)
    references public.attivazione_sezioni(id, attivazione_id) on delete cascade
);
create index attivazione_mezzi_sezione_idx on public.attivazione_mezzi (attivazione_sezione_id);
create index attivazione_mezzi_attivazione_idx on public.attivazione_mezzi (attivazione_id);

create table public.attivazione_materiali (
  id                      bigint generated always as identity primary key,
  attivazione_id          bigint not null references public.attivazioni(id) on delete cascade,
  attivazione_sezione_id  bigint not null,
  quantita                integer not null check (quantita between 1 and 10000),
  descrizione             text not null check (length(trim(descrizione)) between 1 and 150),
  note                    text check (note is null or length(note) <= 300),
  created_at              timestamptz not null default now(),
  foreign key (attivazione_sezione_id, attivazione_id)
    references public.attivazione_sezioni(id, attivazione_id) on delete cascade
);
create index attivazione_materiali_sezione_idx on public.attivazione_materiali (attivazione_sezione_id);
create index attivazione_materiali_attivazione_idx on public.attivazione_materiali (attivazione_id);

-- audit come negli altri moduli
create trigger trg_log_attivita after insert or update or delete on public.attivazioni_tipologie
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.attivazione_mezzi
  for each row execute function public.fn_log_attivita();
create trigger trg_log_attivita after insert or update or delete on public.attivazione_materiali
  for each row execute function public.fn_log_attivita();

-- RLS: tipologie come le altre liste; mezzi e materiali (nessun dato personale)
-- leggibili anche da "base", modificabili solo da "completo"
alter table public.attivazioni_tipologie enable row level security;
alter table public.attivazione_mezzi     enable row level security;
alter table public.attivazione_materiali enable row level security;

create policy "liste: lettura" on public.attivazioni_tipologie   for select to authenticated using (true);
create policy "liste: scrittura" on public.attivazioni_tipologie for all to authenticated using (public.gestisce_attivazioni()) with check (public.gestisce_attivazioni());

create policy "attivazioni: lettura" on public.attivazione_mezzi
  for select to authenticated using (public.attivazione_accesso(attivazione_id));
create policy "attivazioni: scrittura" on public.attivazione_mezzi
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));
create policy "attivazioni: lettura" on public.attivazione_materiali
  for select to authenticated using (public.attivazione_accesso(attivazione_id));
create policy "attivazioni: scrittura" on public.attivazione_materiali
  for all to authenticated using (public.attivazione_permesso(attivazione_id)) with check (public.attivazione_permesso(attivazione_id));

revoke all on public.attivazioni_tipologie, public.attivazione_mezzi, public.attivazione_materiali from anon;

-- ---------------------------------------------------------------------
-- 4. Campi configurabili
-- ---------------------------------------------------------------------
create or replace function public.campi_attivazione_validi(p jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select jsonb_typeof(p) = 'object'
     and not exists (
       select 1 from jsonb_each(p) e
        where e.key not in ('cellulare','patenti','abilitazioni','servizi','note','esigenze',
                            'tipologia','art39','orari','mezzi','materiali')
           or jsonb_typeof(e.value) <> 'string'
           or (e.value #>> '{}') not in ('non_richiesto','facoltativo','obbligatorio'));
$$;

-- ---------------------------------------------------------------------
-- 5. Vista base: + tipologia (art. 39 resta fuori)
-- ---------------------------------------------------------------------
create or replace view public.v_adesioni_base
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
                 from public.adesione_servizi x where x.adesione_id = a.id), '{}') as servizi,
       a.tipologia
from public.adesioni a
join public.attivazione_sezioni s on s.id = a.attivazione_sezione_id
where public.attivazione_accesso(a.attivazione_id);

-- ---------------------------------------------------------------------
-- 6. RPC pubbliche
-- ---------------------------------------------------------------------
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
                                          order by s.giorno, array_position(array['disponibile','colazione','pranzo','cena','pernotto'], s.tipo))
                         from public.attivazione_servizi s where s.attivazione_id = v_es.id), '[]'::jsonb),
    'patenti', coalesce((select jsonb_agg(nome order by ordine, nome) from public.attivazioni_patenti), '[]'::jsonb),
    'abilitazioni', coalesce((select jsonb_agg(nome order by ordine, nome) from public.attivazioni_abilitazioni), '[]'::jsonb),
    'esigenze', coalesce((select jsonb_agg(jsonb_build_object('nome', nome, 'con_nota', con_nota) order by ordine, nome)
                          from public.attivazioni_esigenze), '[]'::jsonb),
    'tipologie', coalesce((select jsonb_agg(nome order by ordine, nome) from public.attivazioni_tipologie), '[]'::jsonb),
    'volontari', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'cognome', a.cognome, 'nome', a.nome, 'codice_fiscale', a.codice_fiscale,
                 'cellulare', a.cellulare, 'patenti', a.patenti, 'abilitazioni', a.abilitazioni,
                 'note', a.note, 'esigenze', a.esigenze, 'esigenze_note', a.esigenze_note,
                 'tipologia', a.tipologia, 'art39', a.art39,
                 'servizi', coalesce((select jsonb_agg(x.servizio_id) from public.adesione_servizi x
                                      where x.adesione_id = a.id), '[]'::jsonb),
                 'orari', coalesce((select jsonb_object_agg(x.servizio_id::text,
                                             jsonb_build_object('dalle', to_char(x.ora_dalle, 'HH24:MI'),
                                                                'alle',  to_char(x.ora_alle,  'HH24:MI')))
                                      from public.adesione_servizi x
                                     where x.adesione_id = a.id and x.ora_dalle is not null), '{}'::jsonb))
               order by a.cognome, a.nome)
        from public.adesioni a where a.attivazione_sezione_id = v_sez.id), '[]'::jsonb),
    'mezzi', coalesce((
        select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'targa', m.targa, 'note', m.note,
                                            'giorni', to_jsonb(m.giorni)) order by m.id)
        from public.attivazione_mezzi m where m.attivazione_sezione_id = v_sez.id), '[]'::jsonb),
    'materiali', coalesce((
        select jsonb_agg(jsonb_build_object('quantita', m.quantita, 'descrizione', m.descrizione, 'note', m.note) order by m.id)
        from public.attivazione_materiali m where m.attivazione_sezione_id = v_sez.id), '[]'::jsonb)
  );
end;
$function$;

-- p_volontari: elenco dei volontari (come prima) oppure { volontari, mezzi, materiali }.
-- Mezzi/materiali assenti dal dato = non toccati; presenti = sostituiscono quelli della Sezione.
-- tipologia / art39 / orari assenti dal volontario = si conserva quanto già salvato.
CREATE OR REPLACE FUNCTION public.adesione_salva(p_token uuid, p_volontari jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c_max_volontari constant int := 150;
  c_max_mezzi     constant int := 50;
  c_max_materiali constant int := 100;
  v_sez       public.attivazione_sezioni%rowtype;
  v_es        public.attivazioni%rowtype;
  v_esist     public.adesioni%rowtype;
  l_cell      text;
  l_pat       text;
  l_abil      text;
  l_serv      text;
  l_note      text;
  l_esig      text;
  l_tipol     text;
  l_art39     text;
  l_orari     text;
  l_mezzi     text;
  l_mater     text;
  v_lista     jsonb;
  v_mezzi     jsonb;
  v_mater     jsonb;
  v           jsonb;
  v_cf        text;
  v_cognome   text;
  v_nome      text;
  v_cell      text;
  v_note      text;
  v_esig_note text;
  v_tipol     text;
  v_art39     boolean;
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

  l_cell  := coalesce(v_es.campi->>'cellulare',    'facoltativo');
  l_pat   := coalesce(v_es.campi->>'patenti',      'facoltativo');
  l_abil  := coalesce(v_es.campi->>'abilitazioni', 'facoltativo');
  l_serv  := coalesce(v_es.campi->>'servizi',      'facoltativo');
  l_note  := coalesce(v_es.campi->>'note',         'facoltativo');
  l_esig  := coalesce(v_es.campi->>'esigenze',     'non_richiesto');
  l_tipol := coalesce(v_es.campi->>'tipologia',    'non_richiesto');
  l_art39 := coalesce(v_es.campi->>'art39',        'non_richiesto');
  l_orari := coalesce(v_es.campi->>'orari',        'non_richiesto');
  l_mezzi := coalesce(v_es.campi->>'mezzi',        'non_richiesto');
  l_mater := coalesce(v_es.campi->>'materiali',    'non_richiesto');

  if p_volontari is null or jsonb_typeof(p_volontari) not in ('array','object') then
    raise exception 'Dati non validi.';
  end if;
  if jsonb_typeof(p_volontari) = 'array' then
    v_lista := p_volontari;
  else
    v_lista := coalesce(nullif(p_volontari->'volontari', 'null'::jsonb), '[]'::jsonb);
    if l_mezzi <> 'non_richiesto' then v_mezzi := nullif(p_volontari->'mezzi', 'null'::jsonb); end if;
    if l_mater <> 'non_richiesto' then v_mater := nullif(p_volontari->'materiali', 'null'::jsonb); end if;
  end if;
  if jsonb_typeof(v_lista) <> 'array'
     or (v_mezzi is not null and jsonb_typeof(v_mezzi) <> 'array')
     or (v_mater is not null and jsonb_typeof(v_mater) <> 'array') then
    raise exception 'Dati non validi.';
  end if;
  if jsonb_array_length(v_lista) = 0
     and coalesce(jsonb_array_length(v_mezzi), 0) = 0
     and coalesce(jsonb_array_length(v_mater), 0) = 0 then
    raise exception 'Inserisci almeno un volontario, oppure usa "La Sezione non partecipa".';
  end if;
  if jsonb_array_length(v_lista) > c_max_volontari then
    raise exception 'Puoi inviare al massimo % volontari per Sezione.', c_max_volontari;
  end if;
  if coalesce(jsonb_array_length(v_mezzi), 0) > c_max_mezzi then
    raise exception 'Puoi indicare al massimo % mezzi per Sezione.', c_max_mezzi;
  end if;
  if coalesce(jsonb_array_length(v_mater), 0) > c_max_materiali then
    raise exception 'Puoi indicare al massimo % materiali per Sezione.', c_max_materiali;
  end if;

  -- 1) validazione completa prima di toccare i dati
  for v in select * from jsonb_array_elements(v_lista) loop
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
    or (v ? 'esigenze'     and jsonb_typeof(v->'esigenze')     not in ('array','null'))
    or (v ? 'orari'        and jsonb_typeof(v->'orari')        not in ('object','null'))
    or (v ? 'art39'        and jsonb_typeof(v->'art39')        not in ('boolean','null')) then
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
    -- tipologia
    if l_tipol <> 'non_richiesto' then
      if l_tipol = 'obbligatorio' and trim(coalesce(v->>'tipologia', '')) = '' then
        raise exception 'Volontario n. % (% %): indica la tipologia.', n, v_cognome, v_nome;
      end if;
      if trim(coalesce(v->>'tipologia', '')) <> ''
         and v->>'tipologia' not in (select nome from public.attivazioni_tipologie) then
        raise exception 'Volontario n. %: tipologia non riconosciuta.', n;
      end if;
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
        raise exception 'Volontario n. % (% %): indica almeno una giornata, un pasto o un pernotto.', n, v_cognome, v_nome;
      end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'servizi', 'null'::jsonb), '[]')) p(x)
                 where case when x ~ '^[0-9]{1,18}$'
                            then x::bigint not in (select id from public.attivazione_servizi
                                                   where attivazione_id = v_es.id)
                            else true end) then
        raise exception 'Volontario n. %: servizio non valido per questo evento.', n;
      end if;
      -- orari: solo su giornate di disponibilità scelte, formato HH:MM, inizio diverso dalla fine
      if l_orari <> 'non_richiesto' and jsonb_typeof(v->'orari') = 'object' then
        if exists (
          select 1 from jsonb_each(v->'orari') e(k, o)
           where case
                   when k !~ '^[0-9]{1,18}$' or jsonb_typeof(o) <> 'object' then true
                   when coalesce(o->>'dalle', '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                     or coalesce(o->>'alle',  '') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
                     or o->>'dalle' = o->>'alle' then true
                   when k not in (select jsonb_array_elements_text(coalesce(nullif(v->'servizi', 'null'::jsonb), '[]'))) then true
                   else not exists (select 1 from public.attivazione_servizi s
                                     where s.id = k::bigint and s.attivazione_id = v_es.id and s.tipo = 'disponibile')
                 end) then
          raise exception 'Volontario n. % (% %): orari non validi (formato HH:MM, solo sulle giornate scelte).', n, v_cognome, v_nome;
        end if;
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

  -- mezzi
  n := 0;
  for v in select * from jsonb_array_elements(coalesce(v_mezzi, '[]'::jsonb)) loop
    n := n + 1;
    if jsonb_typeof(v) <> 'object'
       or (v ? 'giorni' and jsonb_typeof(v->'giorni') not in ('array','null')) then
      raise exception 'Mezzo n. %: dati non validi.', n;
    end if;
    if trim(coalesce(v->>'tipo', '')) = '' then
      raise exception 'Mezzo n. %: indica il tipo di mezzo.', n;
    end if;
    if length(trim(v->>'tipo')) > 80 or length(coalesce(trim(v->>'targa'), '')) > 15 or length(coalesce(v->>'note', '')) > 300 then
      raise exception 'Mezzo n. %: testo troppo lungo (tipo max 80, targa max 15, note max 300 caratteri).', n;
    end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(nullif(v->'giorni', 'null'::jsonb), '[]')) g(x)
                where x not in (select s.giorno::text from public.attivazione_servizi s where s.attivazione_id = v_es.id)) then
      raise exception 'Mezzo n. %: giorno non valido per questo evento.', n;
    end if;
  end loop;

  -- materiali
  n := 0;
  for v in select * from jsonb_array_elements(coalesce(v_mater, '[]'::jsonb)) loop
    n := n + 1;
    if jsonb_typeof(v) <> 'object' then
      raise exception 'Materiale n. %: dati non validi.', n;
    end if;
    if trim(coalesce(v->>'descrizione', '')) = '' then
      raise exception 'Materiale n. %: indica la descrizione.', n;
    end if;
    if coalesce(v->>'quantita', '') !~ '^[0-9]{1,5}$' or (v->>'quantita')::int not between 1 and 10000 then
      raise exception 'Materiale n. % (%): la quantità deve essere un numero da 1 a 10000.', n, trim(v->>'descrizione');
    end if;
    if length(trim(v->>'descrizione')) > 150 or length(coalesce(v->>'note', '')) > 300 then
      raise exception 'Materiale n. %: testo troppo lungo (descrizione max 150, note max 300 caratteri).', n;
    end if;
  end loop;

  -- 2) CF già iscritti da un'ALTRA Sezione dello stesso evento
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
  for v in select * from jsonb_array_elements(v_lista) loop
    v_cf        := upper(regexp_replace(coalesce(v->>'codice_fiscale', ''), '\s', '', 'g'));
    v_cognome   := upper(trim(v->>'cognome'));
    v_nome      := upper(trim(v->>'nome'));
    v_cell      := case when l_cell = 'non_richiesto' then null else nullif(trim(coalesce(v->>'cellulare', '')), '') end;
    v_note      := case when l_note = 'non_richiesto' then null else nullif(trim(coalesce(v->>'note', '')), '') end;
    v_esig_note := case when l_esig = 'non_richiesto' then null else nullif(trim(coalesce(v->>'esigenze_note', '')), '') end;
    v_tipol     := case when l_tipol = 'non_richiesto' then null else nullif(trim(coalesce(v->>'tipologia', '')), '') end;
    v_art39     := case when l_art39 = 'non_richiesto' then false else coalesce((v->>'art39')::boolean, false) end;
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
      -- campi non richiesti (o assenti dal dato, per tipologia e art. 39): si conserva quanto già presente
      if l_cell = 'non_richiesto' then v_cell      := v_esist.cellulare;     end if;
      if l_note = 'non_richiesto' then v_note      := v_esist.note;          end if;
      if l_pat  = 'non_richiesto' then v_patenti   := v_esist.patenti;       end if;
      if l_abil = 'non_richiesto' then v_abil      := v_esist.abilitazioni;  end if;
      if l_esig = 'non_richiesto' then v_esig      := v_esist.esigenze;
                                       v_esig_note := v_esist.esigenze_note; end if;
      if l_tipol = 'non_richiesto' or not (v ? 'tipologia') then v_tipol := v_esist.tipologia; end if;
      if l_art39 = 'non_richiesto' or not (v ? 'art39')     then v_art39 := v_esist.art39;     end if;

      if (v_esist.volontario_id, v_esist.cognome, v_esist.nome, v_esist.cellulare,
          v_esist.patenti, v_esist.abilitazioni, v_esist.note, v_esist.esigenze, v_esist.esigenze_note,
          v_esist.tipologia, v_esist.art39)
         is distinct from
         (v_vol_id, v_cognome, v_nome, v_cell, v_patenti, v_abil, v_note, v_esig, v_esig_note,
          v_tipol, v_art39) then
        update public.adesioni
           set volontario_id = v_vol_id, cognome = v_cognome, nome = v_nome, cellulare = v_cell,
               patenti = v_patenti, abilitazioni = v_abil, note = v_note,
               esigenze = v_esig, esigenze_note = v_esig_note,
               tipologia = v_tipol, art39 = v_art39
         where id = v_esist.id;
      end if;
      v_id := v_esist.id;
    else
      begin
        insert into public.adesioni (attivazione_id, attivazione_sezione_id, volontario_id,
                                     cognome, nome, codice_fiscale, cellulare, patenti, abilitazioni, note,
                                     esigenze, esigenze_note, tipologia, art39)
        values (v_es.id, v_sez.id, v_vol_id, v_cognome, v_nome, v_cf, v_cell, v_patenti, v_abil, v_note,
                v_esig, v_esig_note, v_tipol, v_art39)
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
      -- orari: solo se inviati; giornata senza orario = giornata intera
      if l_orari <> 'non_richiesto' and v ? 'orari' then
        update public.adesione_servizi x
           set ora_dalle = (v->'orari'->(x.servizio_id::text)->>'dalle')::time,
               ora_alle  = (v->'orari'->(x.servizio_id::text)->>'alle')::time
         where x.adesione_id = v_id;
      end if;
    end if;
  end loop;

  -- 5) mezzi e materiali: sostituiti solo se inviati
  if v_mezzi is not null then
    delete from public.attivazione_mezzi where attivazione_sezione_id = v_sez.id;
    insert into public.attivazione_mezzi (attivazione_id, attivazione_sezione_id, tipo, targa, giorni, note)
    select v_es.id, v_sez.id, upper(trim(m->>'tipo')) , nullif(upper(regexp_replace(coalesce(m->>'targa', ''), '\s', '', 'g')), ''),
           coalesce((select array_agg(distinct g::date order by g::date)
                       from jsonb_array_elements_text(coalesce(nullif(m->'giorni', 'null'::jsonb), '[]')) x(g)), '{}'),
           nullif(trim(coalesce(m->>'note', '')), '')
      from jsonb_array_elements(v_mezzi) with ordinality t(m, i)
     order by i;
  end if;
  if v_mater is not null then
    delete from public.attivazione_materiali where attivazione_sezione_id = v_sez.id;
    insert into public.attivazione_materiali (attivazione_id, attivazione_sezione_id, quantita, descrizione, note)
    select v_es.id, v_sez.id, (m->>'quantita')::int, trim(m->>'descrizione'), nullif(trim(coalesce(m->>'note', '')), '')
      from jsonb_array_elements(v_mater) with ordinality t(m, i)
     order by i;
  end if;

  update public.attivazione_sezioni
     set stato = 'risposto', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true, 'volontari', jsonb_array_length(v_lista),
                            'mezzi', coalesce(jsonb_array_length(v_mezzi), 0),
                            'materiali', coalesce(jsonb_array_length(v_mater), 0));
end;
$function$;

-- "non partecipa": tolgo anche mezzi e materiali
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
  delete from public.attivazione_mezzi where attivazione_sezione_id = v_sez.id;
  delete from public.attivazione_materiali where attivazione_sezione_id = v_sez.id;
  update public.attivazione_sezioni
     set stato = 'non_partecipa', risposto_at = now()
   where id = v_sez.id;

  return jsonb_build_object('ok', true);
end;
$function$;

-- ---------------------------------------------------------------------
-- 7. Cucina: le giornate di disponibilità non sono pasti
-- ---------------------------------------------------------------------
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
  where s.attivazione_id = p_attivazione_id
    and s.tipo <> 'disponibile';

  return v;
end;
$function$;

-- ---------------------------------------------------------------------
-- 8. Riepilogo per giorno (anche "base": niente nomi, CF, cellulari, art. 39)
-- ---------------------------------------------------------------------
create function public.attivazione_giorni(p_attivazione_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.attivazione_accesso(p_attivazione_id) then
    raise exception 'Permesso negato.';
  end if;

  with righe as (
    select x.servizio_id, x.ora_dalle, x.ora_alle, a.tipologia, a.patenti, a.abilitazioni, z.sezione
      from public.adesione_servizi x
      join public.adesioni a on a.id = x.adesione_id
      join public.attivazione_sezioni z on z.id = a.attivazione_sezione_id
     where a.attivazione_id = p_attivazione_id
  )
  select jsonb_build_object(
    'giorni', coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'giorno', s.giorno,
        'volontari',  (select count(*) from righe r where r.servizio_id = s.id),
        'con_orario', (select count(*) from righe r where r.servizio_id = s.id and r.ora_dalle is not null),
        'fasce',      coalesce((select jsonb_object_agg(f.k, f.n) from (
                         select to_char(r.ora_dalle, 'HH24:MI') || '–' || to_char(r.ora_alle, 'HH24:MI') as k, count(*) as n
                           from righe r where r.servizio_id = s.id and r.ora_dalle is not null group by 1) f), '{}'::jsonb),
        'tipologie',  coalesce((select jsonb_object_agg(f.k, f.n) from (
                         select coalesce(r.tipologia, '') as k, count(*) as n
                           from righe r where r.servizio_id = s.id group by 1) f), '{}'::jsonb),
        'patenti',    coalesce((select jsonb_object_agg(f.k, f.n) from (
                         select unnest(r.patenti) as k, count(*) as n
                           from righe r where r.servizio_id = s.id group by 1) f), '{}'::jsonb),
        'abilitazioni', coalesce((select jsonb_object_agg(f.k, f.n) from (
                         select unnest(r.abilitazioni) as k, count(*) as n
                           from righe r where r.servizio_id = s.id group by 1) f), '{}'::jsonb),
        'sezioni',    coalesce((select jsonb_object_agg(f.k, f.n) from (
                         select r.sezione as k, count(*) as n
                           from righe r where r.servizio_id = s.id group by 1) f), '{}'::jsonb),
        'mezzi',      (select count(*) from public.attivazione_mezzi m
                        where m.attivazione_id = p_attivazione_id and s.giorno = any(m.giorni))
      ) order by s.giorno), '[]'::jsonb)
  ) into v
  from public.attivazione_servizi s
  where s.attivazione_id = p_attivazione_id
    and s.tipo = 'disponibile';

  return v;
end;
$$;

-- ---------------------------------------------------------------------
-- 9. Privilegi
-- ---------------------------------------------------------------------
revoke all on function public.attivazione_giorni(bigint) from public, anon;
grant execute on function public.attivazione_giorni(bigint) to authenticated, service_role;

revoke all on function public.adesione_get(uuid)          from public;
revoke all on function public.adesione_salva(uuid, jsonb) from public;
revoke all on function public.adesione_nessuna(uuid)      from public;
grant execute on function public.adesione_get(uuid)          to anon, authenticated, service_role;
grant execute on function public.adesione_salva(uuid, jsonb) to anon, authenticated, service_role;
grant execute on function public.adesione_nessuna(uuid)      to anon, authenticated, service_role;

commit;
