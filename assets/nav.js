/* ===========================================================================
   nav.js — comportamiento de la navegación de joaquinromero.com
   Se enlaza desde TODAS las páginas, al final del <body>:
     <script src="/assets/nav.js" defer></script>
   No depende de librerías.
   =========================================================================== */
(function () {
  'use strict';

  var burger = document.querySelector('.jr-header .jr-burger');
  var closeB = document.querySelector('.jr-menu .jr-burger');
  var menu   = document.querySelector('.jr-menu');
  var scrim  = document.querySelector('.jr-scrim');
  if (!burger || !menu || !scrim) return;

  var open = false;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');

  function focusables() {
    return menu.querySelectorAll('a[href], button:not([disabled])');
  }

  function openMenu() {
    if (open) return;
    open = true;
    menu.hidden = false;
    scrim.hidden = false;
    document.body.classList.add('jr-locked');
    requestAnimationFrame(function () {
      menu.classList.add('is-open');
      scrim.classList.add('is-open');
    });
    burger.setAttribute('aria-expanded', 'true');
    burger.setAttribute('aria-label', 'Cerrar menú');
    setTimeout(function () {
      var f = focusables();
      if (f.length) (f[1] || f[0]).focus({ preventScroll: true });
    }, 60);
    document.addEventListener('keydown', onKey);
  }

  function closeMenu() {
    if (!open) return;
    open = false;
    menu.classList.remove('is-open');
    scrim.classList.remove('is-open');
    burger.setAttribute('aria-expanded', 'false');
    burger.setAttribute('aria-label', 'Abrir menú');
    document.body.classList.remove('jr-locked');
    document.removeEventListener('keydown', onKey);
    setTimeout(function () {
      menu.hidden = true;
      scrim.hidden = true;
    }, reduce.matches ? 0 : 300);
    burger.focus({ preventScroll: true });
  }

  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); closeMenu(); return; }
    if (e.key !== 'Tab') return;
    var f = focusables();
    if (!f.length) return;
    var first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  }

  burger.addEventListener('click', function () { open ? closeMenu() : openMenu(); });
  if (closeB) closeB.addEventListener('click', closeMenu);
  scrim.addEventListener('click', closeMenu);
  Array.prototype.forEach.call(menu.querySelectorAll('a[href]'), function (a) {
    a.addEventListener('click', closeMenu);
  });
  window.addEventListener('hashchange', closeMenu);

  // si el usuario gira el móvil o pasa a desktop con el panel abierto, se cierra
  var wide = window.matchMedia('(min-width: 768px)');
  var onWide = function (e) { if (e.matches) closeMenu(); };
  if (wide.addEventListener) wide.addEventListener('change', onWide);
  else if (wide.addListener) wide.addListener(onWide);

  /* --- marcado de la sección/página activa -------------------------------- */
  (function markActive() {
    var path = location.pathname.replace(/index\.html$/, '');
    var hash = location.hash;
    var all = document.querySelectorAll('.jr-links a[href], .jr-menu-list a[href]');
    Array.prototype.forEach.call(all, function (a) {
      var href = a.getAttribute('href') || '';
      var isBlog = /^\/blog\//.test(path) && /#blog$/.test(href);
      var samePage = href.indexOf('/') === 0 && href.split('#')[0] === path && href.split('#')[0] !== '/';
      var sameHash = hash && href.slice(-hash.length) === hash;
      if (isBlog || samePage || sameHash) a.setAttribute('aria-current', 'true');
      else a.removeAttribute('aria-current');
    });
  })();
})();
