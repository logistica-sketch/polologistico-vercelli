/* ============================================================
   Esercitazioni ed emergenze – modello Excel da scaricare e ricaricare.
   Condiviso da adesione.html (Sezioni) e index.html (cruscotto admin).
   Usa ExcelJS (caricato da CDN solo quando serve) perché permette i menu
   a tendina (convalida dati). Nessun dato viene inviato: tutto nel browser.

   API (window.EsercitazioniExcel):
     scaricaModello(cfg)      → genera e scarica il file .xlsx
     leggiFile(file, cfg)     → { righe:[{ riga, volontario, errori[] }], erroriFile[] }
     htmlAnteprima(esito)     → tabella HTML (stili in linea) con gli errori riga per riga
   cfg = { titolo, tipoNome ("Esercitazione" | "Emergenza"), sezione, date, campi, patenti[], abilitazioni[],
           tipologie[], esigenze[], servizi[{id,giorno,tipo}], volontari[], maxVolontari }
   Gli orari delle giornate di disponibilità non sono nel modello: si indicano dalla pagina
   (un volontario caricato da Excel senza orari conserva quelli già salvati).
   ============================================================ */
(function(){
  "use strict";

  const EXCELJS_URL = "https://cdnjs.cloudflare.com/ajax/libs/exceljs/4.4.0/exceljs.min.js";
  const TIPI = ["disponibile", "colazione", "pranzo", "cena", "pernotto"];
  const LABEL_TIPO = { disponibile:"Disponibile", colazione:"Colazione", pranzo:"Pranzo", cena:"Cena", pernotto:"Pernotto" };
  // campi che, se assenti dalla configurazione, valgono "non richiesto" (come sul DB)
  const NON_RICHIESTI_SE_ASSENTI = ["esigenze", "tipologia", "art39", "orari", "mezzi", "materiali"];
  const LIVELLO_DEFAULT = "facoltativo";
  const RIGHE_MODELLO = 150;
  const FOGLIO = "Volontari";
  const FOGLIO_CODICI = "_codici";

  let caricamento = null;
  function caricaExcelJS(){
    if (window.ExcelJS) return Promise.resolve(window.ExcelJS);
    if (caricamento) return caricamento;
    caricamento = new Promise((ok, ko) => {
      const s = document.createElement("script");
      s.src = EXCELJS_URL;
      s.onload = () => window.ExcelJS ? ok(window.ExcelJS) : ko(new Error("Libreria Excel non disponibile."));
      s.onerror = () => { caricamento = null; ko(new Error("Impossibile caricare la libreria Excel: controlla la connessione.")); };
      document.head.appendChild(s);
    });
    return caricamento;
  }

  // come sul DB: un campo assente vale "facoltativo", tranne quelli in NON_RICHIESTI_SE_ASSENTI
  function livello(campi, k){ return (campi && campi[k]) || (NON_RICHIESTI_SE_ASSENTI.includes(k) ? "non_richiesto" : LIVELLO_DEFAULT); }

  function serviziOrdinati(cfg){
    return [...(cfg.servizi || [])].sort((a, b) => a.giorno.localeCompare(b.giorno) || TIPI.indexOf(a.tipo) - TIPI.indexOf(b.tipo));
  }
  function giornoPrima(iso){
    const d = new Date(iso + "T00:00:00Z");
    d.setUTCDate(d.getUTCDate() - 1);
    return d.toISOString().slice(0, 10);
  }
  function attivo(campi, k){ return livello(campi, k) !== "non_richiesto"; }
  function obbligatorio(campi, k){ return livello(campi, k) === "obbligatorio"; }

  function cfValido(cf){
    if (!/^[A-Z]{6}[0-9LMNPQRSTUV]{2}[ABCDEHLMPRST][0-9LMNPQRSTUV]{2}[A-Z][0-9LMNPQRSTUV]{3}[A-Z]$/.test(cf || "")) return false;
    const dispari = [1,0,5,7,9,13,15,17,19,21,2,4,18,20,11,3,6,8,12,14,16,10,22,25,24,23];
    let s = 0;
    for (let i = 0; i < 15; i++){
      const c = cf[i];
      const v = /[0-9]/.test(c) ? c.charCodeAt(0) - 48 : c.charCodeAt(0) - 65;
      s += (i % 2 === 0) ? dispari[v] : v;
    }
    return cf[15] === String.fromCharCode(65 + s % 26);
  }

  function etichettaGiorno(iso){
    const d = new Date(iso + "T00:00:00");
    const t = d.toLocaleDateString("it-IT", { weekday:"short", day:"2-digit", month:"2-digit" });
    return t.charAt(0).toUpperCase() + t.slice(1);
  }

  // Colonne del modello, in ordine: { chiave, titolo, tipo: testo|sino|lista, larghezza, valori? }
  function colonne(cfg){
    const c = cfg.campi || {};
    const stella = k => obbligatorio(c, k) ? " *" : "";
    const out = [
      { chiave:"cognome", titolo:"Cognome *", tipo:"testo", larghezza:22 },
      { chiave:"nome", titolo:"Nome *", tipo:"testo", larghezza:20 },
      { chiave:"codice_fiscale", titolo:"Codice fiscale *", tipo:"testo", larghezza:20 }
    ];
    if (attivo(c, "tipologia")) out.push({ chiave:"tipologia", titolo:"Tipologia" + stella("tipologia"), tipo:"lista", larghezza:16, valori:cfg.tipologie || [] });
    if (attivo(c, "cellulare")) out.push({ chiave:"cellulare", titolo:"Cellulare" + stella("cellulare"), tipo:"testo", larghezza:16 });
    if (attivo(c, "art39")) out.push({ chiave:"art39", titolo:"Chiede art. 39", tipo:"sino", larghezza:12 });
    if (attivo(c, "patenti")) (cfg.patenti || []).forEach(p => out.push({ chiave:"patente:" + p, titolo:"Patente " + p, tipo:"sino", larghezza:11 }));
    if (attivo(c, "abilitazioni")) (cfg.abilitazioni || []).forEach(p => out.push({ chiave:"abilitazione:" + p, titolo:p, tipo:"sino", larghezza:11 }));
    if (attivo(c, "servizi")) serviziOrdinati(cfg).forEach(s => out.push({ chiave:"servizio:" + s.id, titolo:`${etichettaGiorno(s.giorno)} ${LABEL_TIPO[s.tipo] || s.tipo}`, tipo:"sino", larghezza:14, servizio:s }));
    if (attivo(c, "esigenze")){
      (cfg.esigenze || []).forEach(e => out.push({ chiave:"esigenza:" + e.nome, titolo:e.nome + (e.con_nota ? " (scrivi nella nota)" : ""), tipo:"sino", larghezza:13 }));
      out.push({ chiave:"esigenze_note", titolo:"Nota esigenze alimentari", tipo:"testo", larghezza:28 });
    }
    if (attivo(c, "note")) out.push({ chiave:"note", titolo:"Note" + stella("note"), tipo:"testo", larghezza:30 });
    return out;
  }

  function valoreCella(col, v){
    const [tipo, chiave] = col.chiave.includes(":") ? col.chiave.split(/:(.*)/s) : [col.chiave, null];
    if (tipo === "patente") return (v.patenti || []).includes(chiave) ? "SI" : "NO";
    if (tipo === "abilitazione") return (v.abilitazioni || []).includes(chiave) ? "SI" : "NO";
    if (tipo === "esigenza") return (v.esigenze || []).includes(chiave) ? "SI" : "NO";
    if (tipo === "servizio") return (v.servizi || []).map(String).includes(chiave) ? "SI" : "NO";
    if (tipo === "art39") return v.art39 ? "SI" : "NO";
    return v[tipo] || "";
  }

  function letteraColonna(n){
    let s = "";
    while (n > 0){ const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
    return s;
  }

  async function scaricaModello(cfg){
    const ExcelJS = await caricaExcelJS();
    const cols = colonne(cfg);
    const wb = new ExcelJS.Workbook();
    wb.creator = "Polo Logistico 1° RGPT/CAP Vercelli";
    wb.created = new Date();

    // Foglio volontari
    const ws = wb.addWorksheet(FOGLIO, { views:[{ state:"frozen", ySplit:1 }] });
    ws.columns = cols.map(c => ({ header:c.titolo, key:c.chiave, width:c.larghezza }));
    const testa = ws.getRow(1);
    testa.font = { bold:true, color:{ argb:"FFFFFFFF" } };
    testa.alignment = { vertical:"middle", horizontal:"center", wrapText:true };
    testa.height = 32;
    testa.eachCell(cella => { cella.fill = { type:"pattern", pattern:"solid", fgColor:{ argb:"FF1D4E89" } }; });

    // Colazione del giorno X+1 collegata al pernotto della notte X (stessa regola dei moduli):
    // la cella ha una formula che segue il pernotto, ma si può sovrascrivere scegliendo SI/NO.
    const pernottoPrima = new Map(); // indice colonna colazione -> indice colonna pernotto della notte prima
    cols.forEach((c, i) => {
      if (!c.servizio || c.servizio.tipo !== "colazione") return;
      const j = cols.findIndex(x => x.servizio && x.servizio.tipo === "pernotto" && x.servizio.giorno === giornoPrima(c.servizio.giorno));
      if (j >= 0) pernottoPrima.set(i, j);
    });

    (cfg.volontari || []).forEach(v => ws.addRow(cols.map(c => valoreCella(c, v))));
    for (let r = 2; r <= RIGHE_MODELLO + 1; r++){
      const riga = ws.getRow(r);
      cols.forEach((c, i) => {
        const cella = riga.getCell(i + 1);
        if (c.tipo === "sino"){
          if (pernottoPrima.has(i)){
            const rifPernotto = `${letteraColonna(pernottoPrima.get(i) + 1)}${r}`;
            const regola = String(riga.getCell(pernottoPrima.get(i) + 1).value || "") === "SI" ? "SI" : "NO";
            const attuale = cella.value === null || cella.value === undefined || cella.value === "" ? regola : cella.value;
            // formula solo se il valore coincide con la regola (righe vuote o già coerenti)
            if (attuale === regola) cella.value = { formula:`IF(${rifPernotto}="SI","SI","NO")`, result:regola };
          }
          if (cella.value === null || cella.value === undefined || cella.value === "") cella.value = "NO";
          cella.alignment = { horizontal:"center" };
          cella.dataValidation = { type:"list", allowBlank:true, formulae:['"SI,NO"'], showErrorMessage:true,
                                   errorTitle:"Valore non valido", error:"Scegli SI oppure NO." };
        } else if (c.tipo === "lista"){
          if (c.valori.length) cella.dataValidation = { type:"list", allowBlank:true, formulae:[`"${c.valori.join(",")}"`], showErrorMessage:true,
                                                        errorTitle:"Valore non valido", error:"Scegli un valore dal menu." };
        } else {
          cella.numFmt = "@"; // testo: il CF non diventa un numero e gli zeri iniziali del cellulare restano
        }
      });
    }

    // Foglio istruzioni
    const ist = wb.addWorksheet("Istruzioni");
    ist.getColumn(1).width = 110;
    const righeIst = [
      [`${cfg.tipoNome || "Esercitazione"}: ${cfg.titolo || ""}`, true],
      [cfg.date ? `Date: ${cfg.date}` : "", false],
      [cfg.sezione ? `Sezione: ${cfg.sezione}` : "", false],
      ["", false],
      ["Come compilare", true],
      ["• Una riga per ogni volontario, nel foglio \"Volontari\". Non modificate la prima riga né l'ordine delle colonne.", false],
      ["• Le colonne con * sono obbligatorie. Cognome, nome e codice fiscale servono sempre.", false],
      ["• Codice fiscale: 16 caratteri, senza spazi.", false],
      ["• Nelle colonne con il menu a tendina scegliete SI oppure NO.", false],
      ...(attivo(cfg.campi, "tipologia") ? [["• Tipologia: sceglietela dal menu a tendina." + (obbligatorio(cfg.campi, "tipologia") ? " È obbligatoria." : ""), false]] : []),
      ...(attivo(cfg.campi, "servizi") && (cfg.servizi || []).some(s => s.tipo === "disponibile")
          ? [["• Disponibile: SI per ogni giornata in cui il volontario è disponibile." + (attivo(cfg.campi, "orari") ? " Gli eventuali orari si indicano dalla pagina, dopo il caricamento." : ""), false]] : []),
      ...(attivo(cfg.campi, "servizi") && (cfg.servizi || []).some(s => s.tipo !== "disponibile")
          ? [["• Pasti e pernotti: SI per ogni pasto o notte a cui il volontario partecipa.", false],
             ["• La colazione si imposta da sola a SI se il volontario pernotta la notte prima; potete comunque cambiarla.", false]] : []),
      ...(obbligatorio(cfg.campi, "servizi") ? [["• Almeno una giornata, un pasto o un pernotto è obbligatorio.", false]] : []),
      ...(attivo(cfg.campi, "art39") ? [["• Chiede art. 39: SI se il volontario chiede i benefici di legge per il datore di lavoro (i dati del datore li gestisce la Sezione).", false]] : []),
      ...(attivo(cfg.campi, "esigenze") ? [["• Esigenze alimentari: SI dove serve. Per allergie e \"altro\" scrivete il dettaglio nella colonna \"Nota esigenze alimentari\".", false]] : []),
      ...(obbligatorio(cfg.campi, "patenti") ? [["• Patenti: indicate SI per almeno una patente.", false]] : []),
      ...(obbligatorio(cfg.campi, "abilitazioni") ? [["• Abilitazioni: indicate SI per almeno un'abilitazione.", false]] : []),
      [`• Massimo ${cfg.maxVolontari || RIGHE_MODELLO} volontari.`, false],
      ["", false],
      ["Come inviare", true],
      ["1. Salvate il file e caricatelo dalla pagina delle adesioni con \"Carica Excel\".", false],
      ["2. Controllate l'anteprima: le righe con errori vengono segnalate e non sono caricate.", false],
      ["3. Premete \"Invia adesione\" per confermare. Caricare il file NON invia nulla da solo.", false]
    ];
    righeIst.forEach(([testo, grassetto]) => {
      const r = ist.addRow([testo]);
      r.getCell(1).alignment = { wrapText:true, vertical:"top" };
      if (grassetto) r.font = { bold:true, size:12 };
    });

    // Foglio nascosto con le chiavi delle colonne (per rileggere il file con certezza)
    const cod = wb.addWorksheet(FOGLIO_CODICI, { state:"veryHidden" });
    cod.addRow(cols.map(c => c.chiave));

    const buf = await wb.xlsx.writeBuffer();
    const blob = new Blob([buf], { type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
    const nome = `Adesione_${(cfg.sezione || "Sezione").replace(/[^a-zA-Z0-9]+/g, "_")}_${(cfg.titolo || "evento").replace(/[^a-zA-Z0-9]+/g, "_").slice(0, 40)}.xlsx`;
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = nome;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  function testoCella(cella){
    if (!cella) return "";
    const v = cella.value;
    if (v === null || v === undefined) return "";
    if (typeof v === "object"){
      if (v.richText) return v.richText.map(t => t.text).join("");
      if (v.text !== undefined) return String(v.text);
      if (v.result !== undefined) return String(v.result);
      if (v instanceof Date) return v.toISOString().slice(0, 10);
    }
    return String(v);
  }

  function siNo(testo){
    const t = String(testo || "").trim().toUpperCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    if (t === "" || t === "NO" || t === "N" || t === "0" || t === "FALSO" || t === "FALSE") return false;
    if (t === "SI" || t === "S" || t === "X" || t === "1" || t === "VERO" || t === "TRUE") return true;
    return null; // non riconosciuto
  }

  async function leggiFile(file, cfg){
    const ExcelJS = await caricaExcelJS();
    const wb = new ExcelJS.Workbook();
    try{
      await wb.xlsx.load(await file.arrayBuffer());
    }catch(e){
      return { righe:[], erroriFile:["Il file non è un Excel valido (.xlsx). Usate il modello scaricato da questa pagina."] };
    }
    const ws = wb.getWorksheet(FOGLIO) || wb.worksheets.find(w => w.state === "visible");
    if (!ws) return { righe:[], erroriFile:["Nel file non c'è il foglio \"Volontari\"."] };

    const attese = colonne(cfg);
    const perChiave = new Map(attese.map(c => [c.chiave, c]));
    const perTitolo = new Map(attese.map(c => [c.titolo.replace(/\s*\*$/, "").trim().toUpperCase(), c]));
    const erroriFile = [];

    // Mappa colonna → chiave: dal foglio nascosto se c'è, altrimenti dai titoli
    const mappa = [];
    const cod = wb.getWorksheet(FOGLIO_CODICI);
    const testa = ws.getRow(1);
    const nCol = Math.max(testa.cellCount, cod ? cod.getRow(1).cellCount : 0);
    for (let i = 1; i <= nCol; i++){
      const chiaveCod = cod ? testoCella(cod.getRow(1).getCell(i)).trim() : "";
      const titolo = testoCella(testa.getCell(i)).replace(/\s*\*$/, "").trim().toUpperCase();
      const col = (chiaveCod && perChiave.get(chiaveCod)) || perTitolo.get(titolo) || null;
      mappa[i] = col;
      if (!col && titolo) erroriFile.push(`Colonna "${testoCella(testa.getCell(i))}" non prevista per questo evento: viene ignorata.`);
    }
    ["cognome", "nome", "codice_fiscale"].forEach(k => {
      if (!mappa.some(c => c && c.chiave === k)) erroriFile.push(`Manca la colonna obbligatoria "${perChiave.get(k).titolo}".`);
    });
    if (erroriFile.some(e => e.startsWith("Manca"))) return { righe:[], erroriFile };

    const campi = cfg.campi || {};
    const righe = [];
    const cfVisti = new Map();
    for (let r = 2; r <= ws.rowCount; r++){
      const riga = ws.getRow(r);
      const val = {};
      let vuota = true;
      for (let i = 1; i <= nCol; i++){
        const col = mappa[i];
        if (!col) continue;
        const t = testoCella(riga.getCell(i)).trim();
        val[col.chiave] = t;
        if (t && col.tipo !== "sino") vuota = false;
        if (col.tipo === "sino" && siNo(t) === true) vuota = false;
      }
      if (vuota) continue;

      const errori = [];
      const v = {
        cognome: (val.cognome || "").toUpperCase(),
        nome: (val.nome || "").toUpperCase(),
        codice_fiscale: (val.codice_fiscale || "").replace(/[^A-Za-z0-9]/g, "").toUpperCase(),
        cellulare: attivo(campi, "cellulare") ? (val.cellulare || "") : "",
        note: attivo(campi, "note") ? ((val.note || "") || null) : null,
        esigenze_note: attivo(campi, "esigenze") ? ((val.esigenze_note || "") || null) : null,
        patenti: [], abilitazioni: [], servizi: [], esigenze: []
      };
      // tipologia e art. 39 solo se richiesti: se assenti, sul DB resta il valore già salvato
      if (attivo(campi, "tipologia")){
        const t = (val.tipologia || "").trim();
        const trovata = (cfg.tipologie || []).find(x => x.toUpperCase() === t.toUpperCase());
        v.tipologia = trovata || null;
        if (t && !trovata) errori.push(`tipologia "${t}" non prevista`);
        else if (!t && obbligatorio(campi, "tipologia")) errori.push("tipologia obbligatoria");
      }
      if (attivo(campi, "art39")) v.art39 = false;
      if (!v.cognome) errori.push("cognome mancante");
      if (!v.nome) errori.push("nome mancante");
      if (v.cognome.length > 80 || v.nome.length > 80) errori.push("cognome o nome troppo lungo");
      if (!v.codice_fiscale) errori.push("codice fiscale mancante");
      else if (!cfValido(v.codice_fiscale)) errori.push("codice fiscale non valido");
      else if (cfVisti.has(v.codice_fiscale)) errori.push(`codice fiscale ripetuto (riga ${cfVisti.get(v.codice_fiscale)})`);
      if (v.codice_fiscale) cfVisti.set(v.codice_fiscale, r);
      if (v.cellulare.length > 30) errori.push("cellulare troppo lungo");
      if (v.note && v.note.length > 500) errori.push("note troppo lunghe");

      Object.entries(val).forEach(([chiave, t]) => {
        const col = perChiave.get(chiave);
        if (!col || col.tipo !== "sino") return;
        const b = siNo(t);
        if (b === null){ errori.push(`"${col.titolo}": scrivere SI o NO`); return; }
        if (!b) return;
        const [tipo, k] = chiave.split(/:(.*)/s);
        if (tipo === "patente") v.patenti.push(k);
        else if (tipo === "abilitazione") v.abilitazioni.push(k);
        else if (tipo === "esigenza") v.esigenze.push(k);
        else if (tipo === "servizio") v.servizi.push(Number(k));
        else if (tipo === "art39") v.art39 = true;
      });
      if (v.esigenze_note && v.esigenze_note.length > 300) errori.push("nota esigenze troppo lunga");
      const conNota = (cfg.esigenze || []).filter(e => e.con_nota).map(e => e.nome);
      if (v.esigenze.some(e => conNota.includes(e)) && !v.esigenze_note) errori.push("descrivere l'esigenza alimentare nella nota");
      if (obbligatorio(campi, "cellulare") && !v.cellulare) errori.push("cellulare obbligatorio");
      if (obbligatorio(campi, "note") && !v.note) errori.push("note obbligatorie");
      if (obbligatorio(campi, "patenti") && !v.patenti.length) errori.push("indicare almeno una patente");
      if (obbligatorio(campi, "abilitazioni") && !v.abilitazioni.length) errori.push("indicare almeno un'abilitazione");
      if (obbligatorio(campi, "servizi") && !v.servizi.length) errori.push("indicare almeno una giornata, un pasto o un pernotto");

      righe.push({ riga:r, volontario:v, errori });
    }
    const max = cfg.maxVolontari || RIGHE_MODELLO;
    if (righe.length > max) erroriFile.push(`Il file contiene ${righe.length} volontari: il massimo è ${max}.`);
    if (!righe.length && !erroriFile.length) erroriFile.push("Il file non contiene volontari.");
    return { righe, erroriFile };
  }

  function esc(s){
    return String(s === null || s === undefined ? "" : s).replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]));
  }

  function htmlAnteprima(esito){
    const ok = esito.righe.filter(r => !r.errori.length).length;
    const ko = esito.righe.length - ok;
    const generali = esito.erroriFile.length
      ? `<div style="background:#fdecea;color:#c0392b;border-radius:8px;padding:10px 12px;font-size:13px;margin-bottom:10px;">${esito.erroriFile.map(esc).join("<br>")}</div>` : "";
    if (!esito.righe.length) return generali;
    return `${generali}
      <div style="font-size:13px;margin-bottom:8px;"><strong style="color:#2e7d32;">${ok} righe valide</strong>${ko ? ` · <strong style="color:#c0392b;">${ko} con errori (non verranno caricate)</strong>` : ""}</div>
      <div style="max-height:320px;overflow:auto;border:1px solid #e6e9ee;border-radius:8px;">
        <table style="width:100%;border-collapse:collapse;font-size:12.5px;">
          <thead><tr style="background:#f4f6f9;text-align:left;">
            <th style="padding:6px 8px;">Riga</th><th style="padding:6px 8px;">Volontario</th><th style="padding:6px 8px;">Esito</th>
          </tr></thead>
          <tbody>${esito.righe.map(r => `
            <tr style="border-top:1px solid #e6e9ee;${r.errori.length ? "background:#fdecea;" : ""}">
              <td style="padding:6px 8px;">${r.riga}</td>
              <td style="padding:6px 8px;"><strong>${esc(r.volontario.cognome)}</strong> ${esc(r.volontario.nome)}<br><span style="font-family:monospace;color:#8a93a3;">${esc(r.volontario.codice_fiscale)}</span></td>
              <td style="padding:6px 8px;color:${r.errori.length ? "#c0392b" : "#2e7d32"};">${r.errori.length ? esc(r.errori.join("; ")) : "OK"}</td>
            </tr>`).join("")}
          </tbody>
        </table>
      </div>`;
  }

  window.EsercitazioniExcel = { scaricaModello, leggiFile, htmlAnteprima, campoAttivo:attivo, campoObbligatorio:obbligatorio };
})();
