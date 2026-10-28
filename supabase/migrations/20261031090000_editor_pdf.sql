-- =====================================================================
-- EDITOR PDF – Polo Logistico 1 RGPT/CAP Vercelli
-- Da eseguire a mano nell'SQL Editor di Supabase (progetto hzovguvwnadoptwrdyub)
--
-- Permesso in app_users.permessi:  "editor_pdf"
--   'base'     -> vede e compila documenti, firma, crea link di firma
--   'completo' -> in più crea e modifica i modelli
--   it_admin   -> tutto (come nel resto dell'app)
--
-- Nessun dato storico viene cancellato: i documenti si ANNULLANO,
-- ogni versione del PDF resta nello storage (v1, v2, v3...).
-- =====================================================================

-- ---------- MODELLI ----------
create table if not exists public.pdf_modelli (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null,
  descrizione   text,
  pdf_path      text not null,                 -- bucket pdf-modelli
  pagine        jsonb not null default '[]',   -- [{larghezza, altezza}] in punti PDF
  campi         jsonb not null default '[]',   -- stesso formato del JSON del prototipo
  versione      int  not null default 1,
  attivo        boolean not null default true,
  creato_da     uuid references auth.users(id),
  creato_il     timestamptz not null default now(),
  aggiornato_il timestamptz not null default now()
);

-- ---------- DOCUMENTI ----------
create table if not exists public.pdf_documenti (
  id               uuid primary key default gen_random_uuid(),
  modello_id       uuid references public.pdf_modelli(id),
  modello_versione int,
  titolo           text not null,
  stato            text not null default 'bozza'
                   check (stato in ('bozza','in_firma','firmato','annullato')),
  campi            jsonb not null default '[]',  -- COPIA dei campi del modello al momento della creazione
  valori           jsonb not null default '{}',  -- campo_id -> valore (testi, date, caselle; NO immagini firma)
  riferimenti      jsonb not null default '{}',  -- es. {"volontario_id": 12, "tlc_id": 40}
  firme_completate jsonb not null default '[]',  -- elenco campo_id firma già apposti
  pdf_path         text,                         -- versione corrente nel bucket pdf-documenti
  versione_pdf     int  not null default 0,      -- blocco ottimistico per firme contemporanee
  sha256           text,                         -- impronta della versione corrente
  creato_da        uuid references auth.users(id),
  creato_il        timestamptz not null default now(),
  aggiornato_il    timestamptz not null default now(),
  firmato_il       timestamptz,
  annullato_il     timestamptz,
  annullato_da     uuid references auth.users(id),
  motivo_annullo   text
);
create index if not exists pdf_documenti_stato_idx   on public.pdf_documenti(stato);
create index if not exists pdf_documenti_modello_idx on public.pdf_documenti(modello_id);

-- ---------- RICHIESTE DI FIRMA VIA LINK ----------
create table if not exists public.pdf_firme_richieste (
  id                  uuid primary key default gen_random_uuid(),
  documento_id        uuid not null references public.pdf_documenti(id),
  campo_id            text not null,
  firmatario_nome     text not null,
  firmatario_contatto text,                    -- mail o telefono
  token_hash          text unique not null,    -- sha256 del token: il token in chiaro non si salva mai
  scade_il            timestamptz not null,
  aperto_il           timestamptz,
  usato_il            timestamptz,
  revocato_il         timestamptz,
  revocato_da         uuid references auth.users(id),
  ip                  text,
  user_agent          text,
  creato_da           uuid references auth.users(id),
  creato_il           timestamptz not null default now()
);
create index if not exists pdf_firme_richieste_doc_idx on public.pdf_firme_richieste(documento_id);

-- ---------- REGISTRO (solo aggiunta) ----------
create table if not exists public.pdf_audit (
  id           bigint generated always as identity primary key,
  documento_id uuid references public.pdf_documenti(id),
  evento       text not null,   -- creato, salvato, firma_interna, link_creato, link_revocato,
                                -- link_aperto, firma_link, completato, annullato
  campo_id     text,
  attore       text,            -- email utente o nome del firmatario esterno
  utente_id    uuid,
  ip           text,
  user_agent   text,
  sha256       text,
  dettagli     jsonb,
  creato_il    timestamptz not null default now()
);
create index if not exists pdf_audit_doc_idx on public.pdf_audit(documento_id, creato_il);

-- ---------- aggiornato_il automatico ----------
create or replace function public.pdf_touch() returns trigger
language plpgsql as $$ begin new.aggiornato_il = now(); return new; end $$;

drop trigger if exists pdf_modelli_touch on public.pdf_modelli;
create trigger pdf_modelli_touch before update on public.pdf_modelli
  for each row execute function public.pdf_touch();
drop trigger if exists pdf_documenti_touch on public.pdf_documenti;
create trigger pdf_documenti_touch before update on public.pdf_documenti
  for each row execute function public.pdf_touch();

-- =====================================================================
-- RLS (usa le funzioni già presenti: ha_accesso, ha_permesso, is_it_admin)
-- =====================================================================
alter table public.pdf_modelli         enable row level security;
alter table public.pdf_documenti       enable row level security;
alter table public.pdf_firme_richieste enable row level security;
alter table public.pdf_audit           enable row level security;

-- Modelli
drop policy if exists "pdf_modelli: lettura"   on public.pdf_modelli;
drop policy if exists "pdf_modelli: inserimento" on public.pdf_modelli;
drop policy if exists "pdf_modelli: modifica"  on public.pdf_modelli;
create policy "pdf_modelli: lettura" on public.pdf_modelli for select to authenticated
  using (ha_accesso('editor_pdf'));
create policy "pdf_modelli: inserimento" on public.pdf_modelli for insert to authenticated
  with check (ha_permesso('editor_pdf'));
create policy "pdf_modelli: modifica" on public.pdf_modelli for update to authenticated
  using (ha_permesso('editor_pdf')) with check (ha_permesso('editor_pdf'));
-- niente delete: i modelli si disattivano (attivo = false)

-- Documenti
drop policy if exists "pdf_documenti: lettura"     on public.pdf_documenti;
drop policy if exists "pdf_documenti: inserimento" on public.pdf_documenti;
drop policy if exists "pdf_documenti: modifica"    on public.pdf_documenti;
create policy "pdf_documenti: lettura" on public.pdf_documenti for select to authenticated
  using (ha_accesso('editor_pdf'));
create policy "pdf_documenti: inserimento" on public.pdf_documenti for insert to authenticated
  with check (ha_accesso('editor_pdf') and creato_da = auth.uid());
-- i documenti firmati o annullati non si toccano più dal portale
create policy "pdf_documenti: modifica" on public.pdf_documenti for update to authenticated
  using (ha_accesso('editor_pdf') and (stato in ('bozza','in_firma') or is_it_admin()))
  with check (ha_accesso('editor_pdf'));
-- niente delete

-- Richieste di firma: il portale le LEGGE, le crea/revoca solo la Edge Function
drop policy if exists "pdf_firme_richieste: lettura" on public.pdf_firme_richieste;
create policy "pdf_firme_richieste: lettura" on public.pdf_firme_richieste for select to authenticated
  using (ha_accesso('editor_pdf'));

-- Registro: lettura e aggiunta, mai modifica
drop policy if exists "pdf_audit: lettura"     on public.pdf_audit;
drop policy if exists "pdf_audit: inserimento" on public.pdf_audit;
create policy "pdf_audit: lettura" on public.pdf_audit for select to authenticated
  using (ha_accesso('editor_pdf'));
create policy "pdf_audit: inserimento" on public.pdf_audit for insert to authenticated
  with check (ha_accesso('editor_pdf') and utente_id = auth.uid());

-- =====================================================================
-- STORAGE
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('pdf-modelli','pdf-modelli',false), ('pdf-documenti','pdf-documenti',false)
on conflict (id) do nothing;

drop policy if exists "pdf-modelli: lettura"   on storage.objects;
drop policy if exists "pdf-modelli: scrittura" on storage.objects;
drop policy if exists "pdf-modelli: modifica"  on storage.objects;
create policy "pdf-modelli: lettura" on storage.objects for select to authenticated
  using (bucket_id = 'pdf-modelli' and ha_accesso('editor_pdf'));
create policy "pdf-modelli: scrittura" on storage.objects for insert to authenticated
  with check (bucket_id = 'pdf-modelli' and ha_permesso('editor_pdf'));
create policy "pdf-modelli: modifica" on storage.objects for update to authenticated
  using (bucket_id = 'pdf-modelli' and ha_permesso('editor_pdf'));

-- pdf-documenti: percorso {documento_id}/v{n}.pdf, solo nuove versioni (niente sovrascritture)
drop policy if exists "pdf-documenti: lettura"   on storage.objects;
drop policy if exists "pdf-documenti: scrittura" on storage.objects;
create policy "pdf-documenti: lettura" on storage.objects for select to authenticated
  using (bucket_id = 'pdf-documenti' and ha_accesso('editor_pdf'));
create policy "pdf-documenti: scrittura" on storage.objects for insert to authenticated
  with check (bucket_id = 'pdf-documenti' and ha_accesso('editor_pdf'));
