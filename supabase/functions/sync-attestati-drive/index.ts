// Edge Function "sync-attestati-drive"
//
// Chiamata da un Database Webhook su documenti_volontario (INSERT, DELETE).
// Copia gli attestati su Google Drive (tramite la Web App Apps Script) e li
// cestina quando vengono rimossi dall'app.
//
// Segreti (supabase secrets set): WEBHOOK_SECRET, APPS_SCRIPT_SECRET, APPS_SCRIPT_URL.
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY sono forniti dalla piattaforma.
// Deploy con --no-verify-jwt: la protezione è l'header x-webhook-secret.
//
// Ogni esito finisce in log_attivita (SYNC_DRIVE_OK / SYNC_DRIVE_ERRORE).
// Il lavoro vero gira in background (EdgeRuntime.waitUntil) e la risposta al
// webhook è immediata: un errore di sync non blocca mai l'app.
//
// Backfill una tantum: POST {"backfill": true} (stesso header x-webhook-secret).
// Collega gli attestati senza drive_file_id ai PDF già presenti nella cartella
// ATTESTATI dell'edizione, abbinandoli per dimensione in byte. Nessuna scrittura
// su Drive. Con {"backfill": true, "dryRun": true} mostra il risultato senza salvare.

import { createClient } from "npm:@supabase/supabase-js@2.117.2";

const BUCKET = "volontari-documenti";
const DURATA_URL_FIRMATO = 600; // 10 minuti
const UTENTE_LOG = "sync-attestati-drive";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

type Riga = Record<string, unknown> & { id?: number };
type Payload = {
  type?: string;
  table?: string;
  record?: Riga | null;
  old_record?: Riga | null;
  backfill?: boolean;
  dryRun?: boolean;
};
type FileDrive = { id: string; name: string; size: number };

Deno.serve(async (req) => {
  const segreto = Deno.env.get("WEBHOOK_SECRET");
  if (!segreto || req.headers.get("x-webhook-secret") !== segreto) {
    return json({ ok: false, error: "non autorizzato" }, 401);
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch (err) {
    await log("SYNC_DRIVE_ERRORE", null, null, { evento: "PAYLOAD", errore: "payload non valido: " + messaggio(err) });
    return json({ ok: false, error: "payload non valido" });
  }

  // Backfill: lanciato a mano, risponde con il riepilogo (sincrono)
  if (payload.backfill === true) {
    try {
      return json({ ok: true, ...(await backfill(payload.dryRun === true)) });
    } catch (err) {
      await log("SYNC_DRIVE_ERRORE", null, null, { evento: "BACKFILL", errore: messaggio(err) });
      return json({ ok: false, error: messaggio(err) });
    }
  }

  const lavoro = gestisci(payload).catch((err) =>
    log("SYNC_DRIVE_ERRORE", payload.record?.id ?? payload.old_record?.id ?? null, payload.old_record ?? null, {
      evento: payload.type,
      errore: messaggio(err),
    })
  );
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(lavoro);
  else await lavoro;

  return json({ ok: true, ricevuto: payload.type ?? null });
});

async function gestisci(p: Payload) {
  if (p.type === "INSERT" && p.record?.tipo === "attestato" && (!p.table || p.table === "documenti_volontario")) {
    return await suInserimento(p.record);
  }
  if (p.type === "DELETE" && p.old_record?.tipo === "attestato" && (!p.table || p.table === "documenti_volontario")) {
    return await suEliminazione(p.old_record);
  }
  // Evento che non riguarda un attestato (es. certificato medico): nessuna azione, ma lo registro
  const riga = p.record ?? p.old_record ?? null;
  await log("SYNC_DRIVE_OK", riga?.id ?? null, p.old_record ?? null, {
    evento: p.type ?? null,
    tabella_evento: p.table ?? null,
    tipo_documento: riga?.tipo ?? null,
    esito: "ignorato: non è un attestato su documenti_volontario",
  });
}

/* ---------- INSERT: carica su Drive ---------- */
async function suInserimento(doc: Riga) {
  const docId = doc.id ?? null;
  if (!doc.iscrizione_id) throw new Error("attestato senza iscrizione_id");
  if (!doc.storage_path) throw new Error("attestato senza storage_path");

  const { data: isc, error: errIsc } = await sb
    .from("iscrizioni_corsi")
    .select("id, edizione_corso_id, volontario_id")
    .eq("id", doc.iscrizione_id)
    .single();
  if (errIsc) throw new Error("iscrizione: " + errIsc.message);

  const { data: ed, error: errEd } = await sb
    .from("edizioni_corso")
    .select("id, label, sede, data_corso, drive_cartella_attestati_id, catalogo_corsi(codice)")
    .eq("id", isc.edizione_corso_id)
    .single();
  if (errEd) throw new Error("edizione: " + errEd.message);

  const { data: vol, error: errVol } = await sb
    .from("volontari_formazione")
    .select("cognome, nome, codice_fiscale")
    .eq("id", doc.volontario_id ?? isc.volontario_id)
    .single();
  if (errVol) throw new Error("volontario: " + errVol.message);

  const { data: firmato, error: errUrl } = await sb.storage
    .from(BUCKET)
    .createSignedUrl(String(doc.storage_path), DURATA_URL_FIRMATO);
  if (errUrl) throw new Error("URL firmato: " + errUrl.message);

  const fileName = nomeFileDrive(vol, String(doc.nome_file ?? doc.storage_path));
  const richiesta: Record<string, unknown> = { action: "upload", fileUrl: firmato.signedUrl, fileName };
  if (ed.drive_cartella_attestati_id) {
    richiesta.folderId = ed.drive_cartella_attestati_id;
  } else {
    if (!ed.data_corso) throw new Error(`edizione ${ed.id} senza data_corso e senza cartella Drive`);
    richiesta.anno = String(ed.data_corso).slice(0, 4);
    richiesta.nomeCorso = nomeCartellaCorso(ed);
  }

  const esito = await chiamaAppsScript(richiesta);

  // Prima volta per questa edizione: memorizzo la cartella ATTESTATI creata/trovata
  if (!ed.drive_cartella_attestati_id && esito.folderId) {
    const { error } = await sb
      .from("edizioni_corso")
      .update({ drive_cartella_attestati_id: esito.folderId })
      .eq("id", ed.id)
      .is("drive_cartella_attestati_id", null);
    if (error) throw new Error(`file caricato (${esito.fileId}), ma cartella non salvata sull'edizione: ${error.message}`);
  }

  const { error: errAgg } = await sb.from("documenti_volontario").update({ drive_file_id: esito.fileId }).eq("id", docId);
  if (errAgg) throw new Error(`file caricato (${esito.fileId}), ma drive_file_id non salvato: ${errAgg.message}`);

  await log("SYNC_DRIVE_OK", docId, null, {
    evento: "INSERT",
    drive_file_id: esito.fileId,
    drive_cartella_id: esito.folderId,
    nome_file_drive: fileName,
    edizione: ed.label,
  });
}

/* ---------- DELETE: cestina su Drive ---------- */
async function suEliminazione(vecchio: Riga) {
  const docId = vecchio.id ?? null;
  if (vecchio.drive_file_id) {
    await chiamaAppsScript({ action: "trash", fileId: vecchio.drive_file_id });
    await log("SYNC_DRIVE_OK", docId, vecchio, { evento: "DELETE", cestinato: vecchio.drive_file_id });
    return;
  }

  // Attestato mai collegato: provo l'abbinamento per dimensione nella cartella dell'edizione
  const trovato = await cercaPerDimensione(vecchio);
  if (!trovato.fileId) {
    await log("SYNC_DRIVE_ERRORE", docId, vecchio, {
      evento: "DELETE",
      errore: `documento senza drive_file_id, da rimuovere a mano: ${trovato.motivo}`,
    });
    return;
  }
  await chiamaAppsScript({ action: "trash", fileId: trovato.fileId });
  await log("SYNC_DRIVE_OK", docId, vecchio, {
    evento: "DELETE",
    cestinato: trovato.fileId,
    abbinamento: `per dimensione (${trovato.size} byte)`,
  });
}

// Dimensione da old_record se presente; altrimenti dallo storage, se il file
// non è ancora stato rimosso (l'app cancella prima la riga e poi il file).
async function cercaPerDimensione(vecchio: Riga): Promise<{ fileId?: string; size?: number; motivo: string }> {
  let size = numero(vecchio.dimensione_bytes) ?? numero(vecchio.size);
  if (size === null && vecchio.storage_path) {
    size = await dimensioneStorage(String(vecchio.storage_path), new Map());
  }
  if (size === null) return { motivo: "dimensione non disponibile (file già rimosso dallo storage)" };
  if (!vecchio.iscrizione_id) return { motivo: "attestato senza iscrizione_id" };

  const { data: isc, error: errIsc } = await sb
    .from("iscrizioni_corsi").select("edizione_corso_id").eq("id", vecchio.iscrizione_id).maybeSingle();
  if (errIsc) return { motivo: "iscrizione: " + errIsc.message };
  if (!isc) return { motivo: "iscrizione non trovata" };
  const { data: ed, error: errEd } = await sb
    .from("edizioni_corso").select("drive_cartella_attestati_id").eq("id", isc.edizione_corso_id).maybeSingle();
  if (errEd) return { motivo: "edizione: " + errEd.message };
  if (!ed?.drive_cartella_attestati_id) return { motivo: "edizione senza cartella Drive" };

  const liberi = await fileDriveNonCollegati(String(ed.drive_cartella_attestati_id));
  const stessi = liberi.filter((f) => f.size === size);
  if (stessi.length !== 1) return { size, motivo: `${stessi.length} file su Drive con dimensione ${size} byte` };
  return { fileId: stessi[0].id, size, motivo: "" };
}

/* ---------- BACKFILL: collega i file già presenti su Drive ---------- */
async function backfill(dryRun: boolean) {
  const { data: edizioni, error } = await sb
    .from("edizioni_corso")
    .select("id, label, drive_cartella_attestati_id")
    .not("drive_cartella_attestati_id", "is", null)
    .order("id");
  if (error) throw new Error("edizioni: " + error.message);

  const cacheCartelle = new Map<string, Promise<Map<string, number>>>();
  const perEdizione = [];
  for (const ed of edizioni ?? []) perEdizione.push(await backfillEdizione(ed, dryRun, cacheCartelle));

  const totali = {
    collegati: perEdizione.reduce((n, e) => n + e.collegati, 0),
    ambigui: perEdizione.reduce((n, e) => n + e.ambigui.length, 0),
    senza_corrispondenza: perEdizione.reduce((n, e) => n + e.senza_corrispondenza.length, 0),
    errori: perEdizione.reduce((n, e) => n + e.errori.length, 0),
  };
  await log(totali.errori ? "SYNC_DRIVE_ERRORE" : "SYNC_DRIVE_OK", null, null, {
    evento: "BACKFILL",
    dryRun,
    totali,
    per_edizione: perEdizione.map((e) => ({
      edizione: e.edizione,
      collegati: e.collegati,
      ambigui: e.ambigui.length,
      senza_corrispondenza: e.senza_corrispondenza.length,
      errori: e.errori.length,
    })),
  });
  return { dryRun, totali, edizioni: perEdizione };
}

// deno-lint-ignore no-explicit-any
async function backfillEdizione(ed: any, dryRun: boolean, cacheCartelle: Map<string, Promise<Map<string, number>>>) {
  const esito = {
    edizione: ed.label as string,
    edizione_id: ed.id as number,
    gia_collegati: 0,
    collegati: 0,
    ambigui: [] as Record<string, unknown>[],
    senza_corrispondenza: [] as Record<string, unknown>[],
    errori: [] as string[],
    file_drive_non_abbinati: 0,
  };

  const { data: iscrizioni, error: errIsc } = await sb.from("iscrizioni_corsi").select("id").eq("edizione_corso_id", ed.id);
  if (errIsc){ esito.errori.push("iscrizioni: " + errIsc.message); return esito; }
  if (!iscrizioni?.length) return esito;

  const { data: documenti, error: errDoc } = await sb
    .from("documenti_volontario")
    .select("id, nome_file, storage_path, drive_file_id")
    .eq("tipo", "attestato")
    .in("iscrizione_id", iscrizioni.map((i) => i.id));
  if (errDoc){ esito.errori.push("documenti: " + errDoc.message); return esito; }

  const daCollegare = (documenti ?? []).filter((d) => !d.drive_file_id);
  esito.gia_collegati = (documenti ?? []).length - daCollegare.length;
  if (daCollegare.length === 0) return esito;

  // File della cartella non ancora collegati a nessun documento
  const liberi = await fileDriveNonCollegati(String(ed.drive_cartella_attestati_id));

  // Dimensione di ogni attestato dallo storage (metadata.size di storage.objects)
  const conDimensione = await Promise.all(daCollegare.map(async (d) => {
    try {
      return { doc: d, size: await dimensioneStorage(String(d.storage_path), cacheCartelle) };
    } catch (err) {
      return { doc: d, size: null, errore: messaggio(err) };
    }
  }));

  const filePerDimensione = raggruppa(liberi, (f) => f.size);
  const docPerDimensione = raggruppa(conDimensione.filter((x) => x.size !== null), (x) => x.size as number);
  const fileUsati = new Set<string>();

  for (const { doc, size, errore } of conDimensione as { doc: Riga; size: number | null; errore?: string }[]) {
    const descr = { documento_id: doc.id, nome_file: doc.nome_file, size };
    if (size === null) {
      esito.errori.push(`documento ${doc.id} (${doc.nome_file}): ${errore ?? "dimensione non trovata nello storage"}`);
      continue;
    }
    const candidati = filePerDimensione.get(size) ?? [];
    const stessaDimensione = docPerDimensione.get(size) ?? [];
    if (candidati.length === 0) {
      esito.senza_corrispondenza.push(descr);
    } else if (candidati.length > 1 || stessaDimensione.length > 1) {
      esito.ambigui.push({
        ...descr,
        motivo: candidati.length > 1
          ? `${candidati.length} file su Drive con la stessa dimensione`
          : `${stessaDimensione.length} attestati con la stessa dimensione`,
        candidati: candidati.map((f) => f.name),
      });
    } else {
      const file = candidati[0];
      if (!dryRun) {
        const { error } = await sb
          .from("documenti_volontario")
          .update({ drive_file_id: file.id })
          .eq("id", doc.id)
          .is("drive_file_id", null);
        if (error){ esito.errori.push(`documento ${doc.id}: ${error.message}`); continue; }
      }
      fileUsati.add(file.id);
      esito.collegati++;
    }
  }
  esito.file_drive_non_abbinati = liberi.filter((f) => !fileUsati.has(f.id)).length;
  return esito;
}

// PDF della cartella che non risultano già collegati a un documento
async function fileDriveNonCollegati(folderId: string): Promise<FileDrive[]> {
  const risposta = await chiamaAppsScript({ action: "list", folderId });
  const files = ((risposta as { files?: FileDrive[] }).files ?? []).map((f) => ({ ...f, size: Number(f.size) }));
  if (files.length === 0) return [];
  const { data: collegati, error } = await sb
    .from("documenti_volontario")
    .select("drive_file_id")
    .in("drive_file_id", files.map((f) => f.id));
  if (error) throw new Error("documenti già collegati: " + error.message);
  const usati = new Set((collegati ?? []).map((r) => r.drive_file_id));
  return files.filter((f) => !usati.has(f.id));
}

// Dimensione in byte di un oggetto dello storage, via list() della sua cartella
// (restituisce metadata.size di storage.objects). La cache evita list ripetute.
async function dimensioneStorage(path: string, cache: Map<string, Promise<Map<string, number>>>) {
  const i = path.lastIndexOf("/");
  const cartella = i >= 0 ? path.slice(0, i) : "";
  const nome = path.slice(i + 1);
  if (!cache.has(cartella)) {
    cache.set(cartella, (async () => {
      const mappa = new Map<string, number>();
      for (let da = 0; ; da += 1000) {
        const { data, error } = await sb.storage.from(BUCKET).list(cartella, { limit: 1000, offset: da });
        if (error) throw new Error(`storage list "${cartella}": ${error.message}`);
        for (const o of data ?? []) {
          const s = numero(o.metadata?.size);
          if (s !== null) mappa.set(o.name, s);
        }
        if (!data || data.length < 1000) return mappa;
      }
    })());
  }
  return (await cache.get(cartella)!).get(nome) ?? null;
}

/* ---------- Apps Script ---------- */
// La Web App risponde con un 302 verso script.googleusercontent.com: il POST
// è già stato eseguito, il risultato si legge seguendo il redirect con una GET.
async function chiamaAppsScript(richiesta: Record<string, unknown>) {
  const url = Deno.env.get("APPS_SCRIPT_URL");
  const segreto = Deno.env.get("APPS_SCRIPT_SECRET");
  if (!url || !segreto) throw new Error("APPS_SCRIPT_URL o APPS_SCRIPT_SECRET non configurati");

  let resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...richiesta, secret: segreto }),
    redirect: "manual",
  });
  if (resp.status >= 300 && resp.status < 400) {
    const location = resp.headers.get("location");
    await resp.body?.cancel();
    if (!location) throw new Error(`Apps Script: redirect ${resp.status} senza Location`);
    resp = await fetch(location, { method: "GET" });
  }

  const testo = await resp.text();
  if (!resp.ok) throw new Error(`Apps Script: HTTP ${resp.status}`);
  let esito: { ok?: boolean; error?: string; fileId?: string; folderId?: string };
  try {
    esito = JSON.parse(testo);
  } catch {
    throw new Error("Apps Script: risposta non JSON (" + testo.slice(0, 120) + ")");
  }
  if (!esito.ok) throw new Error("Apps Script: " + (esito.error ?? "errore sconosciuto"));
  return esito;
}

/* ---------- Nomi ---------- */
// "COGNOME NOME_CODICEFISCALE.pdf", come l'export degli attestati.
// L'estensione segue il file originale (l'app accetta anche immagini); di default .pdf.
function nomeFileDrive(vol: { cognome?: string; nome?: string; codice_fiscale?: string }, nomeOriginale: string) {
  const chi = `${(vol.cognome ?? "").trim()} ${(vol.nome ?? "").trim()}`.toUpperCase().trim();
  const cf = (vol.codice_fiscale ?? "SENZA_CF").toUpperCase().trim();
  const est = (nomeOriginale.match(/\.([a-z0-9]{2,5})$/i)?.[1] ?? "pdf").toLowerCase();
  return `${chi}_${cf}`.replace(/[<>:"/\\|?*\x00-\x1f]/g, "_").replace(/\s+/g, " ").trim() + "." + est;
}

// "FORM_CAP_NNN_MM-AA CODICE SEDE", es. "FORM_CAP_009_12-25 SF02 ALESSANDRIA"
// NNN = numero nella label (es. "FORM_CAP_09 -12/25" → 009), MM-AA da data_corso.
// deno-lint-ignore no-explicit-any
function nomeCartellaCorso(ed: any) {
  const numero = String(ed.label ?? "").match(/FORM_CAP_?(\d+)/i)?.[1] ?? String(ed.label ?? "").match(/(\d+)/)?.[1];
  if (!numero) throw new Error(`label edizione "${ed.label}" senza numero corso`);
  const [anno, mese] = String(ed.data_corso).split("-");
  const codice = (Array.isArray(ed.catalogo_corsi) ? ed.catalogo_corsi[0] : ed.catalogo_corsi)?.codice ?? "";
  return [`FORM_CAP_${numero.padStart(3, "0")}_${mese}-${anno.slice(2)}`, codice, String(ed.sede ?? "").toUpperCase()]
    .map((s) => s.trim())
    .filter(Boolean)
    .join(" ");
}

/* ---------- Utility ---------- */
// Una riga in log_attivita per ogni esecuzione. operazione = SYNC_DRIVE_OK | SYNC_DRIVE_ERRORE
// (richiede che il CHECK log_attivita_operazione_check ammetta questi due valori).
// record_id è text. Se l'insert fallisce non si può loggare sul DB: l'errore completo
// va nei log della funzione (Dashboard → Functions → sync-attestati-drive → Logs).
async function log(operazione: "SYNC_DRIVE_OK" | "SYNC_DRIVE_ERRORE", recordId: unknown, prima: unknown, dopo: unknown) {
  const riga = {
    utente_email: UTENTE_LOG,
    tabella: "documenti_volontario",
    operazione,
    record_id: recordId === null || recordId === undefined ? null : String(recordId),
    dati_prima: prima ?? null,
    dati_dopo: dopo ?? null,
  };
  try {
    const { error } = await sb.from("log_attivita").insert(riga);
    if (error) {
      console.error("LOG_ATTIVITA_NON_SCRITTO", JSON.stringify({
        codice: error.code, messaggio: error.message, dettagli: error.details, suggerimento: error.hint, riga,
      }));
    }
  } catch (err) {
    console.error("LOG_ATTIVITA_NON_SCRITTO", messaggio(err), JSON.stringify(riga));
  }
}

function numero(v: unknown): number | null {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? n : null;
}

function raggruppa<T>(elenco: T[], chiave: (x: T) => number) {
  const mappa = new Map<number, T[]>();
  for (const x of elenco) {
    const k = chiave(x);
    mappa.set(k, [...(mappa.get(k) ?? []), x]);
  }
  return mappa;
}

function messaggio(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

function json(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
}
