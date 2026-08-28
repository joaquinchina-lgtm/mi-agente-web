/* ═══════════════════════════════════════════════════════════════
   GOOGLE ANALYTICS 4 · joaquinromero.com

   Un único sitio donde vive la medición. Antes el tag estaba
   pegado a mano en tres páginas y faltaba en las otras veintidós,
   así que las páginas de servicio (que son las largas, las que de
   verdad interesa saber si se leen) no medían absolutamente nada.

   Aquí se hacen tres cosas, y en este orden, que importa:

     1. Se declara el consentimiento por defecto en «denegado».
        Tiene que ocurrir ANTES de configurar el tag: si se hace
        después, la primera vista de página ya ha salido con
        almacenamiento permitido y el consentimiento llega tarde.
        En el montaje anterior pasaba exactamente eso.
     2. Se recupera la preferencia guardada y, si aceptó, se
        actualiza a «concedido».
     3. Se carga el tag y se configura.

   El banner se pinta en cualquier página, no solo en la home: si
   alguien llega directo a una página de servicio desde LinkedIn,
   tiene que poder decidir ahí mismo. Si la página ya trae su
   propio #cookie-banner (la home lo trae, con su política larga),
   se reutiliza ese y no se inventa otro.

   Se carga con `defer` en todas las páginas públicas. En el área
   interna no se carga a propósito: son visitas propias y no deben
   contaminar las cifras.
   ═══════════════════════════════════════════════════════════════ */
(function(){
  "use strict";

  var ID    = "G-4H0ZT7ZTNX";
  var CLAVE = "cookieConsentGA";          // 'true' | 'false' | null

  window.dataLayer = window.dataLayer || [];
  function gtag(){ dataLayer.push(arguments); }
  window.gtag = gtag;

  function leer(){ try{ return localStorage.getItem(CLAVE); }catch(e){ return null; } }
  function guardar(v){ try{ localStorage.setItem(CLAVE, v); }catch(e){} }

  /* ── 1 · Consentimiento por defecto, antes de nada ────────── */
  gtag("consent", "default", {
    ad_storage:          "denied",
    ad_user_data:        "denied",
    ad_personalization:  "denied",
    analytics_storage:   "denied"
  });

  /* ── 2 · Preferencia ya guardada ──────────────────────────── */
  var pref = leer();
  if(pref === "true"){
    gtag("consent", "update", { analytics_storage: "granted" });
  }

  /* ── 3 · Y ahora el tag ───────────────────────────────────── */
  var s = document.createElement("script");
  s.async = true;
  s.src = "https://www.googletagmanager.com/gtag/js?id=" + ID;
  (document.head || document.documentElement).appendChild(s);

  gtag("js", new Date());
  gtag("config", ID);

  /* ── 4 · Banner ───────────────────────────────────────────── */
  var CSS =
    "#jr-cookies{position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;" +
    "background:#fff;border:1px solid #e4e7e6;padding:16px 18px;max-width:640px;" +
    "margin:0 auto;font:400 14.5px/1.5 'Inter',system-ui,sans-serif;color:#16211f;" +
    "box-shadow:0 10px 18px rgba(2,6,23,.08)}" +
    "#jr-cookies p{margin:0 0 12px}" +
    "#jr-cookies a{color:#22525C}" +
    "#jr-cookies .jr-cb{display:flex;gap:8px;flex-wrap:wrap}" +
    "#jr-cookies button{font:500 14px 'Inter',system-ui,sans-serif;padding:8px 14px;" +
    "border:1px solid #e4e7e6;background:#fff;color:#16211f;cursor:pointer}" +
    "#jr-cookies button.p{background:#32717E;color:#fff;border-color:#32717E}";

  function propio(){
    var d = document.createElement("div");
    d.id = "jr-cookies";
    d.setAttribute("role", "dialog");
    d.setAttribute("aria-label", "Consentimiento de cookies");
    d.innerHTML =
      '<p>Usamos cookies <strong>técnicas</strong> y, si aceptas, ' +
      '<strong>analíticas</strong> (Google Analytics 4) para saber qué ' +
      'se lee. <a href="/#politica-cookies">Más información</a>.</p>' +
      '<div class="jr-cb">' +
      '<button type="button" data-jr="no">Rechazar</button>' +
      '<button type="button" class="p" data-jr="si">Aceptar</button>' +
      '</div>';
    var e = document.createElement("style");
    e.textContent = CSS;
    document.head.appendChild(e);
    document.body.appendChild(d);
    d.addEventListener("click", function(ev){
      var b = ev.target.closest("button[data-jr]");
      if(b) window.setCookieConsent(b.getAttribute("data-jr") === "si");
    });
    return d;
  }

  function arrancar(){
    /* La home trae su propio banner con la política completa. */
    var banner = document.getElementById("cookie-banner");
    var mio    = false;

    window.setCookieConsent = function(acepta){
      guardar(String(!!acepta));
      gtag("consent", "update", { analytics_storage: acepta ? "granted" : "denied" });
      var b = document.getElementById("cookie-banner") || document.getElementById("jr-cookies");
      if(b) b.style.display = "none";
    };

    window.toggleCookieBanner = function(ver){
      var b = document.getElementById("cookie-banner");
      if(!b && !document.getElementById("jr-cookies")) b = propio();
      b = b || document.getElementById("jr-cookies");
      if(b) b.style.display = ver ? "block" : "none";
    };

    if(leer() !== null) return;               // ya decidió

    if(!banner){ banner = propio(); mio = true; }
    banner.style.display = "block";
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", arrancar);
  } else {
    arrancar();
  }
})();
