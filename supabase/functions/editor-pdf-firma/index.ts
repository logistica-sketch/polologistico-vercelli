// =====================================================================
// Edge Function: editor-pdf-firma
// Link di firma monouso per l'Editor PDF del Polo Logistico.
//
// Azioni (POST JSON, campo "azione"):
//   crea    (utente collegato)  -> crea la richiesta e restituisce il link
//   revoca  (utente collegato)  -> annulla un link non ancora usato
//   apri    (pubblica, token)   -> dati per la pagina firma.html
//   firma   (pubblica, token)   -> scrive la firma nel PDF e brucia il token
//
// Deploy SENZA verifica JWT (le azioni pubbliche non hanno login):
//   config.toml ->  [functions.editor-pdf-firma]  verify_jwt = false
// Secret richiesto: PUBLIC_SITE_URL (es. https://polologistico.coordanapiemonte.it)
// =====================================================================

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SB_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SITE = (Deno.env.get("PUBLIC_SITE_URL") ?? "https://polologistico.coordanapiemonte.it").replace(/\/$/, "");
const BUCKET = "pdf-documenti";
const ORE_DEFAULT = 48;
const ORE_MAX = 168; // 7 giorni

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const admin = createClient(SB_URL, SB_SERVICE, { auth: { persistSession: false } });

// ---------- utilità ----------
async function sha256Hex(data: Uint8Array | string): Promise<string> {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const h = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function nuovoToken(): string {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const adesso = () =>
  new Intl.DateTimeFormat("it-IT", { timeZone: "Europe/Rome", dateStyle: "short", timeStyle: "short" }).format(new Date());
const safe = (s: string) => String(s).replace(/[^\x20-\x7E\xA0-\xFF]/g, "?");
function infoClient(req: Request) {
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;
  const ua = req.headers.get("user-agent")?.slice(0, 300) ?? null;
  return { ip, ua };
}
async function audit(r: Record<string, unknown>) {
  const { error } = await admin.from("pdf_audit").insert(r);
  if (error) console.error("audit", error);
}

// utente collegato con permesso editor_pdf
async function utenteAutorizzato(req: Request) {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;
  const c = createClient(SB_URL, SB_ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data } = await c.auth.getUser();
  if (!data?.user) return null;
  const { data: ok } = await c.rpc("ha_accesso", { chiave: "editor_pdf" });
  return ok ? data.user : null;
}

type Richiesta = {
  id: string; documento_id: string; campo_id: string; firmatario_nome: string;
  scade_il: string; aperto_il: string | null; usato_il: string | null; revocato_il: string | null;
};
async function trovaRichiesta(token: unknown): Promise<{ r?: Richiesta; err?: string }> {
  if (typeof token !== "string" || token.length < 30 || token.length > 100) return { err: "non_valido" };
  const { data: r } = await admin.from("pdf_firme_richieste").select("*").eq("token_hash", await sha256Hex(token)).maybeSingle();
  if (!r) return { err: "non_valido" };
  if (r.revocato_il) return { err: "revocato" };
  if (r.usato_il) return { err: "usato" };
  if (new Date(r.scade_il) < new Date()) return { err: "scaduto" };
  return { r };
}

// ---------- azioni ----------
async function crea(req: Request, b: any) {
  const u = await utenteAutorizzato(req);
  if (!u) return json({ errore: "non_autorizzato" }, 401);

  const nome = String(b.firmatario_nome ?? "").trim();
  if (!b.documento_id || !b.campo_id || !nome) return json({ errore: "dati_mancanti" }, 400);

  const { data: doc } = await admin.from("pdf_documenti")
    .select("id, stato, campi, firme_completate, pdf_path").eq("id", b.documento_id).maybeSingle();
  if (!doc) return json({ errore: "documento_non_trovato" }, 404);
  if (doc.stato === "firmato" || doc.stato === "annullato") return json({ errore: "documento_chiuso" }, 409);
  if (!doc.pdf_path) return json({ errore: "pdf_mancante" }, 409);

  const campo = (doc.campi ?? []).find((c: any) => c.id === b.campo_id && c.tipo === "sign");
  if (!campo) return json({ errore: "campo_non_valido" }, 400);
  if ((doc.firme_completate ?? []).includes(b.campo_id)) return json({ errore: "campo_gia_firmato" }, 409);

  const ora = new Date().toISOString();
  // un solo link attivo per campo: i precedenti vengono revocati
  await admin.from("pdf_firme_richieste").update({ revocato_il: ora, revocato_da: u.id })
    .eq("documento_id", doc.id).eq("campo_id", b.campo_id).is("usato_il", null).is("revocato_il", null);

  const token = nuovoToken();
  const ore = Math.min(Math.max(Number(b.ore_validita) || ORE_DEFAULT, 1), ORE_MAX);
  const scade = new Date(Date.now() + ore * 3600_000).toISOString();

  const { data: ric, error } = await admin.from("pdf_firme_richieste").insert({
    documento_id: doc.id, campo_id: b.campo_id, firmatario_nome: nome,
    firmatario_contatto: b.firmatario_contatto ?? null,
    token_hash: await sha256Hex(token), scade_il: scade, creato_da: u.id,
  }).select("id").single();
  if (error) { console.error(error); return json({ errore: "errore_interno" }, 500); }

  if (doc.stato === "bozza") await admin.from("pdf_documenti").update({ stato: "in_firma" }).eq("id", doc.id);
  await audit({ documento_id: doc.id, evento: "link_creato", campo_id: b.campo_id, attore: u.email, utente_id: u.id,
    dettagli: { richiesta_id: ric.id, firmatario: nome, scade_il: scade } });

  return json({ richiesta_id: ric.id, link: `${SITE}/firma.html?t=${token}`, scade_il: scade });
}

async function revoca(req: Request, b: any) {
  const u = await utenteAutorizzato(req);
  if (!u) return json({ errore: "non_autorizzato" }, 401);
  const { data: r } = await admin.from("pdf_firme_richieste")
    .update({ revocato_il: new Date().toISOString(), revocato_da: u.id })
    .eq("id", b.richiesta_id).is("usato_il", null).is("revocato_il", null)
    .select("id, documento_id, campo_id").maybeSingle();
  if (!r) return json({ errore: "non_revocabile" }, 409);
  await audit({ documento_id: r.documento_id, evento: "link_revocato", campo_id: r.campo_id, attore: u.email, utente_id: u.id,
    dettagli: { richiesta_id: r.id } });
  return json({ ok: true });
}

async function apri(req: Request, b: any) {
  const t = await trovaRichiesta(b.token);
  if (t.err) return json({ errore: t.err }, 410);
  const r = t.r!;
  const { data: doc } = await admin.from("pdf_documenti")
    .select("id, titolo, stato, pdf_path, campi").eq("id", r.documento_id).single();
  if (!doc || doc.stato === "annullato" || !doc.pdf_path) return json({ errore: "revocato" }, 410);

  const campo = (doc.campi ?? []).find((c: any) => c.id === r.campo_id);
  const { data: url } = await admin.storage.from(BUCKET).createSignedUrl(doc.pdf_path, 600);
  const { ip, ua } = infoClient(req);
  if (!r.aperto_il) await admin.from("pdf_firme_richieste").update({ aperto_il: new Date().toISOString() }).eq("id", r.id);
  await audit({ documento_id: doc.id, evento: "link_aperto", campo_id: r.campo_id, attore: r.firmatario_nome, ip, user_agent: ua });

  return json({
    titolo: doc.titolo,
    firmatario_nome: r.firmatario_nome,
    scade_il: r.scade_il,
    pdf_url: url?.signedUrl,
    campo: campo && { nome: campo.nome, pagina: campo.pagina, x: campo.x, y: campo.y, larghezza: campo.larghezza, altezza: campo.altezza },
  });
}

async function firma(req: Request, b: any) {
  if (b.consenso !== true) return json({ errore: "consenso_mancante" }, 400);
  const png64 = b.firma_png;
  if (typeof png64 !== "string" || !png64.startsWith("data:image/png;base64,") || png64.length > 700_000)
    return json({ errore: "firma_non_valida" }, 400);

  const t = await trovaRichiesta(b.token);
  if (t.err) return json({ errore: t.err }, 410);
  const r = t.r!;
  const { ip, ua } = infoClient(req);

  // prenotazione atomica del token: se due richieste arrivano insieme ne passa una sola
  const { data: lock } = await admin.from("pdf_firme_richieste")
    .update({ usato_il: new Date().toISOString(), ip, user_agent: ua })
    .eq("id", r.id).is("usato_il", null).is("revocato_il", null).gt("scade_il", new Date().toISOString())
    .select("id").maybeSingle();
  if (!lock) return json({ errore: "usato" }, 410);

  try {
    const png = Uint8Array.from(atob(png64.split(",")[1]), (c) => c.charCodeAt(0));

    // fino a 3 tentativi se un'altra firma sullo stesso documento arriva in contemporanea
    for (let tentativo = 0; tentativo < 3; tentativo++) {
      const { data: doc } = await admin.from("pdf_documenti").select("*").eq("id", r.documento_id).single();
      if (!doc || doc.stato === "annullato" || doc.stato === "firmato") throw new Error("documento_chiuso");
      const campo = (doc.campi ?? []).find((c: any) => c.id === r.campo_id);
      if (!campo) throw new Error("campo_non_trovato");

      const { data: file, error: dlErr } = await admin.storage.from(BUCKET).download(doc.pdf_path);
      if (dlErr || !file) throw dlErr ?? new Error("pdf_non_trovato");

      const pdf = await PDFDocument.load(new Uint8Array(await file.arrayBuffer()), { ignoreEncryption: true });
      const page = pdf.getPages()[campo.pagina - 1];
      const H = page.getHeight();
      const img = await pdf.embedPng(png);
      const s = Math.min(campo.larghezza / img.width, campo.altezza / img.height);
      const w = img.width * s, h = img.height * s;
      page.drawImage(img, {
        x: campo.x + (campo.larghezza - w) / 2,
        y: H - campo.y - campo.altezza + (campo.altezza - h) / 2,
        width: w, height: h,
      });
      const font = await pdf.embedFont(StandardFonts.Helvetica);
      page.drawText(safe(`Firmato elettronicamente da ${r.firmatario_nome} il ${adesso()}`), {
        x: campo.x, y: H - campo.y - campo.altezza - 7, size: 5.5, font, color: rgb(0.4, 0.45, 0.52),
      });

      const bytes = await pdf.save();
      const hash = await sha256Hex(bytes);
      const versione = (doc.versione_pdf ?? 0) + 1;
      const path = `${doc.id}/v${versione}.pdf`;

      const up = await admin.storage.from(BUCKET).upload(path, bytes, { contentType: "application/pdf", upsert: false });
      if (up.error) {
        if (/exist|duplicate/i.test(up.error.message)) continue; // qualcun altro ha già creato vN: riprovo sulla nuova
        throw up.error;
      }

      const firme = [...new Set([...(doc.firme_completate ?? []), campo.id])];
      const obbligatorie = (doc.campi ?? []).filter((c: any) => c.tipo === "sign" && c.obbligatorio !== false).map((c: any) => c.id);
      const completo = obbligatorie.every((id: string) => firme.includes(id));
      const ora = new Date().toISOString();

      const { data: ok } = await admin.from("pdf_documenti").update({
        pdf_path: path, versione_pdf: versione, sha256: hash, firme_completate: firme,
        stato: completo ? "firmato" : "in_firma", firmato_il: completo ? ora : null,
      }).eq("id", doc.id).eq("versione_pdf", doc.versione_pdf ?? 0).select("id").maybeSingle();
      if (!ok) continue; // conflitto: il file vN resta come storico, riprovo

      await audit({ documento_id: doc.id, evento: "firma_link", campo_id: campo.id, attore: r.firmatario_nome,
        ip, user_agent: ua, sha256: hash, dettagli: { richiesta_id: r.id, versione } });
      if (completo) await audit({ documento_id: doc.id, evento: "completato", sha256: hash, dettagli: { versione } });

      return json({ ok: true, sha256: hash, completo });
    }
    throw new Error("conflitto_ripetuto");
  } catch (e) {
    console.error("firma", e);
    // libero il token così il firmatario può riprovare
    await admin.from("pdf_firme_richieste").update({ usato_il: null, ip: null, user_agent: null }).eq("id", r.id);
    const msg = e instanceof Error ? e.message : "";
    if (msg === "documento_chiuso") return json({ errore: "revocato" }, 410);
    return json({ errore: "errore_interno" }, 500);
  }
}

// ---------- router ----------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ errore: "metodo_non_consentito" }, 405);
  let b: any;
  try { b = await req.json(); } catch { return json({ errore: "richiesta_non_valida" }, 400); }
  switch (b?.azione) {
    case "crea": return crea(req, b);
    case "revoca": return revoca(req, b);
    case "apri": return apri(req, b);
    case "firma": return firma(req, b);
    default: return json({ errore: "azione_sconosciuta" }, 400);
  }
});
