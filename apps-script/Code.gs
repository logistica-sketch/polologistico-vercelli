/**
 * Sync attestati Polo Logistico — Web App chiamata dall'Edge Function
 * Supabase "sync-attestati-drive".
 *
 * Il segreto condiviso NON è nel codice: va inserito dall'editor in
 * Impostazioni progetto → Proprietà script → APPS_SCRIPT_SECRET.
 * Apps Script non espone gli header HTTP a doPost, quindi il segreto
 * arriva nel corpo JSON (campo "secret").
 *
 * Azioni (POST, corpo JSON):
 *   upload: { secret, action:"upload", fileUrl, fileName, folderId }
 *           oppure, senza folderId: { ..., anno, nomeCorso }
 *           → { ok:true, fileId, folderId }   (folderId = cartella ATTESTATI)
 *   trash:  { secret, action:"trash", fileId } → { ok:true, fileId }
 * GET → { ok:true } per verificare che il servizio sia online.
 */

// Cartella "01_CORSI": contiene <anno>/<nome corso>/{SCANSIONI, ATTESTATI}
const CARTELLA_CORSI_ID = "1h2kvQL2NW550Uyr4UW82QYt47F087lPQ";

function doGet() {
  return risposta_({ ok: true, servizio: "sync-attestati-polo-logistico" });
}

function doPost(e) {
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || "{}");

    const atteso = PropertiesService.getScriptProperties().getProperty("APPS_SCRIPT_SECRET");
    if (!atteso) return risposta_({ ok: false, error: "APPS_SCRIPT_SECRET non configurato nelle Proprietà script" });
    if (typeof body.secret !== "string" || body.secret !== atteso) return risposta_({ ok: false, error: "non autorizzato" });

    if (body.action === "upload") return risposta_(carica_(body));
    if (body.action === "trash") return risposta_(cestina_(body));
    return risposta_({ ok: false, error: "azione sconosciuta: " + body.action });
  } catch (err) {
    return risposta_({ ok: false, error: String((err && err.message) || err) });
  }
}

function carica_(body) {
  if (!body.fileUrl || !body.fileName) return { ok: false, error: "fileUrl e fileName obbligatori" };

  let cartella;
  if (body.folderId) {
    cartella = DriveApp.getFolderById(body.folderId);
  } else {
    if (!body.anno || !body.nomeCorso) return { ok: false, error: "senza folderId servono anno e nomeCorso" };
    cartella = cartellaAttestati_(String(body.anno), String(body.nomeCorso));
  }

  const resp = UrlFetchApp.fetch(body.fileUrl, { muteHttpExceptions: true, followRedirects: true });
  if (resp.getResponseCode() !== 200) {
    return { ok: false, error: "download del file non riuscito (HTTP " + resp.getResponseCode() + ")" };
  }
  const blob = resp.getBlob().setName(body.fileName);
  const file = cartella.createFile(blob);
  return { ok: true, fileId: file.getId(), folderId: cartella.getId() };
}

function cestina_(body) {
  if (!body.fileId) return { ok: false, error: "fileId obbligatorio" };
  DriveApp.getFileById(body.fileId).setTrashed(true); // cestino, mai cancellazione definitiva
  return { ok: true, fileId: body.fileId };
}

// 01_CORSI/<anno>/<nomeCorso>/ATTESTATI (crea ciò che manca, compresa SCANSIONI).
// Il lock evita cartelle doppie se arrivano più upload insieme per lo stesso corso.
function cartellaAttestati_(anno, nomeCorso) {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const radice = DriveApp.getFolderById(CARTELLA_CORSI_ID);
    const cartellaAnno = sottocartella_(radice, anno);
    const cartellaCorso = sottocartella_(cartellaAnno, nomeCorso);
    sottocartella_(cartellaCorso, "SCANSIONI");
    return sottocartella_(cartellaCorso, "ATTESTATI");
  } finally {
    lock.releaseLock();
  }
}

function sottocartella_(padre, nome) {
  const trovate = padre.getFoldersByName(nome);
  return trovate.hasNext() ? trovate.next() : padre.createFolder(nome);
}

function risposta_(oggetto) {
  return ContentService.createTextOutput(JSON.stringify(oggetto)).setMimeType(ContentService.MimeType.JSON);
}
