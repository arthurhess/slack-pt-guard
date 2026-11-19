// Portuguese detector for the English Slack send guard.
// Pure, synchronous, no network. Shared by guard.js (in-page) and node tests.
(function (root) {
  "use strict";

  // Words that are Portuguese and (practically) never English.
  // Deliberately excluded because they are English words/abbreviations too:
  // a, o, e, um, so, sim, era, pro, eu, nos, ne, td, q, rs, ali, sem, to, ta, la, me, as, do, no.
  const STRONG = new Set((
    "não nao você voce vocês voces vc vcs está esta estou estamos estão estao estava " +
    "isso isto essa esse essas esses aquele aquela aquilo também tambem tb tbm " +
    "obrigado obrigada valeu tá tô dá lá aí daí né pra pq porque porquê então entao " +
    "aqui agora ainda já muito muita muitos muitas bem bom boa oi olá ola tudo nada " +
    "gente que quê quem qual quais quando onde como com sobre depois antes hoje " +
    "amanhã amanha ontem vou vai vamos vão fazer faz fiz feito tem tenho temos ter ser " +
    "foi sou são é eles elas ele ela nós meu minha seu sua dele dela nosso nossa " +
    "mesmo mesma mais menos só pode posso podemos preciso precisa acho sei sabe " +
    "quero queria beleza blz viu deu coisa coisas tipo dia novo nova uma umas uns " +
    "num numa dos das nas pelo pela pelos pelas ao aos à às mas para até ate cadê cade " +
    "certeza claro galera pessoal tranquilo por favor manda mandar mandei olha alguém " +
    "consegui conseguiu vamo bora entendi beleza"
  ).split(/\s+/));

  // Function words shared with other languages: only count once a strong signal exists.
  const WEAK = new Set("o a e de do da em no na os as um".split(" "));

  const STRIP = [
    /```[\s\S]*?```/g,           // code blocks
    /`[^`\n]*`/g,                // inline code
    /\bhttps?:\/\/\S+/gi,        // URLs
    /\b[\w.-]+\.(com|br|io|dev|org|net)\b\S*/gi, // bare domains
    /:[a-z0-9_+-]+:/gi,          // :emoji:
    /[@#][\w.-]+/g,              // @mentions, #channels
  ];

  function tokenize(text) {
    let t = String(text || "");
    for (const re of STRIP) t = t.replace(re, " ");
    return t.match(/[A-Za-zÀ-ÖØ-öø-ÿ]+/g) || [];
  }

  function isStrong(word, index) {
    const w = word.toLowerCase();
    if (STRONG.has(w)) return true;
    if (/^k{3,}$/.test(w)) return true; // kkkk
    // ã/õ/ç or Portuguese suffixes, but not capitalized names mid-sentence (São Paulo, Gonçalves).
    const capitalized = word[0] !== word[0].toLowerCase();
    if (capitalized && index > 0) return false;
    if (/[ãõç]/.test(w)) return true;
    if (w.length > 4 && /(ção|ções|ões|inho|inha)$/.test(w)) return true;
    return false;
  }

  function looksPortuguese(text) {
    const tokens = tokenize(text);
    let strong = 0, weak = 0;
    const hits = [];
    tokens.forEach((tok, i) => {
      if (isStrong(tok, i)) { strong++; hits.push(tok); }
      else if (WEAK.has(tok.toLowerCase())) weak++;
    });
    const n = tokens.length;
    let pt = false;
    let score = 0;
    if (n > 0 && strong > 0) {
      score = (strong + 0.5 * weak) / n;
      pt = n < 3 ? true : score >= 0.35;
    }
    return { pt, score: Math.round(score * 100) / 100, tokens: n, hits };
  }

  root.looksPortuguese = looksPortuguese;
  if (typeof module !== "undefined" && module.exports) module.exports = { looksPortuguese };
})(typeof globalThis !== "undefined" ? globalThis : this);
