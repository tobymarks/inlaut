// Lets the language switch knob finish its slide before the other language loads.
(() => {
  const link = document.querySelector(".lang-switch");
  if (!link) return;
  const still = matchMedia("(prefers-reduced-motion: reduce)");
  link.addEventListener("click", event => {
    if (still.matches || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return;
    event.preventDefault();
    link.classList.add("is-switching");
    setTimeout(() => { location.href = link.href; }, 420);
  });
  // Coming back via the history must not show the knob on the wrong side.
  addEventListener("pageshow", () => link.classList.remove("is-switching"));
})();
