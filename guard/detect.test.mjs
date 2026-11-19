import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
const { looksPortuguese } = createRequire(import.meta.url)("./detect.js");

const PORTUGUESE = [
  "você viu isso?",
  "Vou ver isso amanhã",
  "O deploy quebrou de novo",
  "valeu",
  "obrigado!",
  "tá bom",
  "blz",
  "kkkkk",
  "não sei se dá pra fazer hoje",
  "Pessoal, alguém pode revisar meu PR?",
  "a reunião foi remarcada para quinta",
  "Acho que o problema está na migração",
  "beleza, já subi a correção",
  "pq o build tá falhando?",
  "Bom dia galera",
  "manda o link aqui por favor",
  "Consegui resolver, era só reiniciar o serviço",
];

const ENGLISH = [
  "did you see this?",
  "I'll look at it tomorrow",
  "The deploy broke again",
  "thanks!",
  "ok",
  "LGTM",
  "Can someone review my PR?",
  "We had a great trip to São Paulo last week",
  "Gonçalves is joining the call",
  "Nice façade on that building",
  "The meeting moved to Thursday",
  "I think the problem is in the migration script",
  "um, not sure about that",
  "ping @joao.silva in #time-dev",
  "see https://example.com.br/nao/isso/pra/voce",
  "run `git commit -m 'não sei'` and push",
  "```\nconst isso = 'você está aqui'\n```\nthis snippet fails",
  "So do we need a SIM for the EU trip?",
  "pro tip: use the era field",
  ":tada: shipped!",
  "",
  "Our new product launch is on track",
  "Let's sync on the data model",
];

for (const s of PORTUGUESE) test(`pt: ${JSON.stringify(s)}`, () => {
  const r = looksPortuguese(s);
  assert.equal(r.pt, true, JSON.stringify(r));
});

for (const s of ENGLISH) test(`en: ${JSON.stringify(s)}`, () => {
  const r = looksPortuguese(s);
  assert.equal(r.pt, false, JSON.stringify(r));
});
