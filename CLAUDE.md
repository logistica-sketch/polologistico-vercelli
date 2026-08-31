# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Polo Logistico 1 RGPT/CAP Vercelli" — a gestionale (management app) for vehicles (automezzi) and radio/telecom equipment (TLC) of a Croce Rossa Italiana logistics unit. Italian-language UI throughout; comments and identifiers in the code are Italian.

It is a static, no-build, single-page PWA: there is no bundler, package manager, or compile step. All application logic lives in one file, `index.html` (~5800 lines: markup + CSS classes + a single `<script>` block with the entire app). `stile.css` holds shared styles, `sw.js` is a minimal service worker (installability only, no offline API caching — see comments at the top of that file), and `manifest.json` is the PWA manifest.

The backend is Supabase (Postgres + Auth + Storage), used directly from the client via `@supabase/supabase-js` — there is no server-side code in this repo.

## Commands

There is no build/test/lint tooling in this repo (no `package.json`). To work on it:

- **Run locally**: serve the directory with any static file server (e.g. `npx serve .` or `python -m http.server`) and open `index.html`. Opening the file directly via `file://` will break the service worker and some fetch-based flows.
- **Deploy**: this is a GitHub Pages site (see `CNAME` → `polologistico.coordanapiemonte.it`). Pushing to the deployed branch publishes the change; there is no separate build artifact.
- There are no automated tests. Verify changes by exercising the affected screen manually in a browser against the live Supabase backend (see Data layer below — there is no local/mock backend).

## Architecture

### Single-file app structure (`index.html`)

The `<script>` block is organized as sequential sections marked by `/* ===== ... ===== */` comment banners, roughly in this order:
1. **CONFIG** — Supabase client init (`sb`), PDF.js worker setup.
2. **STATO GLOBALE** — a single `state` object (`state.user`, `state.profile`, `state.route`) holds all client-side session state. There is no framework/reactivity: screens re-render themselves imperatively by rebuilding `innerHTML` and reattaching listeners.
3. **DEFINIZIONE MENU** — the `MENU` array drives the sidebar and doubles as the routing/permission table (each entry maps a `route` to a `permesso` key).
4. **UTILITY** — Italian date formatting, expiry-status helpers, `escapeHtml`.
5. **AUTH** — Supabase Auth (email/password), plus a first-login bootstrap that auto-creates a row in `app_users` with role `standard`.
6. **SIDEBAR / NAV / ROUTER** — a hash-based router (`#/route`, see `router()`): each route maps to one `render<Section>()` function that owns fetching data and rendering that page's `#page-content` HTML.
7. One large section per feature module, each following the same pattern: `render<Modulo>()` (page shell + grid/list) → `apriModal<Entita>(id)` / `renderModal<Entita>()` (detail modal with tabs) → per-tab `renderTab...()` + `carica...()` (data fetch) functions → CRUD handlers (`salva...`, `elimina...`).

### Feature modules (each is a self-contained block of functions, in this order in the file)

- **Automezzi** — vehicle registry: data sheet, photos (stored per-vehicle/side), documents, manutenzioni (maintenance), movimenti (movements/assignments).
- **TLC / Radio** — radio/telecom equipment inventory (`tlc_apparati`), with Excel import/export, and **movimentazioni** (check-out/check-in of equipment) including an on-screen signature capture (`creaCanvasFirma`) and PDF "bolla" (delivery note) generation/archival.
- **Formazione** — training courses (`catalogo_corsi`, `edizioni_corso`), volunteer registry (`volontari_formazione`), enrollments (`iscrizioni_corsi`), certificate (attestato) uploads including bulk ZIP import.
- **Firma Documenti** — generic PDF document signing: load a PDF with pdf.js, place a draggable/resizable signature overlay, flatten it with pdf-lib.
- **Libro Matricola** — a separate vehicle registry/ledger with its own documents and Excel/PDF export, including bulk ZIP import of "polizze" (insurance policies).
- **Convocazioni** — notice/summons generation to recipient groups (`gruppi_destinatari`), producing PDFs.
- **Impostazioni / Gestione Utenti** — self-service (password change, personal signature for TLC hand-offs), plus IT-admin-only user management, role/permission editing, and access log viewer (`log_accessi`).

When adding a feature, follow the existing module's pattern (render/modal/tab/carica/salva/elimina) rather than introducing a new structure — the whole app is intentionally consistent this way.

### Permissions model

Roles (`app_users.ruolo`): `it_admin`, `specialita`, `segreteria`, `standard`. `it_admin` bypasses all checks. Other roles are gated by a per-user `permessi` JSON object keyed by section name (matching `MENU[].permesso`), checked via `userCanSee(permesso)`. Some sections (currently `tlc`) support graded access — `livelloPermesso(sezione)` returns `"completo"` or `"base"` instead of a boolean. `_solo_it_admin` and `_almeno_una_sezione` are special pseudo-permission keys handled directly in `userCanSee`/`paginaImpostazioniHaSezioni`. Route access is enforced both in `renderSidebar()` (hides items) and `router()` (redirects to home if the current route isn't allowed) — new routes/sections need both to be updated, plus the corresponding checks inside the section's own render function for any sub-actions that need a finer-grained (`completo` vs `base`) check.

### Data layer (Supabase)

- Client: `sb` (`window.supabase.createClient(...)`), configured with `persistSession: false` / `autoRefreshToken: false` — the app deliberately does not keep the user logged in across reloads (`initAuth()` force-signs-out and clears any leftover `sb-*` storage keys on load), so every page load requires fresh login.
- All data access is direct `sb.from("<table>").select/insert/update/delete(...)` calls scattered through each module — there is no data-access abstraction layer. Row-level security in Supabase (not in this repo) is the actual authorization boundary; client-side `userCanSee`/`livelloPermesso` only control UI visibility.
- Tables in use: `app_users`, `automezzi`, `documenti_automezzi`, `manutenzioni_automezzi`, `movimenti_automezzi`, `tlc_apparati`, `tlc_categorie`, `tlc_marche`, `tlc_sottocategorie_radio`, `movimentazioni_tlc`, `movimentazioni_tlc_apparati`, `catalogo_corsi`, `edizioni_corso`, `volontari_formazione`, `iscrizioni_corsi`, `documenti_volontario`, `firme_salvate`, `libro_matricola`, `documenti_libro_matricola`, `convocazioni`, `gruppi_destinatari`, `log_accessi`, `log_attivita`, plus a view `v_scadenze` (expirations, feeds the Home dashboard alerts).
- Storage buckets (each declared as a `STORAGE_BUCKET_*` constant near its first use): `mezzi-foto`, `mezzi-documenti`, `tlc-bolle`, `volontari-documenti`, `firme-personali`, and buckets for libro-matricola documents and saved TLC signatures — grep `STORAGE_BUCKET_` to find each one's declaration site and usage.
- Supabase URL and anon key are hardcoded at the top of `index.html` (this is a client-only anon key, expected to be public; do not add service-role keys or other secrets here).

### External libraries (all loaded via CDN `<script>` tags in `<head>`, no local copies/bundling)

`@supabase/supabase-js@2`, `heic2any` (HEIC photo conversion), `jspdf` + `pdf-lib` (PDF generation/editing), `pdf.js` (PDF rendering for the Firma Documenti viewer), `xlsx` (Excel import/export), `jszip` (bulk ZIP import/export), `@tabler/icons-webfont` (icon font).
