# Editor PDF – istruzioni per Claude Code

Repo: `logistica-sketch/polologistico-vercelli` (file principali `index.html` e `stile.css` nella root).
Obiettivo: aggiungere la pagina **Editor PDF** all'app Polo Logistico 1 RGPT/CAP Vercelli.

> Lavora a patch: modifica `index.html` e `stile.css` esistenti, non riscriverli.
> Non cancellare mai dati: i documenti si annullano, i modelli si disattivano.
> Il file `riferimento_prototipo.html` contiene la logica già funzionante (editor campi, compilazione, export pdf-lib): riusala e adattala allo stile dell'app.

---

## 0. Prerequisiti (già fatti a mano da Federico)

1. Eseguito `01_editor_pdf.sql` nell'SQL Editor di Supabase.
2. Pubblicata la Edge Function `editor-pdf-firma` con **verifica JWT disattivata**, secret `PUBLIC_SITE_URL=https://polologistico.coordanapiemonte.it`.
3. Caricato `firma.html` nella root del repo (pagina pubblica, non toccarla se non richiesto).

## 1. Librerie

Aggiungi in `index.html`, prima dello script dell'app, con versione fissa:

```html
<script src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/pdf-lib@1.17.1/dist/pdf-lib.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/signature_pad@4.2.0/dist/signature_pad.umd.min.js"></script>
```

Il worker caricato come script fa girare pdf.js senza Web Worker separato: va bene così.

## 2. Menu e permessi

- Nuova voce in sidebar **Editor PDF**, icona Tabler `ti-file-pencil`, visibile se `permessi.editor_pdf` è `base` o `completo` (o ruolo `it_admin`).
- In Impostazioni → gestione utenti aggiungi il permesso **Editor PDF** con i livelli già usati negli altri moduli (`base`, `completo`).
  - `base`: vede, crea e compila documenti, firma, crea link.
  - `completo`: in più crea e modifica i modelli.
- Registra le operazioni in `log_attivita` come fanno gli altri moduli.

## 3. Struttura della pagina

Tre schede in alto: **Documenti** (predefinita), **Modelli**, **Registro**.

### 3a. Modelli (solo `completo`)
- Elenco da `pdf_modelli` (attivi in alto, disattivati in grigio) con: nome, n. campi, versione, aggiornato il.
- **Nuovo modello**: carica PDF → upload in bucket `pdf-modelli` come `{uuid}.pdf` → si apre l'editor.
- **Editor**: porta da `riferimento_prototipo.html` la modalità "Modello" (palette campi, trascina, ridimensiona, frecce, pannello proprietà). Salvataggio in `pdf_modelli.campi` / `pagine` con lo stesso formato del JSON del prototipo:
  `{id, nome, tipo: text|date|check|sign, pagina (da 1), x, y, larghezza, altezza, dato, obbligatorio, dimensione_testo}` — punti PDF, origine in alto a sinistra.
- Ogni salvataggio incrementa `versione`. Pulsante **Disattiva** (mai elimina).
- Anteprima "Prova compilazione" = modalità Compila del prototipo con dati reali.

### 3b. Dati collegabili (sostituiscono i dati finti del prototipo)

| chiave `dato` | sorgente |
|---|---|
| `volontari.nome_completo` | `volontari_formazione.nome` + `cognome` |
| `volontari.codice_fiscale` | `volontari_formazione.codice_fiscale` |
| `volontari.data_nascita` | `volontari_formazione.data_nascita` (gg/mm/aaaa) |
| `volontari.luogo_nascita` | `luogo_nascita` + ` (` + `provincia_nascita` + `)` |
| `volontari.sezione` | `volontari_formazione.sezione_ana` |
| `volontari.telefono` / `volontari.email` | stessi nomi |
| `tlc.codice_ana` / `tlc.descrizione` / `tlc.matricola` | `tlc_apparati` |
| `tlc.marca_modello` | `marca` + ` ` + `modello` |
| `tlc.categoria` | `categoria` (+ `sottocategoria_radio` se presente) |
| `sistema.oggi` | data odierna |
| `sistema.utente` | `app_users.nome` dell'utente collegato |
| `sistema.firma_utente` | PNG dal bucket `firme-personali` (`app_users.firma_personale_path`) |
| `manuale` | inserito a mano in compilazione |
| `esterno` | **nuovo, solo per tipo `sign`**: firma raccolta con link monouso |

Il volontario si sceglie con ricerca per cognome o codice fiscale, il materiale per codice ANA o matricola. I gruppi che un modello non usa non si mostrano.

### 3c. Documenti
- Elenco da `pdf_documenti` con filtri per stato (`bozza`, `in_firma`, `firmato`, `annullato`) e ricerca titolo. Badge colorati per stato.
- **Nuovo documento**: scegli modello attivo → scegli volontario/materiale se il modello li usa → compilazione (modalità Compila del prototipo). Titolo proposto: `{nome modello} – {cognome nome} – {gg/mm/aaaa}`, modificabile.
- **Firma interna**: i campi `manuale` di tipo firma si firmano nel riquadro (usa **signature_pad** al posto del canvas fatto a mano del prototipo). `sistema.firma_utente` si applica da solo.
- **Salva** (genera il PDF):
  1. pdf-lib come nel prototipo: testi, caselle, firme già disponibili; flatten dei campi AcroForm; i campi `esterno` restano vuoti.
  2. Inserisci la riga in `pdf_documenti` con `campi` = **copia** dei campi del modello, `modello_versione`, `valori` (senza immagini), `riferimenti` (`volontario_id`, `tlc_id`), `firme_completate` = id dei campi firma già apposti, `creato_da = auth.uid()`.
  3. Upload in `pdf-documenti/{documento_id}/v1.pdf`, poi aggiorna `pdf_path`, `versione_pdf = 1`, `sha256` (calcolato con `crypto.subtle`).
  4. Stato: `firmato` se non restano firme obbligatorie, altrimenti `in_firma`.
  5. Riga in `pdf_audit` (`creato`, e `firma_interna` per ogni firma interna) con `utente_id`, `attore` = email, `sha256`.
- Una bozza si può ancora modificare (nuova versione `v{n+1}`, mai sovrascrivere). Da `in_firma` in poi il PDF lo aggiorna solo la Edge Function.
- **Annulla documento**: chiede il motivo, imposta `stato = annullato`, `annullato_il`, `annullato_da`, `motivo_annullo`, audit `annullato`. I link aperti smettono di funzionare da soli.

### 3d. Dettaglio documento
- Anteprima della versione corrente (signed URL 5 minuti dal bucket `pdf-documenti`) e pulsante **Scarica PDF**.
- Per ogni campo firma: stato (Firmato / In attesa / Link inviato a X, scade il …) letto da `firme_completate` e `pdf_firme_richieste`.
- Pulsante **Crea link di firma** sui campi `esterno` non firmati: chiede nome del firmatario, contatto (facoltativo) e validità (24 h, 48 h, 72 h, 7 giorni; predefinito 48 h). Chiamata:

```js
const { data, error } = await supabase.functions.invoke('editor-pdf-firma', {
  body: { azione: 'crea', documento_id, campo_id, firmatario_nome, firmatario_contatto, ore_validita: 48 }
});
// data = { richiesta_id, link, scade_il }
```

  Il link si mostra **una sola volta** (il database salva solo l'hash). Pulsanti: **Copia link**, **WhatsApp** (`https://wa.me/?text=` + testo codificato), **Email** (`mailto:`), **Condividi** (`navigator.share` se disponibile). Testo proposto:
  `Ciao {nome}, ti chiediamo di firmare "{titolo}". Apri il link entro il {data}: {link}`
- **Revoca link** sulle richieste ancora attive: `invoke('editor-pdf-firma', { body: { azione: 'revoca', richiesta_id } })`. Creare un nuovo link per lo stesso campo revoca da solo il precedente.
- Cronologia del documento da `pdf_audit` (evento, chi, quando, IP per le firme esterne, impronta abbreviata).
- Aggiorna lo stato con Supabase Realtime su `pdf_documenti` oppure con un pulsante Aggiorna.

### 3e. Registro
Tabella di `pdf_audit` con filtri per periodo ed evento, export Excel con ExcelJS come negli altri moduli.

## 4. Codici di errore della Edge Function
`non_autorizzato`, `dati_mancanti`, `documento_non_trovato`, `documento_chiuso`, `pdf_mancante`, `campo_non_valido`, `campo_gia_firmato`, `non_revocabile`, `errore_interno`. Mostra messaggi chiari in italiano, es. `campo_gia_firmato` → "Questo campo è già stato firmato."

## 5. Note tecniche
- pdf-lib usa coordinate con origine in basso: `y_pdf = altezzaPagina - y - altezza` (vedi `generate()` nel prototipo).
- Font Helvetica standard: sostituisci con `?` i caratteri fuori da Latin‑1 (funzione `safe()` del prototipo).
- Firme PNG ritagliate prima dell'inserimento (funzione `trimCanvas()` del prototipo).
- Pagine ruotate non gestite: se `page.rotate` ≠ 0, avvisa che il modello potrebbe non allinearsi.
- Nella riga di audit in fondo al PDF usa: `Compilato e firmato elettronicamente il {data} alle {ora} – Polo Logistico 1 RGPT/CAP Vercelli`.
- Comandi git a fine lavoro: `git add -A && git commit -m "Editor PDF" && git push`.
