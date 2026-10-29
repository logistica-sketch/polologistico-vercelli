/* =====================================================================
   Genera gli MP3 della guida dai copioni in dati.js (intro + v di ogni passo).
   Rigenera solo i file il cui testo è cambiato.

   ElevenLabs (consigliato):
     ELEVENLABS_API_KEY=xxx ELEVENLABS_VOICE_ID=yyy node genera-audio.mjs
   Gratis, senza account (voci Microsoft Edge, serve Python):
     pip install edge-tts
     node genera-audio.mjs --edge
     voce diversa:  $env:EDGE_VOICE="it-IT-DiegoNeural"   (altre: it-IT-ElsaNeural, it-IT-GiuseppeMultilingualNeural)
     Python non nel PATH:  $env:PYTHON="$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
   Google Cloud Text-to-Speech:
     GOOGLE_API_KEY=xxx GOOGLE_VOICE=it-IT-Chirp3-HD-Aoede node genera-audio.mjs --google
   Gemini API (serve ffmpeg; la chiave solo come variabile, mai nei file):
     $env:GEMINI_API_KEY="xxx"; node genera-audio.mjs --gemini
     voce: $env:GEMINI_VOICE="Kore" (predefinita Charon); modello: $env:GEMINI_MODEL
     ffmpeg non nel PATH:  $env:FFMPEG="C:\...\ffmpeg.exe"
     Al limite giornaliero si ferma: rilanciando il giorno dopo riparte dai file mancanti.

   Opzioni:  --solo tlc,formazione   solo queste pagine
             --forza                 rigenera tutto
             --prova                 mostra cosa farebbe, senza chiamare il servizio
             --uscita prova-voci     scrive <voce>-<n>.mp3 in quella cartella per confrontare
                                     le voci, senza toccare audio/ né le impronte
   Richiede Node 18 o successivo.
   ===================================================================== */
import fs from "node:fs";
import vm from "node:vm";
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2);
const opt = n => { const i = args.indexOf(n); return i >= 0 ? (args[i+1] || true) : null; };
const EDGE = args.includes("--edge"), GOOGLE = args.includes("--google"), GEMINI = args.includes("--gemini"), FORZA = args.includes("--forza"), PROVA = args.includes("--prova");
const SOLO = typeof opt("--solo") === "string" ? opt("--solo").split(",") : null;
const USCITA = typeof opt("--uscita") === "string" ? opt("--uscita") : null;

const GEMINI_MODEL = process.env.GEMINI_MODEL || "gemini-3.1-flash-tts-preview";
const STILE_GEMINI = "Parla in italiano, con tono cordiale, calmo e naturale, come un volontario esperto di protezione civile che spiega l'app a un collega seduto accanto a lui. Ritmo tranquillo, piccole pause tra le frasi. Testo: ";

/* Come pronunciare sigle e abbreviazioni: modifica liberamente. */
const PRONUNCIA = [
  [/\bTLC\b/g, "ti elle ci"], [/\bT L C\b/g, "ti elle ci"], [/\bPDF\b/g, "pi di effe"],
  [/\bC A I\b/g, "ca-i"], [/\bCAI\b/g, "ca-i"], [/\bRGPT\b/g, "Raggruppamento"],
  [/\bANA\b/g, "Ana"], [/\bDPI\b/g, "di pi i"], [/\bart\. ?39\b/gi, "articolo trentanove"],
  [/\bExcel\b/g, "Excel"], [/\bzip\b/gi, "zip"], [/\bA4\b/g, "A quattro"],
];
const pronuncia = t => PRONUNCIA.reduce((s, [re, r]) => s.replace(re, r), t);

const ctx = {}; vm.createContext(ctx);
vm.runInContext(fs.readFileSync("dati.js", "utf8") + ";this.PAGINE = PAGINE;", ctx);

fs.mkdirSync("audio", { recursive: true });
const HASH_FILE = "audio/.impronte.json";
const impronte = fs.existsSync(HASH_FILE) ? JSON.parse(fs.readFileSync(HASH_FILE, "utf8")) : {};
const voce = EDGE ? (process.env.EDGE_VOICE || "it-IT-IsabellaNeural") : GOOGLE ? (process.env.GOOGLE_VOICE || "it-IT-Chirp3-HD-Aoede")
  : GEMINI ? (process.env.GEMINI_VOICE || "Charon") : process.env.ELEVENLABS_VOICE_ID;
// Con Gemini anche modello e indicazione di stile cambiano il risultato: entrano nell'impronta
const chiaveVoce = GEMINI ? `${voce}|${GEMINI_MODEL}|${STILE_GEMINI}` : voce;

if (!PROVA && !EDGE){
  if (GOOGLE && !process.env.GOOGLE_API_KEY) fine("Manca GOOGLE_API_KEY");
  if (GEMINI && !process.env.GEMINI_API_KEY) fine("Manca GEMINI_API_KEY");
  if (!GOOGLE && !GEMINI && (!process.env.ELEVENLABS_API_KEY || !voce)) fine("Mancano ELEVENLABS_API_KEY e/o ELEVENLABS_VOICE_ID");
}
function fine(m){ console.error("✖ " + m); process.exit(1); }

function edge(testo, file){
  const tmp = path.join(os.tmpdir(), "guida-testo.txt");
  fs.writeFileSync(tmp, testo, "utf8");
  const argomenti = ["-m", "edge_tts", "--voice", voce, "--rate=-4%", "--file", tmp, "--write-media", file];
  // PYTHON = percorso completo dell'interprete, se non è nel PATH
  for (const py of [process.env.PYTHON, "python", "py", "python3"].filter(Boolean)){
    try{ execFileSync(py, argomenti, { stdio: "pipe" }); return; }
    catch(e){ if (e.code !== "ENOENT") throw new Error(String(e.stderr || e.message).slice(0, 400)); }
  }
  throw new Error("Python non trovato. Installa Python da python.org e poi: pip install edge-tts");
}

/* ---------- Gemini API ---------- */
class LimiteGiornaliero extends Error {}
const attendi = s => new Promise(r => setTimeout(r, s * 1000));

// FFMPEG, poi il PATH, poi l'installazione winget (Gyan.FFmpeg), che non sempre aggiorna il PATH
function candidatiFfmpeg(){
  const c = [process.env.FFMPEG, "ffmpeg"];
  const pacchetti = process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Packages");
  if (pacchetti && fs.existsSync(pacchetti)){
    for (const p of fs.readdirSync(pacchetti).filter(d => d.startsWith("Gyan.FFmpeg"))){
      for (const b of fs.readdirSync(path.join(pacchetti, p))) c.push(path.join(pacchetti, p, b, "bin", "ffmpeg.exe"));
    }
  }
  return c.filter(Boolean);
}

// Audio Gemini → MP3 con ffmpeg. I modelli 3.1 restituiscono PCM 16 bit mono senza intestazione
// (mimeType "audio/L16;codec=pcm;rate=24000"); i più recenti un WAV completo.
function audioInMp3(dati, mimeType, file){
  const wav = dati.subarray(0, 4).toString("ascii") === "RIFF";
  const rate = (/rate=(\d+)/.exec(mimeType || "") || [])[1] || "24000";
  const ingresso = wav ? ["-i", "pipe:0"] : ["-f", "s16le", "-ar", rate, "-ac", "1", "-i", "pipe:0"];
  const argomenti = ["-y", "-loglevel", "error", ...ingresso, "-codec:a", "libmp3lame", "-b:a", "64k", file];
  for (const ff of candidatiFfmpeg()){
    try{ execFileSync(ff, argomenti, { input: dati, stdio: ["pipe", "pipe", "pipe"] }); return; }
    catch(e){ if (e.code !== "ENOENT") throw new Error("ffmpeg: " + String(e.stderr || e.message).slice(0, 400)); }
  }
  throw new Error("ffmpeg non trovato. Installalo (winget install Gyan.FFmpeg) o indica il percorso in FFMPEG");
}

async function gemini(testo, file){
  for (let tentativo = 1; ; tentativo++){
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": process.env.GEMINI_API_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: STILE_GEMINI + testo }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voce } } }
        }
      })
    });
    if (r.status === 429){
      const corpo = await r.text();
      // limite giornaliero (quotaId "...PerDay..."): inutile aspettare
      if (/PerDay/i.test(corpo)) throw new LimiteGiornaliero(corpo.slice(0, 300));
      if (tentativo >= 8) throw new Error("Gemini 429 ripetuto: " + corpo.slice(0, 300));
      const ritardo = /"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"/.exec(corpo);
      const sec = ritardo ? Math.ceil(parseFloat(ritardo[1])) + 2 : 20 * tentativo;
      process.stdout.write(`(limite richieste, attendo ${sec}s) `);
      await attendi(sec);
      continue;
    }
    if (r.status >= 500 && tentativo < 4){ await attendi(5 * tentativo); continue; }
    if (!r.ok) throw new Error(`Gemini ${r.status}: ${(await r.text()).slice(0, 400)}`);
    const j = await r.json();
    const parte = (j.candidates?.[0]?.content?.parts || []).find(p => p.inlineData?.data);
    if (!parte){
      // capita che il modello risponda senza audio: si riprova un paio di volte
      if (tentativo < 3){ await attendi(3); continue; }
      throw new Error("Risposta senza audio: " + JSON.stringify(j).slice(0, 300));
    }
    audioInMp3(Buffer.from(parte.inlineData.data, "base64"), parte.inlineData.mimeType, file);
    return;
  }
}

async function sintetizza(testo, prima, dopo){
  if (GOOGLE){
    const r = await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize?key=${process.env.GOOGLE_API_KEY}`, {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ input: { text: testo }, voice: { languageCode: "it-IT", name: voce },
        audioConfig: { audioEncoding: "MP3", speakingRate: 1.0 } })
    });
    if (!r.ok) throw new Error(`Google ${r.status}: ${await r.text()}`);
    return Buffer.from((await r.json()).audioContent, "base64");
  }
  const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voce}?output_format=mp3_44100_128`, {
    method: "POST",
    headers: { "xi-api-key": process.env.ELEVENLABS_API_KEY, "Content-Type": "application/json", "Accept": "audio/mpeg" },
    body: JSON.stringify({
      text: testo, model_id: "eleven_multilingual_v2",
      previous_text: prima || undefined, next_text: dopo || undefined,   // tono continuo tra un passo e l'altro
      voice_settings: { stability: 0.5, similarity_boost: 0.75, style: 0.15, use_speaker_boost: true }
    })
  });
  if (!r.ok) throw new Error(`ElevenLabs ${r.status}: ${await r.text()}`);
  return Buffer.from(await r.arrayBuffer());
}

if (USCITA) fs.mkdirSync(USCITA, { recursive: true });
let fatti = 0, saltati = 0, caratteri = 0, mancanti = 0, limite = null;
for (const pg of ctx.PAGINE){
  if (SOLO && !SOLO.includes(pg.id)) continue;
  const pezzi = [pg.intro || "", ...pg.passi.map(p => p.v || "")].map(pronuncia);
  for (let i = 0; i < pezzi.length; i++){
    const testo = pezzi[i]; if (!testo) continue;
    const n = String(i).padStart(2, "0");
    const nome = `${pg.id}-${n}.mp3`;
    const dest = USCITA ? path.join(USCITA, `${voce}-${n}.mp3`) : "audio/" + nome;
    const impronta = crypto.createHash("sha1").update(chiaveVoce + "|" + testo).digest("hex");
    if (!USCITA && !FORZA && impronte[nome] === impronta && fs.existsSync(dest)){ saltati++; continue; }
    if (limite){ mancanti++; continue; }
    caratteri += testo.length;
    if (PROVA){ console.log("• " + nome + "  (" + testo.length + " caratteri)"); continue; }
    process.stdout.write("• " + dest + " … ");
    try{
      if (EDGE) edge(testo, dest);
      else if (GEMINI) await gemini(testo, dest);
      else fs.writeFileSync(dest, await sintetizza(testo, pezzi[i-1], pezzi[i+1]));
      if (!USCITA) impronte[nome] = impronta;
      fatti++; console.log("ok");
    } catch(e){
      console.log("ERRORE");
      if (e instanceof LimiteGiornaliero){ limite = e; mancanti++; caratteri -= testo.length; }
      else console.error("  " + e.message);
    }
  }
}
if (!PROVA && !USCITA){
  fs.writeFileSync(HASH_FILE, JSON.stringify(impronte, null, 1));
  const elenco = fs.readdirSync("audio").filter(f => f.endsWith(".mp3")).sort();
  fs.writeFileSync("audio/elenco.json", JSON.stringify(elenco));
}
console.log(`\n${PROVA ? "Da generare" : "Generati"}: ${PROVA ? "" : fatti + ", "}invariati: ${saltati}, caratteri inviati: ${caratteri}`);
if (limite){
  console.log(`\n⚠ Limite giornaliero di Gemini raggiunto: mancano ${mancanti} file. Rilancia lo stesso comando domani, ripartirà da quelli.`);
  console.log("  " + limite.message);
}
