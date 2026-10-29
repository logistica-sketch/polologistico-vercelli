# Guida al Polo Logistico

Sito statico, nessuna installazione. File: `index.html` (motore), `dati.js` (testi, schermate, passi), `icon-192.png`.

## Pubblicare
Copia la cartella su GitHub Pages (repo a sé, oppure cartella `/guida` del repo dell'app → polologistico.coordanapiemonte.it/guida/).

## Link utili
- Una pagina: `…/#tlc`  (benvenuto, accesso, poi gli stessi nomi delle route dell'app: home, automezzi, tlc, formazione, firma, editorpdf, libromatricola, esercitazioni, emergenze, utenti, impostazioni, adesione)
- Solo alcune pagine: `?solo=tlc,formazione`
- Togliere pagine: `?escludi=utenti,editorpdf`
- Per profilo: `?profilo=base` (nasconde i passi "permesso completo" e Gestione Utenti) · `?profilo=completo` (nasconde solo Gestione Utenti)
- Il pulsante "Guida su misura" in alto crea questi link senza scriverli a mano.

## Spiegazione a voce
I copioni parlati sono in `dati.js`: `intro` per ogni pagina, `v` per ogni passo.
Gli MP3 si generano con lo script (Node 18+), dalla cartella della guida:

    ELEVENLABS_API_KEY=xxx ELEVENLABS_VOICE_ID=yyy node genera-audio.mjs

Crea `audio/<pagina>-00.mp3` (introduzione), `-01`, `-02`… (passi) e `audio/elenco.json`.
Rigenera solo i passi con testo cambiato. Opzioni: `--solo tlc,formazione`, `--forza`, `--prova` (mostra cosa farebbe, gratis).
Con Google: `GOOGLE_API_KEY=xxx GOOGLE_VOICE=<nome voce it-IT> node genera-audio.mjs --google`.
Pronuncia di sigle (TLC, PDF, CAI…): lista `PRONUNCIA` in cima allo script.
Finché la cartella `audio/` non c'è, i pulsanti Ascolta non compaiono.

## Video
In `dati.js`, nella pagina: `video:"ID_YOUTUBE"` (o link YouTube, o URL .mp4).

## Modificare i testi
Ogni passo: `{t:"titolo", d:"testo scritto", h:"elemento", solo:"completo", v:"testo parlato"}`.
`h` collega il passo al numero giallo sulla schermata (attributo `data-h`).
`solo:"completo"` = visibile solo a chi ha permesso completo.

## Nascondere sempre una pagina
In `index.html`: `const CONFIG = { escludi: ["utenti"] };`
