/* =====================================================================
   CONTENUTI DELLA GUIDA
   - Ogni pagina ha: id (uguale alla route dell'app), titolo, icona,
     perche (una frase), chi (chi la vede), video (ID YouTube o URL mp4),
     audio (URL mp3, facoltativo: se vuoto si usa la lettura automatica),
     schermo (finta schermata) e passi.
   - Ogni passo: t = titolo, d = testo, h = elemento della schermata da
     indicare (data-h), solo = "completo" (nascosto con ?profilo=base)
     oppure "admin" (nascosto per tutti tranne ?profilo=admin).
   ===================================================================== */

const SIDEBAR = [
  ["home","ti-home","Home"],["automezzi","ti-truck","Automezzi"],["tlc","ti-radio","TLC / Radio"],
  ["formazione","ti-school","Formazione"],["firma","ti-signature","Firma Documenti"],
  ["editorpdf","ti-file-pencil","Editor PDF"],["libromatricola","ti-book","Libro Matricola"],
  ["esercitazioni","ti-flag","Esercitazioni"],["emergenze","ti-alert-triangle","Emergenze"],
  ["utenti","ti-users","Gestione Utenti"],["impostazioni","ti-settings","Impostazioni"]
];

function app(attiva, titolo, corpo){
  return `<div class="m-app">
    <aside class="m-side" data-h="menu">
      <div class="m-brand"><img src="icon-192.png" alt="">Polo Logistico</div>
      ${SIDEBAR.map(([r,i,l]) => `<div class="m-voce${r===attiva?' on':''}"><i class="ti ${i}"></i>${l}</div>`).join("")}
      <div class="m-voce m-esci" data-h="esci"><i class="ti ti-logout"></i>Esci</div>
    </aside>
    <main class="m-main"><div class="m-head"><b>${titolo}</b><span class="m-av">MR</span></div><div class="m-body">${corpo}</div></main>
  </div>`;
}
const btn = (txt, h, cl="") => `<span class="m-btn ${cl}"${h?` data-h="${h}"`:""}>${txt}</span>`;
const cerca = (ph, h) => `<span class="m-cerca"${h?` data-h="${h}"`:""}><i class="ti ti-search"></i>${ph}</span>`;
const sel = (txt, h) => `<span class="m-sel"${h?` data-h="${h}"`:""}>${txt} ▾</span>`;
const tabs = (arr, h) => `<div class="m-tabs"${h?` data-h="${h}"`:""}>${arr.map((t,i)=>`<span class="${i===0?'on':''}">${t}</span>`).join("")}</div>`;
const tab = (righe, h) => `<table class="m-tab"${h?` data-h="${h}"`:""}><tr>${righe[0].map(c=>`<th>${c}</th>`).join("")}</tr>${righe.slice(1).map(r=>`<tr>${r.map(c=>`<td>${c}</td>`).join("")}</tr>`).join("")}</table>`;
const tag = (t, c) => `<span class="m-tag ${c}">${t}</span>`;

const PAGINE = [
{
  id:"benvenuto", titolo:"Benvenuto", icona:"ti-hand-finger",
  perche:"Cos'è l'app del Polo Logistico, chi la usa e come funziona questa guida.",
  chi:"Tutti, da qui si parte.",
  video:"", audio:"",
  intro:"Ciao, e benvenuto. In pochi minuti ti spiego come funziona l'app del Polo Logistico di Vercelli, quella che usiamo come Coordinamento delle Sezioni piemontesi e come primo Raggruppamento per la protezione civile.",
  schermo: () => app("home","Home", `
    <div class="m-griglia2">
      <div class="m-box" data-h="cosa"><div class="m-box-t">Cosa trovi nell'app</div>
        <div class="m-riga">🚐 Mezzi e Libro Matricola</div><div class="m-riga">📻 Radio e materiale TLC</div>
        <div class="m-riga">🎓 Corsi e attestati</div><div class="m-riga">✍️ Documenti da firmare</div><div class="m-riga">🏕️ Esercitazioni ed emergenze</div></div>
      <div class="m-box" data-h="guida"><div class="m-box-t">Come leggere questa guida</div>
        <div class="m-riga"><span class="m-pin finto">1</span> numeri gialli sulla schermata</div><div class="m-riga">▶ spiegazione a voce</div><div class="m-riga">🖨 versione da stampare</div></div>
    </div>`),
  passi:[
    {t:"A cosa serve", d:"Un unico posto per mezzi, radio, formazione, documenti, esercitazioni ed emergenze del Polo Logistico.", h:"cosa",
     v:"L'idea è semplice: avere in un unico posto tutto quello che passa dal Polo. I mezzi e le loro scadenze, le radio che escono e rientrano, i corsi con gli attestati, i documenti da firmare, e le adesioni delle Sezioni a esercitazioni ed emergenze. Niente più fogli Excel che girano per mail."},
    {t:"Il menu", d:"Le sezioni sono tutte nel menu a sinistra. Dal telefono si apre con il pulsante ☰ in alto.", h:"menu",
     v:"Tutte le sezioni le trovi nel menu a sinistra, sempre nello stesso posto. Se sei dal telefono il menu è nascosto: lo apri toccando il pulsante con le tre righe, in alto."},
    {t:"Ognuno vede la sua parte", d:"Vedi solo le sezioni per cui hai il permesso. Con permesso base consulti, con permesso completo puoi anche modificare.", h:"menu",
     v:"Una cosa importante: non tutti vedono tutto. Ognuno ha i suoi permessi, sezione per sezione. Con il permesso base puoi guardare e consultare, con quello completo puoi anche inserire e modificare. Quindi se a un collega compare una voce che a te manca, è normale: se ti serve, chiedi all'amministratore."},
    {t:"Come usare la guida", d:"Una pagina per ogni sezione: tocca i numeri gialli sulla schermata, o premi Ascolta per sentire la spiegazione.", h:"guida",
     v:"Questa guida segue lo stesso ordine del menu. In ogni pagina trovi una schermata di esempio con dei numeri gialli: toccali e ti dico a cosa serve quel pulsante. Oppure fai come adesso, premi Ascolta e lasciati accompagnare. Partiamo dall'inizio: come si entra."}
  ]
},
{
  id:"accesso", titolo:"Accesso", icona:"ti-login",
  perche:"Come entrare nell'app, cosa fare se dimentichi la password, e come averla sul telefono.",
  chi:"Tutti gli utenti.",
  video:"", audio:"",
  intro:"Vediamo come si entra. È la parte più semplice, ma ci sono un paio di cose da sapere che evitano tante telefonate.",
  schermo: () => `<div class="m-login"><div class="m-login-card">
      <img src="icon-192.png" alt=""><div class="m-login-t" data-h="indirizzo">Polo Logistico 1 RGPT/CAP</div><small>Gestionale Operativo</small>
      <div class="m-login-campo" data-h="credenziali"><label>Email</label><span>mario.rossi@email.it</span><label>Password</label><span>••••••••••</span></div>
      <span class="m-btn largo" data-h="accedi">Accedi</span>
      <span class="m-link" data-h="dimenticata">Password dimenticata?</span>
    </div></div>`,
  passi:[
    {t:"L'indirizzo", d:"L'app si apre dal browser su polologistico.coordanapiemonte.it, da computer o telefono.", h:"indirizzo",
     v:"L'app non si scarica da nessuno store: si apre dal browser, sia dal computer che dal telefono, all'indirizzo polologistico punto coordanapiemonte punto it."},
    {t:"Email e password", d:"Usa l'email e la password che ti ha dato l'amministratore.", h:"credenziali",
     v:"Qui scrivi la tua email e la password. Le credenziali non te le crei da solo: te le dà l'amministratore."},
    {t:"Accedi", d:"Premi Accedi. Al primo accesso il menu può essere vuoto: vuol dire che l'amministratore deve ancora darti i permessi.", h:"accedi",
     v:"Premi Accedi e sei dentro. Se è la prima volta e vedi il menu praticamente vuoto, non hai sbagliato niente: vuol dire solo che l'amministratore non ti ha ancora abilitato le sezioni. Avvisalo e ci pensa lui."},
    {t:"Password dimenticata", d:"Scrivi la tua email nel campo, poi premi Password dimenticata?: ti arriva una mail per sceglierne una nuova.", h:"dimenticata",
     v:"Se non ricordi la password, scrivi prima la tua email nel campo in alto, e solo dopo premi Password dimenticata. Ti arriva una mail con il link per sceglierne una nuova. Se non la vedi, guarda anche nella posta indesiderata."},
    {t:"Non resti collegato", d:"Per sicurezza l'app non ricorda l'accesso: se ricarichi la pagina o la riapri, devi rientrare.", h:"accedi",
     v:"Ultima cosa, e questa è importante. Per sicurezza l'app non ti tiene collegato. Ogni volta che la riapri, e anche se ricarichi la pagina, ti chiede di nuovo email e password. Quindi, se stai compilando qualcosa, non ricaricare la pagina prima di aver salvato."},
    {t:"Sul telefono come un'app", d:"Dal menu del browser scegli Aggiungi a schermata Home: avrai l'icona del Polo come un'app normale.", h:"indirizzo",
     v:"Un consiglio per il telefono: dal menu del browser scegli Aggiungi a schermata Home. Ti compare l'icona del Polo tra le altre app, e la apri con un tocco."}
  ]
},
{
  id:"home", titolo:"Home", icona:"ti-home",
  perche:"La prima pagina dopo l'accesso: ti mostra subito cosa è scaduto e cosa è in giro.",
  chi:"Tutti gli utenti.",
  video:"", audio:"",
  intro:"Eccoci nella Home, la pagina che ti si apre appena entri. È fatta per darti in un colpo d'occhio le cose urgenti.",
  schermo: () => app("home","Home", `
    <div class="m-griglia2">
      <div class="m-box" data-h="scadenze"><div class="m-box-t">🚐 Scadenze Automezzi</div>
        <div class="m-riga">${tag("Scaduto","r")} AB123CD · Revisione</div>
        <div class="m-riga">${tag("In avvicinamento","g")} CD456EF · Assicurazione</div>
        <div class="m-riga">${tag("In avvicinamento","g")} EF789GH · Revisione</div></div>
      <div class="m-box" data-h="radio"><div class="m-box-t">📻 Radio attualmente in uso</div>
        <div class="m-riga">TLC0012 · Portatile · Sez. Vercelli</div>
        <div class="m-riga">TLC0031 · Veicolare · Sez. Asti</div></div>
    </div>
    <div class="m-azioni">${btn("📄 Report revisioni scadute/in scadenza","report","scuro")}</div>`),
  passi:[
    {t:"Il menu a sinistra", d:"Qui trovi tutte le sezioni dell'app. Vedi solo quelle per cui hai il permesso: se ti manca una voce, chiedi all'amministratore.", h:"menu",
     v:"A sinistra c'è il menu con le sezioni. Te lo ricordo: vedi solo quelle per cui hai il permesso."},
    {t:"Scadenze dei mezzi", d:"In rosso quello che è già scaduto, in giallo quello che scade a breve: revisioni, assicurazioni e altre scadenze dei mezzi.", h:"scadenze",
     v:"Questo riquadro è il più importante. Ti mostra le scadenze dei mezzi: revisioni, assicurazioni e così via. In rosso quello che è già scaduto, in giallo quello che scade a breve. Se è tutto pulito, meglio così."},
    {t:"Radio in uso", d:"L'elenco degli apparati radio consegnati e non ancora rientrati, con la Sezione che li ha in carico.", h:"radio",
     v:"Qui a fianco vedi le radio che in questo momento sono fuori, consegnate e non ancora rientrate, con la Sezione che le ha in carico. Comodo per sapere dove sono senza chiedere in giro."},
    {t:"Report revisioni", d:"Scarica in PDF l'elenco delle revisioni scadute o in scadenza.", h:"report",
     v:"Con questo pulsante scarichi un PDF con l'elenco delle revisioni scadute o in scadenza."},
    {t:"Uscire", d:"Per sicurezza l'app non ti tiene collegato: ogni volta che la riapri devi rientrare con email e password. Quando hai finito premi Esci.", h:"esci",
     v:"E quando hai finito, premi Esci, in fondo al menu. Soprattutto se sei su un computer che usano anche altri."}
  ]
},
{
  id:"automezzi", titolo:"Automezzi", icona:"ti-truck",
  perche:"L'anagrafica dei mezzi del Polo: scheda, foto, documenti, manutenzioni e uscite.",
  chi:"Chi ha il permesso Automezzi.",
  video:"", audio:"",
  intro:"Passiamo agli Automezzi. Qui c'è l'anagrafica completa dei mezzi del Polo: per ognuno la scheda, le foto, i documenti, le manutenzioni e le uscite.",
  schermo: () => app("automezzi","Automezzi", `
    <div class="m-barra">${cerca("Cerca per targa…","cerca")}${sel("Tutte le categorie","filtri")}${sel("Tutte le posizioni")}${sel("Tutti i proprietari")}
      <span class="m-sp"></span>${btn("🗑️ Mezzi dismessi","dismessi","grigio")}${btn("+ Nuovo mezzo","nuovo")}</div>
    <div class="m-card3" data-h="card">
      <div class="m-card"><div class="m-foto">🚐</div><b>AB123CD</b><small>Fiat Ducato · 9 posti</small>${tag("Operativo","v")}</div>
      <div class="m-card"><div class="m-foto">🚚</div><b>CD456EF</b><small>Iveco Daily · cassonato</small>${tag("In Manutenzione","g")}</div>
      <div class="m-card"><div class="m-foto">🚙</div><b>EF789GH</b><small>Land Rover Defender</small>${tag("Operativo","v")}</div>
    </div>
    <div class="m-modale">${tabs(["Scheda","Foto","Documenti","Manutenzioni","Movimentazioni"],"schede")}
      <div class="m-campi"><span>Targa <b>AB123CD</b></span><span>Scadenza revisione <b>12/03/2027</b></span><span>Frequenza <b>Ogni 2 anni</b></span><span>Stato <b>Operativo</b></span></div></div>`),
  passi:[
    {t:"Trovare un mezzo", d:"Scrivi la targa, anche solo una parte: l'elenco si filtra mentre scrivi.", h:"cerca",
     v:"Per trovare un mezzo, scrivi la targa qui. Basta anche solo un pezzo: l'elenco si restringe mentre scrivi."},
    {t:"Filtri", d:"Restringi l'elenco per categoria, posizione o proprietario.", h:"filtri",
     v:"Questi menu a tendina servono a filtrare: per categoria, per posizione, oppure per proprietario."},
    {t:"Le schede dei mezzi", d:"Ogni riquadro è un mezzo, con il suo stato: Operativo, In Manutenzione o Dismesso. Cliccalo per aprire la scheda.", h:"card",
     v:"Ogni riquadro è un mezzo. Sotto vedi subito lo stato: operativo, in manutenzione o dismesso. Clicca sul riquadro e si apre la scheda."},
    {t:"Dentro la scheda", d:"Scheda: i dati e le scadenze. Foto: le foto per lato del mezzo. Documenti: libretto, polizze e altro. Manutenzioni: interventi con officina, data e costo. Movimentazioni: uscite e rientri con autista, destinazione e chilometri.", h:"schede",
     v:"La scheda è divisa in schede più piccole, in alto. In Scheda trovi i dati e le scadenze. In Foto le foto del mezzo, lato per lato. In Documenti il libretto e le altre carte. In Manutenzioni gli interventi, con officina, data e costo. E in Movimentazioni le uscite e i rientri, con autista, destinazione e chilometri."},
    {t:"Aggiungere un mezzo", d:"Con + Nuovo mezzo inserisci targa e dati principali. La targa è obbligatoria.", h:"nuovo", solo:"completo",
     v:"Se hai il permesso completo, con Nuovo mezzo ne aggiungi uno. L'unico dato obbligatorio è la targa, il resto puoi completarlo dopo."},
    {t:"Mezzi dismessi", d:"I mezzi non più in uso non si cancellano: finiscono qui, così resta lo storico.", h:"dismessi",
     v:"I mezzi che non usiamo più non si cancellano: finiscono tra i mezzi dismessi. Così lo storico resta, e si può sempre andare a vedere."}
  ]
},
{
  id:"tlc", titolo:"TLC / Radio", icona:"ti-radio",
  perche:"Inventario di radio e materiale telecomunicazioni, con consegne e rientri firmati.",
  chi:"Chi ha il permesso TLC. Con permesso base si consulta ma non si registrano consegne.",
  video:"", audio:"",
  intro:"Adesso la sezione T L C, cioè radio e materiale per le telecomunicazioni. Qui si tiene l'inventario e, soprattutto, si registra ogni consegna e ogni rientro, con le firme.",
  schermo: () => app("tlc","TLC / Radio", `
    <div class="m-barra">${cerca("Cerca per codice, selettiva, marca, modello…","cerca")}${sel("Tutte le categorie","filtri")}${sel("Tutte le marche")}
      <span class="m-sp"></span>${btn("📊 Esporta Excel","excel","grigio")}${btn("📋 Movimentazioni","movim","scuro")}${btn("+ Nuovo apparato","nuovo")}</div>
    <div class="m-card3" data-h="card">
      <div class="m-card"><div class="m-foto">📻</div><b>TLC0012</b><small>RADIO · Portatile · Motorola</small>${tag("IN USO","g")}</div>
      <div class="m-card"><div class="m-foto">📻</div><b>TLC0013</b><small>RADIO · Veicolare · Hytera</small>${tag("RIENTRATO","v")}</div>
      <div class="m-card"><div class="m-foto">🔌</div><b>TLC0040</b><small>ALIMENTATORE</small>${tag("Non assegnato","n")}</div>
    </div>
    <div class="m-modale" data-h="consegna"><div class="m-box-t">Nuova movimentazione TLC</div>
      <div class="m-campi"><span>Apparati <b>(2 selezionati)</b></span><span>Ricevente <b>Mario Rossi</b></span><span>Sezione <b>ANA Vercelli</b></span><span>Tipo firma <b>Digitale (mouse/touch)</b></span></div>
      <div class="m-firma">firma del ricevente</div>
      <div class="m-azioni">${btn("Salva e genera bolla","bolla")}</div></div>`),
  passi:[
    {t:"Cercare un apparato", d:"Cerca per codice ANA (TLC0001…), selettiva, marca o modello.", h:"cerca",
     v:"Per cercare un apparato puoi scrivere il codice ANA, quello che inizia con T L C, oppure la selettiva, la marca o il modello."},
    {t:"Filtri", d:"Filtra per categoria (Radio, Rete, Antenna, Alimentatore…) o per marca.", h:"filtri",
     v:"Con questi filtri restringi per categoria, per esempio solo le radio o solo gli alimentatori, oppure per marca."},
    {t:"Gli apparati", d:"Ogni riquadro mostra codice, categoria e stato: IN USO se è stato consegnato, RIENTRATO se è tornato al Polo.", h:"card",
     v:"Ogni riquadro è un apparato. Guarda lo stato: in uso vuol dire che è fuori, consegnato a qualcuno. Rientrato vuol dire che è tornato al Polo."},
    {t:"Nuovo apparato", d:"Se lasci vuoto il Codice ANA, l'app lo assegna da sola con il numero successivo.", h:"nuovo", solo:"completo",
     v:"Quando inserisci un apparato nuovo, il codice ANA puoi anche lasciarlo vuoto: l'app assegna da sola il numero successivo, così non rischi doppioni."},
    {t:"Consegnare il materiale", d:"Da Movimentazioni → + Nuova movimentazione: scegli gli apparati, scrivi nome e Sezione di chi li riceve.", h:"movim", solo:"completo",
     v:"Veniamo alla parte che si usa di più: la consegna. Vai in Movimentazioni e premi Nuova movimentazione. Scegli gli apparati che escono, e scrivi nome e Sezione di chi li riceve."},
    {t:"Le firme", d:"Chi riceve firma sullo schermo (Digitale) oppure su carta (Autografa: stampi, fai firmare e ricarichi la scansione). La tua firma di consegna è quella personale salvata in Impostazioni.", h:"consegna", solo:"completo",
     v:"Poi le firme. Chi riceve può firmare direttamente sullo schermo, col dito o col mouse. Oppure, se preferisci la carta, scegli firma autografa: stampi, fai firmare, e poi carichi la scansione. La tua firma di consegna invece la mette l'app, perché è quella personale che hai salvato nelle Impostazioni."},
    {t:"La bolla", d:"Salva e genera bolla crea il PDF della consegna e lo archivia. Al ritorno usa Registra rientro: firmi la ripresa in carico e l'apparato torna RIENTRATO.", h:"bolla", solo:"completo",
     v:"Premi Salva e genera bolla: l'app crea il PDF della consegna e lo archivia. Quando il materiale torna, apri la movimentazione e premi Registra rientro. Firmi la ripresa in carico, e gli apparati tornano rientrati."},
    {t:"Esportare l'inventario", d:"Scarica tutto l'inventario in Excel.", h:"excel",
     v:"E se ti serve l'inventario completo, questo pulsante lo scarica in Excel."}
  ]
},
{
  id:"formazione", titolo:"Formazione", icona:"ti-school",
  perche:"Corsi, edizioni, volontari iscritti e attestati, collegati al Drive della formazione.",
  chi:"Chi ha il permesso Formazione.",
  video:"", audio:"",
  intro:"Ora la Formazione. Qui gestiamo i corsi, cioè le varie edizioni, chi le ha frequentate e gli attestati.",
  schermo: () => app("formazione","Formazione", `
    <div class="m-barra">${cerca("Cerca per nome edizione…","cerca")}<span class="m-sp"></span>${btn("🔍 Cerca volontari","volontari","grigio")}${btn("📊 Report formazione","report","grigio")}${btn("⚠️ Verifica attestati mancanti","mancanti","rosso")}${btn("+ Nuova edizione corso","nuova")}</div>
    ${tab([["Edizione","Corso","Data","Iscritti","Attestati"],["Base PC – Vercelli 2026","BASE","14/03/2026","32","30"],["Motoseghe – Asti","MOT","02/05/2026","18","18"],["Radio – Torino","TLC","21/09/2026","25","12"]],"elenco")}
    <div class="m-modale">${tabs(["Dati","Volontari","Documenti"],"schede")}
      <div class="m-azioni">${btn("+ Aggiungi volontario","","grigio")}${btn("📦 Import massivo attestati","zip","scuro")}${btn("📥 Scarica Excel","","grigio")}</div></div>`),
  passi:[
    {t:"Le edizioni dei corsi", d:"Ogni riga è un'edizione di un corso, con data, iscritti e quanti attestati sono già caricati.", h:"elenco",
     v:"In questo elenco ogni riga è un'edizione di un corso. Vedi la data, quanti erano iscritti e quanti attestati sono già stati caricati. Se i due numeri non tornano, manca qualcosa."},
    {t:"Creare un'edizione", d:"+ Nuova edizione corso: scegli il corso dal catalogo, dai un nome all'edizione e inserisci data e sede.", h:"nuova", solo:"completo",
     v:"Per creare un'edizione premi Nuova edizione corso. Scegli il corso dal catalogo, gli dai un nome, e inserisci data e sede."},
    {t:"Dentro l'edizione", d:"Dati: le informazioni del corso. Volontari: chi è iscritto, presente o assente, e il suo attestato. Documenti: i collegamenti alle cartelle Drive di attestati e scansioni, e l'elenco iscritti in PDF o Excel.", h:"schede",
     v:"Dentro l'edizione trovi tre schede. Dati, con le informazioni del corso. Volontari, con gli iscritti, chi era presente e chi no, e l'attestato di ognuno. E Documenti, con i collegamenti alle cartelle su Drive, e l'elenco degli iscritti da scaricare in PDF o in Excel."},
    {t:"Caricare tanti attestati insieme", d:"Import massivo attestati: carichi un file ZIP con un PDF per volontario. Ogni file deve avere nel nome il codice fiscale: l'app lo abbina da sola all'iscritto giusto.", h:"zip", solo:"completo",
     v:"Questa è la funzione che fa risparmiare più tempo. Se hai tutti gli attestati in PDF, li metti in un unico file zip e li carichi in un colpo solo. L'unica regola: nel nome di ogni file deve esserci il codice fiscale del volontario. L'app lo legge e abbina ogni attestato alla persona giusta."},
    {t:"Attestati su Drive", d:"Ogni attestato caricato viene copiato in automatico nella cartella ATTESTATI dell'edizione sul Drive condiviso. Non devi fare nulla.", h:"zip",
     v:"E non devi preoccuparti del Drive: ogni attestato che carichi viene copiato da solo nella cartella attestati dell'edizione, sul Drive condiviso della formazione."},
    {t:"Cosa manca", d:"Verifica attestati mancanti ti mostra chi ha frequentato ma non ha ancora l'attestato.", h:"mancanti",
     v:"Con Verifica attestati mancanti vedi subito chi ha frequentato ma non ha ancora l'attestato caricato."},
    {t:"Volontari e report", d:"Cerca volontari apre l'anagrafica con lo storico dei corsi di ognuno. Report formazione riassume tutto ed esporta in Excel.", h:"volontari",
     v:"Infine, con Cerca volontari apri la scheda di una persona, con tutti i corsi che ha fatto. E il Report formazione ti dà il quadro generale, anche in Excel."}
  ]
},
{
  id:"firma", titolo:"Firma Documenti", icona:"ti-signature",
  perche:"Per firmare al volo un PDF qualsiasi con la tua firma salvata.",
  chi:"Chi ha il permesso Firma Documenti.",
  video:"", audio:"",
  intro:"Firma Documenti è la sezione più veloce di tutte: serve a firmare al volo un PDF qualsiasi.",
  schermo: () => app("firma","Firma Documenti", `
    <div class="m-griglia-firma">
      <div class="m-box" data-h="libreria"><div class="m-box-t">Libreria firme</div><div class="m-firma pic">Mario Rossi</div><small>Clicca per usarla</small></div>
      <div class="m-pdf" data-h="pdf"><div class="m-pdf-righe"></div><div class="m-firma sopra" data-h="posiziona">firma</div></div>
    </div>
    <div class="m-azioni">${btn("Carica PDF","carica","grigio")}${btn("⬇️ Scarica PDF firmato","scarica")}</div>`),
  passi:[
    {t:"Carica il PDF", d:"Scegli il documento da firmare dal tuo computer o telefono.", h:"carica",
     v:"Prima carichi il documento, dal computer o dal telefono."},
    {t:"Scegli la firma", d:"Prendi una firma dalla libreria, oppure caricane una nuova.", h:"libreria",
     v:"Poi scegli la firma dalla libreria. Se non ce l'hai ancora, la carichi qui."},
    {t:"Posizionala", d:"La firma compare sul documento: trascinala nel punto giusto e allarga o stringi il riquadro.", h:"posiziona",
     v:"La firma compare sopra il documento, dentro un riquadro. La trascini dove serve, e la allarghi o la stringi tirando gli angoli."},
    {t:"Scarica", d:"Scarica PDF firmato salva il documento con la firma ormai fissata nel PDF.", h:"scarica",
     v:"Quando è al posto giusto, premi Scarica PDF firmato. La firma viene fissata dentro il file, e quel PDF lo puoi mandare a chi vuoi."}
  ]
},
{
  id:"editorpdf", titolo:"Editor PDF", icona:"ti-file-pencil",
  perche:"Moduli PDF da compilare e far firmare, anche a persone esterne tramite un link.",
  chi:"Chi ha il permesso Editor PDF. I modelli si gestiscono solo con permesso completo.",
  video:"", audio:"",
  intro:"L'Editor PDF è un passo avanti rispetto alla semplice firma. Serve per i moduli che usiamo spesso: si compilano, e si fanno firmare, anche da chi non ha accesso all'app.",
  schermo: () => app("editorpdf","Editor PDF", `
    ${tabs(["Documenti","Modelli","Libreria","Registro"],"schede")}
    <div class="m-barra">${cerca("Cerca per titolo…")}<span class="m-sp"></span>${btn("+ Nuovo documento","nuovo")}</div>
    ${tab([["Titolo","Modello","Stato","Aggiornato il"],["Consegna DPI – Rossi","Consegna DPI",tag("In firma","g"),"28/10/2026"],["Verbale ritiro","Verbale",tag("Firmato","v"),"25/10/2026"],["Bozza autorizzazione","Autorizzazione",tag("Bozza","n"),"24/10/2026"]],"stati")}
    <div class="m-modale" data-h="link"><div class="m-box-t">Link di firma per esterni</div><div class="m-campi"><span>Campo <b>Firma del genitore</b></span><span>Link <b>firma.html?t=••••••</b></span></div><small>Copialo ora: viene mostrato una volta sola.</small></div>`),
  passi:[
    {t:"Le quattro schede", d:"Documenti: i moduli compilati. Modelli: i moduli vuoti da riusare. Libreria: firme, sigle, timbri e loghi. Registro: chi ha fatto cosa e quando.", h:"schede",
     v:"In alto hai quattro schede. Documenti, con i moduli già compilati. Modelli, con i moduli vuoti pronti da riusare. Libreria, con firme, sigle, timbri e loghi. E Registro, dove resta scritto chi ha fatto cosa, e quando."},
    {t:"Nuovo documento", d:"Scegli un modello: l'app riempie da sola i dati che conosce (volontario, apparato, data, utente). Tu completi il resto.", h:"nuovo",
     v:"Per compilare un modulo premi Nuovo documento e scegli il modello. Molti dati li riempie l'app da sola, per esempio il nome del volontario, l'apparato, la data o chi sta compilando. A te resta solo il resto."},
    {t:"Gli stati", d:"Bozza mentre lo prepari, In firma quando aspetta qualcuno, Firmato quando è completo. Un documento sbagliato si annulla, non si cancella.", h:"stati",
     v:"Guarda la colonna stato. Bozza, mentre lo stai preparando. In firma, quando aspetta la firma di qualcuno. Firmato, quando è completo. E se un documento è sbagliato non si cancella: si annulla, così resta traccia."},
    {t:"Far firmare un esterno", d:"Per un campo firma esterno crei un link e lo mandi alla persona. Il link si vede una volta sola e vale per una sola firma: se lo perdi, ne crei uno nuovo e quello vecchio smette di funzionare.", h:"link",
     v:"Se deve firmare una persona esterna, per esempio un genitore o un fornitore, crei un link e glielo mandi. Lei apre il link, firma dal telefono, e il documento si aggiorna da solo. Attenzione però: il link lo vedi una volta sola, quindi copialo subito. E vale per una sola firma. Se lo perdi, ne crei uno nuovo, e quello vecchio smette di funzionare."},
    {t:"Creare modelli", d:"Nella scheda Modelli carichi un PDF vuoto e disegni sopra i campi: testo, data, casella, firma.", h:"schede", solo:"completo",
     v:"Se hai il permesso completo, nella scheda Modelli prepari i moduli: carichi un PDF vuoto e ci disegni sopra i campi, cioè testo, data, casella o firma."},
    {t:"Il registro", d:"Ogni salvataggio, firma, link aperto o annullamento resta scritto nel Registro, esportabile in Excel.", h:"schede",
     v:"E nel Registro resta tutto: ogni salvataggio, ogni firma, ogni link aperto o annullato. Se serve, lo esporti in Excel."}
  ]
},
{
  id:"libromatricola", titolo:"Libro Matricola", icona:"ti-book",
  perche:"L'elenco dei mezzi assicurati di tutte le Sezioni, con premi, polizze e CAI.",
  chi:"Chi ha il permesso Libro Matricola.",
  video:"", audio:"",
  intro:"Il Libro Matricola è l'elenco dei mezzi assicurati di tutte le Sezioni, con i premi, le polizze e i C A I.",
  schermo: () => app("libromatricola","Libro Matricola", `
    <div class="m-barra">${cerca("Cerca per targa, descrizione…","cerca")}<span class="m-sp"></span>${btn("📊 Esporta tutto (Excel)","export","grigio")}${btn("📄 Esporta tutto (PDF)","","grigio")}${btn("📁 Esporta per sezione","sezione","scuro")}${btn("+ Nuovo mezzo","nuovo")}</div>
    ${tab([["Targa/Telaio","Descrizione bene","Sezione","Data incl.","Premio RC"],["AB123CD","Fiat Ducato","ANA VERCELLI","01/01/2026","€ ···"],["CD456EF","Rimorchio","ANA ASTI","15/02/2026","€ ···"],["EF789GH","Land Rover","ANA CUNEO","01/01/2026","€ ···"]],"elenco")}
    <div class="m-modale">${tabs(["Dati","Documenti"],"schede")}<div class="m-campi"><span>Polizza <b>AB123CD.PDF</b></span><span>CAI <b>AB123CD_CAI.PDF</b></span></div></div>`),
  passi:[
    {t:"L'elenco", d:"Un mezzo per riga, raggruppati per Sezione, con data di inclusione e premi.", h:"elenco",
     v:"Ogni riga è un mezzo, con la Sezione a cui appartiene, la data di inclusione e i premi."},
    {t:"Cercare", d:"Cerca per targa, numero di telaio o descrizione.", h:"cerca",
     v:"Per trovarne uno, cerca per targa, per numero di telaio, oppure per descrizione."},
    {t:"La scheda del mezzo", d:"Dati: premi RC e Tutela Legale, conguagli, date di inclusione ed esclusione. Documenti: polizza e CAI in PDF.", h:"schede",
     v:"Nella scheda del mezzo trovi due parti. In Dati i premi di responsabilità civile e tutela legale, i conguagli, e le date di inclusione ed esclusione. In Documenti la polizza e il C A I, in PDF."},
    {t:"Esportare", d:"Esporta tutto in Excel o PDF per l'assicurazione.", h:"export",
     v:"Quando serve mandare tutto all'assicurazione, esporti l'intero libro in Excel o in PDF."},
    {t:"Per le Sezioni", d:"Esporta per sezione prepara un file per ogni Sezione, con solo i suoi mezzi.", h:"sezione",
     v:"Se invece devi mandare a ogni Sezione la sua parte, usa Esporta per sezione: l'app prepara un file per ciascuna, con solo i suoi mezzi."},
    {t:"Aggiungere o togliere un mezzo", d:"+ Nuovo mezzo per inserirlo. Quando esce dalla copertura, metti la data di esclusione: il mezzo passa tra i dismessi.", h:"nuovo", solo:"completo",
     v:"Per aggiungere un mezzo premi Nuovo mezzo. Quando invece esce dalla copertura, non lo cancelli: metti la data di esclusione, e passa tra i dismessi."}
  ]
},
{
  id:"esercitazioni", titolo:"Esercitazioni", icona:"ti-flag",
  perche:"Raccogli le adesioni delle Sezioni a un'esercitazione: volontari, pasti e pernotti.",
  chi:"Chi ha il permesso Esercitazioni. Con permesso base vedi i numeri ma non i dati personali.",
  video:"", audio:"",
  intro:"Le Esercitazioni. Questa sezione ha preso il posto del vecchio Excel delle presenze. Ogni Sezione inserisce da sola i suoi volontari, e tu hai sempre i numeri aggiornati, compresi pasti e pernotti.",
  schermo: () => app("esercitazioni","Esercitazioni", `
    <div class="m-barra">${cerca("Cerca per titolo o luogo…")}<span class="m-sp"></span>${btn("+ Nuova esercitazione","nuova")}</div>
    <div class="m-modale">${tabs(["Riepilogo","Volontari","Ospiti","Cucina","Sezioni"],"schede")}
      ${tab([["Sezione","Stato","Volontari","Link"],["ANA Vercelli",tag("Risposto","v"),"14",btn("📋 Copia link","","mini")],["ANA Asti",tag("In attesa","g"),"—",btn("✉️ Mail","","mini")],["ANA Biella",tag("Non partecipa","n"),"0",""]],"sezioni")}
      <div class="m-azioni">${btn("📥 Excel","excel","grigio")}${btn("🖨 Stampa","cucina","grigio")}</div></div>`),
  passi:[
    {t:"Creare l'esercitazione", d:"Titolo, luogo, date, scadenza delle adesioni e un referente. Scegli anche quali dati chiedere ai volontari: cellulare, patenti, abilitazioni, servizi, note.", h:"nuova", solo:"completo",
     v:"Per prima cosa crei l'esercitazione: titolo, luogo, date, entro quando si accettano le adesioni, e un referente. Poi scegli quali dati chiedere ai volontari. Cognome, nome e codice fiscale ci sono sempre. Il resto, come cellulare, patenti o abilitazioni, lo attivi solo se ti serve."},
    {t:"Invitare le Sezioni", d:"Nella scheda Sezioni scegli chi invitare, anche in blocco in base all'ente (CAP o 1° RGPT). Ogni Sezione ha il suo link: lo copi o lo mandi per mail.", h:"sezioni", solo:"completo",
     v:"Poi inviti le Sezioni. Le puoi scegliere una per una, oppure in blocco in base all'ente, Coordinamento o primo Raggruppamento. Ogni Sezione ha il suo link personale: lo copi, oppure lo mandi direttamente per mail."},
    {t:"Le Sezioni rispondono da sole", d:"Chi riceve il link compila senza password, dal browser o con il modello Excel. Qui vedi chi ha Risposto, chi è In attesa e chi Non partecipa.", h:"sezioni",
     v:"Da quel momento le Sezioni fanno da sole. Aprono il link, senza password, e inseriscono i loro volontari, anche caricando un Excel. Tu qui vedi chi ha risposto, chi è ancora in attesa, e chi ha detto che non partecipa."},
    {t:"Il cruscotto", d:"Riepilogo: i totali. Volontari: l'elenco degli iscritti. Ospiti: autorità e relatori aggiunti a mano. Cucina: pasti e pernotti per giorno, con le esigenze alimentari.", h:"schede",
     v:"Le schede in alto ti danno i numeri. Riepilogo, con i totali. Volontari, con l'elenco degli iscritti. Ospiti, dove aggiungi a mano autorità e relatori. E Cucina, con pasti e pernotti giorno per giorno, comprese le esigenze alimentari."},
    {t:"Per la cucina", d:"Stampa il foglio A4 della cucina con i coperti per servizio.", h:"cucina",
     v:"Per chi cucina c'è una stampa apposta: un foglio A4 con i coperti per ogni servizio."},
    {t:"Esportare", d:"Scarica tutto in Excel, con un foglio per ogni vista.", h:"excel",
     v:"E quando ti serve tutto insieme, lo scarichi in Excel, con un foglio per ogni vista."}
  ]
},
{
  id:"emergenze", titolo:"Emergenze", icona:"ti-alert-triangle",
  perche:"Raccogli dalle Sezioni chi è disponibile, in quali giorni, e con quali mezzi e materiali.",
  chi:"Chi ha il permesso Emergenze. Con permesso base vedi i numeri ma non i dati personali.",
  video:"", audio:"",
  intro:"Le Emergenze funzionano come le esercitazioni, con una differenza: qui non chiediamo chi viene a un evento, ma chi è disponibile, e in quali giorni.",
  schermo: () => app("emergenze","Emergenze", `
    <div class="m-barra"><span class="m-sp"></span>${btn("+ Nuova emergenza","nuova")}</div>
    <div class="m-modale">${tabs(["Riepilogo","Volontari","Mezzi e materiali","Sezioni"],"schede")}
      ${tab([["Giorno","Disponibili","Giornata intera","Con orario","Mezzi"],["Lun 02/11","38","30","8","6"],["Mar 03/11","41","35","6","7"],["Mer 04/11","22","20","2","4"]],"giorni")}
      <div class="m-campi" data-h="griglia"><span>Griglia dei giorni fino al <b>04/11/2026</b></span>${btn("✏️ Modifica","","mini")}</div></div>`),
  passi:[
    {t:"Aprire un'emergenza", d:"Funziona come un'esercitazione, ma la fine può restare aperta.", h:"nuova", solo:"completo",
     v:"Quando apri un'emergenza non serve sapere quando finirà: la data di fine può restare aperta."},
    {t:"I giorni", d:"La griglia dei giorni si può allungare man mano che l'emergenza continua.", h:"griglia", solo:"completo",
     v:"Si lavora con una griglia di giorni, e se l'emergenza va avanti la allunghi quanto serve."},
    {t:"Cosa compilano le Sezioni", d:"Per ogni volontario: i giorni di disponibilità (giornata intera o con orario), la tipologia e se chiede l'art. 39. In più l'elenco di mezzi e materiali che possono mandare.", h:"schede",
     v:"Le Sezioni, dal loro link, indicano per ogni volontario i giorni in cui c'è, tutto il giorno oppure in certi orari, la sua tipologia, e se chiede i benefici dell'articolo trentanove. E poi possono segnalare anche i mezzi e i materiali che sono in grado di mandare."},
    {t:"Il riepilogo per giorno", d:"Per ogni giorno vedi quanti sono disponibili, divisi per tipologia, patenti, abilitazioni e Sezione, e quanti mezzi.", h:"giorni",
     v:"Qui vedi il quadro giorno per giorno: quanti sono disponibili, divisi per tipologia, patenti, abilitazioni e Sezione, e quanti mezzi ci sono."},
    {t:"Art. 39", d:"Si registra solo la richiesta. I dati del datore di lavoro restano alla Sezione. Il dato è visibile solo con permesso completo.", h:"schede", solo:"completo",
     v:"Sull'articolo trentanove, una precisazione: qui si registra solo la richiesta. I dati del datore di lavoro restano alla Sezione. E il dato lo vede solo chi ha il permesso completo."}
  ]
},
{
  id:"utenti", titolo:"Gestione Utenti", icona:"ti-users",
  perche:"Chi può entrare nell'app e cosa può fare.",
  chi:"Solo l'amministratore IT.",
  video:"", audio:"",
  intro:"Questa pagina riguarda solo l'amministratore. È dove si decide chi può entrare, e cosa può fare.",
  schermo: () => app("utenti","Gestione Utenti", `
    ${tab([["Utente","Ruolo","Permessi","Attivo"],["Mario Rossi","standard","TLC base · Formazione completo","Sì"],["Laura Bianchi","segreteria","Esercitazioni completo","Sì"],["Paolo Verdi","specialita","TLC completo","No"]],"elenco")}
    <div class="m-modale" data-h="permessi"><div class="m-box-t">Permessi di Mario Rossi</div>
      <div class="m-campi"><span>Automezzi <b>—</b></span><span>TLC <b>base</b></span><span>Formazione <b>completo</b></span><span>Editor PDF <b>base</b></span></div>
      <div class="m-azioni">${btn("Resetta password","reset","grigio")}${btn("Salva")}</div></div>
    <div class="m-azioni">${btn("📋 Log accessi","log","scuro")}</div>`),
  passi:[
    {t:"Gli utenti", d:"Il primo accesso crea l'utente in automatico, senza permessi. Da qui lo abiliti.", h:"elenco", solo:"admin",
     v:"Quando una persona entra per la prima volta, l'app la aggiunge da sola a questo elenco, ma senza nessun permesso. Da qui la abiliti."},
    {t:"I permessi", d:"Per ogni sezione scegli: niente, base (consulta) o completo (modifica). L'utente vede nel menu solo le sezioni abilitate.", h:"permessi", solo:"admin",
     v:"Per ogni sezione scegli il livello: nessuno, base per consultare, oppure completo per modificare. L'utente vedrà nel menu solo le sezioni che gli hai abilitato."},
    {t:"Password dimenticata", d:"Resetta password manda all'utente una mail per sceglierne una nuova.", h:"reset", solo:"admin",
     v:"Se qualcuno ha perso la password, con Resetta password gli arriva una mail per sceglierne una nuova."},
    {t:"Log accessi", d:"Chi è entrato e quando.", h:"log", solo:"admin",
     v:"E nel Log accessi vedi chi è entrato, e quando."}
  ]
},
{
  id:"impostazioni", titolo:"Impostazioni", icona:"ti-settings",
  perche:"La tua password, la tua firma e le liste usate dalle altre sezioni.",
  chi:"Tutti per password e firma. Le liste solo con permesso completo sulla sezione.",
  video:"", audio:"",
  intro:"Nelle Impostazioni ci sono due cose che riguardano te, e poi le liste usate dalle altre sezioni.",
  schermo: () => app("impostazioni","Impostazioni", `
    <div class="m-griglia2">
      <div class="m-box" data-h="password"><div class="m-box-t">Cambia password</div><div class="m-campi"><span>Nuova password <b>••••••••</b></span><span>Conferma <b>••••••••</b></span></div>${btn("Salva password")}</div>
      <div class="m-box" data-h="firma"><div class="m-box-t">Firma personale</div><div class="m-firma pic">Mario Rossi</div>${btn("Salva firma")}</div>
    </div>
    <div class="m-box" data-h="liste"><div class="m-box-t">Liste ▾</div>
      <div class="m-riga">Categorie, marche e sottocategorie TLC</div><div class="m-riga">Patenti, abilitazioni, tipologie, esigenze alimentari</div><div class="m-riga">Mail PC delle Sezioni ANA (CAP / 1° RGPT)</div></div>`),
  passi:[
    {t:"Cambiare password", d:"Scrivi la nuova password due volte e salva.", h:"password",
     v:"Qui cambi la password. La scrivi due volte e salvi."},
    {t:"La tua firma", d:"Disegnala una volta: verrà usata nelle consegne TLC e nei documenti dell'Editor PDF. Ognuno può cambiare solo la propria.", h:"firma",
     v:"E qui c'è la tua firma personale. Vale la pena farla subito: la disegni una volta, e poi l'app la usa da sola nelle consegne delle radio e nei documenti dell'Editor PDF. Ognuno può cambiare solo la propria."},
    {t:"Le liste", d:"Le voci che compaiono nei menu a tendina delle altre sezioni. Se una voce manca qui, non si può scegliere né importare da Excel.", h:"liste", solo:"completo",
     v:"Più sotto ci sono le liste: categorie e marche delle radio, patenti, abilitazioni, esigenze alimentari, le mail delle Sezioni. Sono le voci che compaiono nei menu a tendina delle altre pagine. Se una voce manca qui, non la puoi scegliere da nessuna parte, e neanche importare da Excel."}
  ]
},
{
  id:"adesione", titolo:"Per le Sezioni: rispondere a un invito", icona:"ti-send",
  perche:"Hai ricevuto un link per un'esercitazione o un'emergenza: ecco come rispondere. Non servono password.",
  chi:"Le Sezioni ANA invitate.",
  video:"", audio:"",
  intro:"Questa pagina è per le Sezioni. Se hai ricevuto un link per un'esercitazione o un'emergenza, ti spiego come rispondere. Non servono password, e ci vogliono pochi minuti.",
  schermo: () => `<div class="m-app solo"><main class="m-main"><div class="m-head"><b>Esercitazione regionale 2026 · Adesione ANA Vercelli</b></div><div class="m-body">
    <div class="m-azioni">${btn("📥 Scarica modello","modello","grigio")}${btn("📤 Carica Excel","carica","grigio")}</div>
    ${tab([["Cognome","Nome","Codice fiscale","Servizi"],["Rossi","Mario","RSSMRA80A01L750X","Pranzo · Cena · Pernotto"],["Bianchi","Laura","BNCLRA85B41L750Y","Pranzo"]],"elenco")}
    <div class="m-azioni">${btn("+ Aggiungi volontario","aggiungi","grigio")}<span class="m-sp"></span>${btn("La Sezione non partecipa","no","grigio")}${btn("Invia adesione","salva")}</div></div></main></div>`,
  passi:[
    {t:"Aggiungere i volontari", d:"Per ognuno servono cognome, nome e codice fiscale. Gli altri campi dipendono da cosa chiede l'organizzatore.", h:"aggiungi",
     v:"Per ogni volontario premi Aggiungi volontario. Cognome, nome e codice fiscale servono sempre. Gli altri campi dipendono da cosa ha chiesto chi organizza."},
    {t:"Con Excel", d:"Se i volontari sono tanti, premi Scarica modello, compilalo e ricaricalo: la lista si riempie da sola. Poi controlla e salva.", h:"modello",
     v:"Se i volontari sono tanti, fai prima con Excel. Premi Scarica modello, lo compili, e poi lo ricarichi con Carica Excel: la lista si riempie da sola. Dai solo un'occhiata prima di inviare."},
    {t:"Pasti e pernotti", d:"Spunta i servizi per ogni giorno. Se spunti il pernotto, la colazione del giorno dopo si spunta da sola.", h:"elenco",
     v:"Poi spunti i pasti e i pernotti, giorno per giorno. Un dettaglio comodo: se spunti il pernotto, la colazione del giorno dopo si spunta da sola."},
    {t:"Inviare", d:"Premi Invia adesione. Puoi tornare sul link e modificare quante volte vuoi fino alla chiusura delle adesioni.", h:"salva",
     v:"Quando hai finito premi Invia adesione. E tranquillo: puoi riaprire lo stesso link e correggere quante volte vuoi, fino alla chiusura delle adesioni."},
    {t:"Se non partecipate", d:"Premi La Sezione non partecipa: così l'organizzatore sa che avete risposto.", h:"no",
     v:"Se invece la tua Sezione non partecipa, premi La Sezione non partecipa. Sembra una cosa da poco, ma così chi organizza sa che hai risposto, e non ti deve cercare."}
  ]
}
];
