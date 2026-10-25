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
type Payload = { type?: string; table?: string; record?: Riga | null; old_record?: Riga | null };

Deno.serve(async (req) => {
  const segreto = Deno.env.get("WEBHOOK_SECRET");
  if (!segreto || req.headers.get("x-webhook-secret") !== segreto) {
    return json({ ok: false, error: "non autorizzato" }, 401);
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "payload non valido" });
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
  if (p.table && p.table !== "documenti_volontario") return;
  if (p.type === "INSERT" && p.record?.tipo === "attestato") return await suInserimento(p.record);
  if (p.type === "DELETE" && p.old_record?.tipo === "attestato") return await suEliminazione(p.old_record);
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
  if (!vecchio.drive_file_id) {
    await log("SYNC_DRIVE_ERRORE", docId, vecchio, {
      evento: "DELETE",
      errore: "documento senza drive_file_id: se il file è su Drive va rimosso a mano",
    });
    return;
  }
  await chiamaAppsScript({ action: "trash", fileId: vecchio.drive_file_id });
  await log("SYNC_DRIVE_OK", docId, vecchio, { evento: "DELETE", cestinato: vecchio.drive_file_id });
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
async function log(operazione: string, recordId: unknown, prima: unknown, dopo: unknown) {
  const { error } = await sb.from("log_attivita").insert({
    utente_email: UTENTE_LOG,
    tabella: "documenti_volontario",
    operazione,
    record_id: recordId,
    dati_prima: prima,
    dati_dopo: dopo,
  });
  if (error) console.error("log_attivita non scritto:", error.message, operazione, recordId);
}

function messaggio(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

function json(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
}
