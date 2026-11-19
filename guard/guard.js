// In-page send guard for English Slack. Requires detect.js (globalThis.looksPortuguese)
// to be loaded first; build.sh concatenates them into guard.bundle.js.
// Fails open: any error lets the message through. No network access.
(function () {
  "use strict";
  if (window.__ptGuard) return;
  window.__ptGuard = true;

  const COMPOSER = '[data-qa="texty_input"]';
  const SEND = '[data-qa="texty_send_button"]';
  const AUTOCOMPLETE = '[role="listbox"]'; // emoji / @mention suggestions

  const visible = (el) => el && el.getClientRects().length > 0;
  const autocompleteOpen = () => [...document.querySelectorAll(AUTOCOMPLETE)].some(visible);

  function composerForButton(btn) {
    for (let p = btn.parentElement; p; p = p.parentElement) {
      const c = p.querySelector(COMPOSER);
      if (c) return c;
    }
    const a = document.activeElement;
    return a && a.closest ? a.closest(COMPOSER) : null;
  }

  // Returns true when the send may proceed.
  function allowSend(composer) {
    const text = (composer.innerText || "").trim();
    if (!text) return true;
    const r = globalThis.looksPortuguese(text);
    if (!r.pt) return true;
    const preview = text.length > 160 ? text.slice(0, 160) + "…" : text;
    return window.confirm(`This looks like Portuguese:\n\n“${preview}”\n\nSend anyway?`);
  }

  function block(e) {
    e.preventDefault();
    e.stopImmediatePropagation();
  }

  window.addEventListener("keydown", (e) => {
    try {
      if (e.key !== "Enter" || e.shiftKey || e.altKey || e.ctrlKey || e.metaKey || e.isComposing) return;
      const composer = e.target && e.target.closest ? e.target.closest(COMPOSER) : null;
      if (!composer || autocompleteOpen()) return;
      if (!allowSend(composer)) block(e);
    } catch (err) {
      console.warn("[ptGuard] keydown check failed, allowing send", err);
    }
  }, true);

  window.addEventListener("click", (e) => {
    try {
      const btn = e.target && e.target.closest ? e.target.closest(SEND) : null;
      if (!btn) return;
      const composer = composerForButton(btn);
      if (composer && !allowSend(composer)) block(e);
    } catch (err) {
      console.warn("[ptGuard] click check failed, allowing send", err);
    }
  }, true);
})();
