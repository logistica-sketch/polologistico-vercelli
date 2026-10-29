# Editor PDF – pacchetto di installazione

Ordine consigliato:

1. **SQL** – Supabase → SQL Editor → incolla ed esegui `01_editor_pdf.sql`.
2. **Edge Function** – Supabase → Edge Functions → Deploy new function → nome `editor-pdf-firma`,
   incolla `supabase/functions/editor-pdf-firma/index.ts`.
   Poi nelle impostazioni della funzione disattiva **Verify JWT** (oppure da CLI:
   `npx supabase functions deploy editor-pdf-firma --no-verify-jwt`).
3. **Secret** – Edge Functions → Secrets → `PUBLIC_SITE_URL` = `https://polologistico.coordanapiemonte.it`
4. **firma.html** – copiala nella root del repo `polologistico-vercelli`.
5. **Permessi** – dai `editor_pdf` = `completo` agli utenti che gestiscono i modelli.
6. **Claude Code** – apri il repo in VS Code e passa `ISTRUZIONI_CLAUDE_CODE.md`
   insieme a `riferimento_prototipo.html`.

Prova rapida del link: crea un documento con un campo firma `esterno`, genera il link,
aprilo dal telefono, firma, poi riaprilo: deve risultare "Documento già firmato".
