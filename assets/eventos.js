/* ═══════════════════════════════════════════════════════════════
   MEDICIÓN DE INTERACCIONES · joaquinromero.com

   Registra en Google Analytics 4 lo que de verdad indica interés:
   qué servicio se abre, quién llega a contacto, qué proyecto se
   pulsa y hasta dónde se lee una página de servicio.

   No mide nada por su cuenta: se limita a llamar a `gtag`, que ya
   está sujeto al consentimiento de cookies. Si alguien rechaza,
   estas llamadas no salen del navegador.

   Se carga con `defer` en todas las páginas públicas.
   ═══════════════════════════════════════════════════════════════ */
(function(){
  "use strict";
  function ev(nombre, params){
    try{ if(typeof window.gtag === "function") window.gtag("event", nombre, params || {}); }catch(e){}
  }
  function texto(el){ return el ? (el.textContent||"").replace(/\s+/g," ").trim().slice(0,90) : ""; }

  /* ── 1 · CLICS ──────────────────────────────────────────────
     Un único escuchador delegado en el documento: no hay que
     enganchar nada a mano y funciona con lo que se pinte después
     (la sección de ideas, por ejemplo, se genera con JS). */
  document.addEventListener("click", function(e){
    var a = e.target && e.target.closest ? e.target.closest("a, button.sit") : null;
    if(!a) return;

    /* Las siete situaciones de la home: qué problema se reconoce. */
    if(a.tagName === "BUTTON" && a.classList.contains("sit")){
      ev("situacion_elegida", { situacion: texto(a.querySelector(".sit-t")) });
      return;
    }

    var href = a.getAttribute("href") || "";

    /* «Ver el método» / «Abrir el Reactor»: interés por un servicio. */
    if(a.classList.contains("srv-agentes-cta")){
      var tarjeta = a.closest(".srv");
      ev("ver_metodo", {
        servicio: texto(tarjeta && tarjeta.querySelector(".srv-t")) || href,
        destino: href });
      return;
    }

    /* Contacto: es la conversión real de este sitio. */
    if(/^mailto:/i.test(href) || /\/tarjeta\/?$/.test(href.split("?")[0])){
      ev("contacto", {
        via: /^mailto:/i.test(href) ? "correo" : "tarjeta",
        origen: location.pathname,
        etiqueta: texto(a) });
      return;
    }

    /* Logos de proyectos recientes. */
    var logo = a.querySelector && a.querySelector("img");
    if(logo && a.closest("#proyectos")){
      ev("logo_proyecto", { proyecto: (logo.getAttribute("alt")||"").slice(0,90) });
      return;
    }

    /* Sección de ideas, medios y casos prácticos. */
    if(a.closest("#blog")){
      var li = a.closest("li");
      ev("idea_abierta", {
        titulo: texto(a.querySelector(".c-t, .i-t, h3") || a),
        destino: href,
        tipo: li ? (li.className||"").slice(0,40) : "" });
      return;
    }

    /* Enlaces salientes: prensa, LinkedIn, fichas oficiales. */
    if(/^https?:\/\//i.test(href) && href.indexOf(location.host) === -1){
      ev("enlace_externo", { destino: href.slice(0,120), origen: location.pathname });
    }
  }, true);

  /* ── 2 · PROFUNDIDAD DE LECTURA ─────────────────────────────
     Solo en las páginas largas de servicio. Dice si un texto se
     lee o se abandona, que es la única forma de saber si una
     página vale lo que costó escribirla. */
  var larga = document.querySelector("main.rx-s, .rx-s");
  if(larga){
    var hitos = [25, 50, 75, 100], hechos = {}, ticking = false;
    function medir(){
      var h = document.documentElement;
      var alto = h.scrollHeight - h.clientHeight;
      if(alto <= 0) return;
      var pct = Math.round((h.scrollTop || document.body.scrollTop) / alto * 100);
      for(var i=0;i<hitos.length;i++){
        var m = hitos[i];
        if(pct >= m && !hechos[m]){
          hechos[m] = 1;
          ev("profundidad_lectura", { porcentaje: m, pagina: location.pathname });
        }
      }
    }
    window.addEventListener("scroll", function(){
      if(ticking) return; ticking = true;
      window.requestAnimationFrame(function(){ medir(); ticking = false; });
    }, { passive:true });
    medir();
  }

  /* ── 3 · TIEMPO ÚTIL EN PÁGINA DE SERVICIO ──────────────────
     GA4 ya da tiempo de interacción, pero no distingue entre
     abrir y leer. Esto marca los treinta segundos, que es el
     umbral a partir del cual alguien está leyendo de verdad. */
  if(larga){
    setTimeout(function(){ ev("lectura_sostenida", { pagina: location.pathname }); }, 30000);
  }
})();
