/* ===========================================================================
   Capa de Memoria del Reactor sobre la cadena de agentes.

   No toca el motor: se engancha por el botón que la etapa 02 Piezas pinta
   junto al de adjuntar. Usa `state`, `save()` y `escapeHtml()` del motor, que
   viven en el mismo ámbito global.

   Qué hace: coge la salida del agente Piezas, la normaliza y la traduce al
   idioma del catálogo de I+D, la guarda como piezas del escenario, y por cada
   pieza busca quién la tiene. La máquina propone; una persona firma.
   =========================================================================== */

const MR = {
  URL:  "https://hugtfjbuzltvhysrjlxv.supabase.co",
  // Clave publicable. NUNCA pongas aquí la clave `service_role`.
  ANON: "sb_publishable_y_q6WtW5rfR5A_LOE7-Q0g_OXeRjcW0"
};
const db = supabase.createClient(MR.URL, MR.ANON);
const esc = t => (typeof escapeHtml === 'function' ? escapeHtml(String(t ?? ''))
  : String(t ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])));

let mpPiezas = null;   // piezas traducidas, aún sin guardar
let mpGuardadas = [];  // piezas ya en la base

const SYS_MAPEO = `Recibes la salida del agente Piezas del Reactor de Innovación: una tabla o lista de piezas con nombre, categoría, escala inicial, qué revela y siguiente escala. El formato varía.

Haces dos cosas.

1. NORMALIZAR cada pieza a: nombre, categoria, escala, que_revela, siguiente_escala.
   - categoria: exactamente una de datos, tecnologica, conocimiento, auxiliar.
   - escala: exactamente una de mesa, comunidad, piloto, proceso.
   - Si el original no lo dice, deduce la más razonable.

2. TRADUCIR cada pieza a términos con los que buscarla en un catálogo de grupos de investigación de universidades españolas. El catálogo está escrito como LO QUE UN GRUPO SABE HACER (nombres de grupo, departamentos, líneas de investigación), no como LO QUE UN EQUIPO NECESITA. Traduce de lo segundo a lo primero.
   - "Papers sobre umbrales térmicos de mortalidad" no se busca por "papers" ni por "umbrales": se busca por "epidemiologia ambiental mortalidad calor series temporales".
   - "Sensores low-cost de temperatura" se busca por "instrumentacion sensores ambientales teledeteccion termica microclima".
   - Entre 3 y 7 términos, minúscula, sin verbos, sin topónimos, sin marcas ni nombres de software.
   - Añade el sinónimo académico si la pieza usa lenguaje coloquial: "isla de calor" también es "clima urbano" y "termografia".

3. MARCAR buscar: false cuando ningún grupo de investigación puede aportar esa pieza: software genérico, permisos, comités éticos, contactos institucionales. En esas, terminos va vacío.

Responde SOLO con JSON válido, sin texto alrededor:
{"piezas":[{"nombre":"...","categoria":"datos","escala":"mesa","que_revela":"...","siguiente_escala":"...","terminos":"...","buscar":true}]}`;

/* --- armazón del panel ------------------------------------------------- */
function mpPanel() {
  let p = document.getElementById('mp');
  if (p) return p;
  p = document.createElement('div');
  p.id = 'mp'; p.className = 'mp-panel';
  p.innerHTML = `<div class="mp-caja">
    <button class="mp-cerrar" onclick="cerrarMapeo()">Cerrar</button>
    <h2>Mapeo de recursos de I+D</h2>
    <p style="margin:2px 0 0;font-size:14.5px;color:#5c6360">
      7.795 grupos de 38 universidades públicas. La máquina propone; la conexión
      sólo existe cuando una persona la firma con nombre y motivo. Un descarte
      razonado vale tanto como un acierto: es lo que hoy se pierde al acabar la edición.</p>
    <div class="mp-fila">
      <label class="mp-est">Firma:</label>
      <input id="mp-firmante" placeholder="Nombre y apellido" autocomplete="name">
      <label class="mp-est">Organización:</label>
      <select id="mp-org"></select>
      <button class="mp-b" id="mp-crear">Crear escenario desde el problema</button>
    </div>
    <div class="mp-fila">
      <button class="mp-b p" id="mp-leer" disabled>Leer las piezas de la etapa 02</button>
      <button class="mp-b" id="mp-guardar" disabled>Guardar en la Memoria</button>
      <span class="mp-est" id="mp-est"></span>
    </div>
    <div id="mp-lista"></div>
  </div>`;
  document.body.appendChild(p);
  p.addEventListener('click', e => { if (e.target === p) cerrarMapeo(); });

  const g = document.getElementById('mp-firmante');
  try { g.value = localStorage.getItem('mr_firmante') || ''; } catch (e) {}
  g.addEventListener('input', () => { try { localStorage.setItem('mr_firmante', g.value); } catch (e) {} });

  document.getElementById('mp-crear').addEventListener('click', crearEscenario);
  document.getElementById('mp-leer').addEventListener('click', leerPiezas);
  document.getElementById('mp-guardar').addEventListener('click', guardarPiezas);
  return p;
}

const mpEst = (t, c) => { const e = document.getElementById('mp-est'); e.textContent = t; e.className = 'mp-est' + (c ? ' ' + c : ''); };
function firmante() {
  const v = document.getElementById('mp-firmante').value.trim();
  if (!v) { document.getElementById('mp-firmante').focus(); throw new Error('Escribe tu nombre antes de firmar.'); }
  return v;
}

async function abrirMapeo() {
  mpPanel().classList.add('on');
  const orgs = await db.rpc('mr_organizaciones');
  const sel = document.getElementById('mp-org');
  sel.innerHTML = '';
  (orgs.data || []).forEach(o => { const x = document.createElement('option'); x.value = o.id; x.textContent = o.nombre; sel.appendChild(x); });
  if (state.escenarioId) {
    document.getElementById('mp-crear').textContent = 'Escenario ya creado';
    document.getElementById('mp-crear').disabled = true;
    document.getElementById('mp-leer').disabled = false;
    mpEst('Escenario en curso.');
    await pintarGuardadas();
  } else {
    mpEst(state.outputs.problema ? 'Crea el escenario a partir del problema de la etapa 01.'
                                 : 'Primero ejecuta la etapa 01 Problema.', state.outputs.problema ? '' : 'mal');
  }
}
function cerrarMapeo() { const p = document.getElementById('mp'); if (p) p.classList.remove('on'); }

async function crearEscenario() {
  const decl = (state.outputs.problema || '').trim();
  if (!decl) return mpEst('No hay salida de la etapa 01 Problema.', 'mal');
  const org = document.getElementById('mp-org').value;
  if (!org) return mpEst('Hace falta una organización.', 'mal');
  mpEst('Creando…');
  // La declaración es la primera parte de la salida del agente: lo demás son
  // variantes y verificadores, que ya viven en el texto de la etapa.
  const titulo = decl.split('\n').map(x => x.trim()).filter(Boolean)[1] || 'Escenario 1';
  const { data, error } = await db.rpc('mr_crear_escenario', {
    p_organizacion_id: org, p_declaracion: decl.slice(0, 4000),
    p_titulo: titulo.slice(0, 200), p_modulo: 2, p_visibilidad: 'cliente'
  });
  if (error) return mpEst(error.message, 'mal');
  state.escenarioId = data; save();
  document.getElementById('mp-crear').disabled = true;
  document.getElementById('mp-crear').textContent = 'Escenario ya creado';
  document.getElementById('mp-leer').disabled = false;
  mpEst('Escenario creado. Ahora lee las piezas.', 'bien');
}

async function leerPiezas() {
  const txt = (state.outputs.piezas || '').trim();
  if (txt.length < 40) return mpEst('La etapa 02 Piezas todavía no tiene salida.', 'mal');
  mpEst('Traduciendo las piezas al idioma del catálogo…');
  document.getElementById('mp-leer').disabled = true;
  try {
    const r = await fetch(BACKEND + '/api/ask', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ system: SYS_MAPEO, message: txt.slice(0, 12000), model: 'gpt-4o-mini', temperature: 0.2 })
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || d.error) throw new Error((d.error && d.error.message) || ('HTTP ' + r.status));
    const t = String(d.reply || '');
    const a = t.indexOf('{'), b = t.lastIndexOf('}');
    let ps = null;
    try { ps = JSON.parse(t.slice(a, b + 1)).piezas; } catch (e) { ps = null; }
    if (!Array.isArray(ps) || !ps.length) throw new Error('El agente no ha devuelto piezas utilizables.');
    const CAT = ['datos', 'tecnologica', 'conocimiento', 'auxiliar'], ESC = ['mesa', 'comunidad', 'piloto', 'proceso'];
    mpPiezas = ps.map(p => ({
      nombre: String(p.nombre || '').slice(0, 300),
      categoria: CAT.includes(p.categoria) ? p.categoria : 'auxiliar',
      escala: ESC.includes(p.escala) ? p.escala : 'mesa',
      que_revela: String(p.que_revela || ''), siguiente_escala: String(p.siguiente_escala || ''),
      terminos: String(p.terminos || '')
    })).filter(p => p.nombre.length > 2);
    pintarPropuestas();
    document.getElementById('mp-guardar').disabled = false;
    mpEst(mpPiezas.length + ' pieza(s). Revisa los términos antes de guardar.', 'bien');
  } catch (e) { mpEst(String(e.message || e), 'mal'); }
  finally { document.getElementById('mp-leer').disabled = false; }
}

function pintarPropuestas() {
  const L = document.getElementById('mp-lista'); L.innerHTML = '';
  mpPiezas.forEach((p, i) => {
    const d = document.createElement('div'); d.className = 'mp-pieza';
    d.innerHTML = `<span class="mp-cat">${esc(p.categoria)}</span><b>${esc(p.nombre)}</b>
      <div class="mp-meta">escala ${esc(p.escala)}${p.que_revela ? ' · ' + esc(p.que_revela) : ''}</div>
      <input class="mp-term" data-t="${i}" value="${esc(p.terminos)}"
        placeholder="sin términos: ningún grupo de investigación aporta esta pieza">`;
    L.appendChild(d);
  });
  L.querySelectorAll('[data-t]').forEach(inp =>
    inp.addEventListener('input', () => { mpPiezas[+inp.dataset.t].terminos = inp.value; }));
}

async function guardarPiezas() {
  if (!state.escenarioId || !mpPiezas) return;
  mpEst('Guardando…');
  const { error } = await db.rpc('mr_guardar_piezas', { p_escenario_id: state.escenarioId, p_piezas: mpPiezas });
  if (error) return mpEst(error.message, 'mal');
  mpPiezas = null;
  document.getElementById('mp-guardar').disabled = true;
  await pintarGuardadas();
  mpEst('Piezas guardadas. Ahora busca quién tiene cada una.', 'bien');
}

async function pintarGuardadas() {
  const L = document.getElementById('mp-lista'); L.innerHTML = '';
  const { data, error } = await db.rpc('mr_piezas', { p_escenario_id: state.escenarioId });
  if (error) return mpEst(error.message, 'mal');
  mpGuardadas = data || [];
  mpGuardadas.forEach(p => {
    const buscable = (p.terminos || '').trim().length > 0;
    const d = document.createElement('div'); d.className = 'mp-pieza';
    d.innerHTML = `<span class="mp-cat">${esc(p.categoria)}</span><b>${esc(p.nombre)}</b>
      <div class="mp-meta">escala ${esc(p.escala_inicial)}${p.firmadas ? ' · <b>' + p.firmadas + ' firmada(s)</b>' : p.propuestas ? ' · ' + p.propuestas + ' sin firmar' : ''}</div>
      ${buscable ? `<div class="mp-meta">${esc(p.terminos)}</div>
        <div class="mp-fila" style="margin:8px 0 0">
          <button class="mp-b" data-buscar="${p.id}" data-q="${esc(p.terminos)}">Buscar quién la tiene</button>
        </div>`
      : `<div class="mp-meta">Sin términos: ningún grupo de investigación aporta esta pieza.</div>`}
      <div id="mp-r-${p.id}"></div>`;
    L.appendChild(d);
  });
  L.querySelectorAll('[data-buscar]').forEach(b =>
    b.addEventListener('click', () => buscarPieza(b.dataset.buscar, b.dataset.q)));
  for (const p of mpGuardadas) if (p.propuestas || p.firmadas) await pintarConexiones(p.id);
}

async function buscarPieza(piezaId, q) {
  const cont = document.getElementById('mp-r-' + piezaId);
  cont.innerHTML = '<p class="mp-est">Buscando y proponiendo…</p>';
  const { data, error } = await db.rpc('proponer_conexiones', {
    p_escenario_id: state.escenarioId, p_consulta: q, p_limite: 8, p_pieza_id: piezaId
  });
  if (error) { cont.innerHTML = '<p class="mp-est mal">' + esc(error.message) + '</p>'; return; }
  await pintarConexiones(piezaId);
  mpEst(data + ' propuesta(s) nueva(s) para esa pieza. Sin firmar no valen nada.', 'bien');
}

async function pintarConexiones(piezaId) {
  const cont = document.getElementById('mp-r-' + piezaId);
  if (!cont) return;
  const { data, error } = await db.rpc('mr_conexiones', { p_escenario_id: state.escenarioId });
  if (error) { cont.innerHTML = '<p class="mp-est mal">' + esc(error.message) + '</p>'; return; }
  const mias = (data || []).filter(c => c.pieza_id === piezaId);
  if (!mias.length) { cont.innerHTML = ''; return; }
  cont.innerHTML = '<ul class="mp-res">' + mias.map(c => {
    const cab = `<span class="uni">${esc(c.universidad)}</span><b>${esc(c.recurso)}</b>
      <div class="mp-meta">${c.responsable ? esc(c.responsable) : ''}${c.url ? (c.responsable ? ' · ' : '') + '<a href="' + esc(c.url) + '" target="_blank" rel="noopener">ficha</a>' : ''}</div>`;
    if (c.firmado_por) {
      return `<li>${cab}<div class="mp-sello"><span class="${c.veredicto === 'sirve' ? 's' : 'n'}">${c.veredicto === 'sirve' ? 'Sirve' : 'No sirve'}</span> — ${esc(c.razon)}<br><b>${esc(c.firmado_por)}</b>, ${new Date(c.firmado_en).toLocaleDateString('es-ES')}</div></li>`;
    }
    return `<li>${cab}<div class="mp-firma">
      <input data-razon="${c.id}" placeholder="Por qué sirve, o por qué no">
      <button class="mp-b mp-si" data-firmar="${c.id}" data-v="sirve" data-p="${piezaId}">Sirve</button>
      <button class="mp-b mp-no" data-firmar="${c.id}" data-v="no_sirve" data-p="${piezaId}">No sirve</button>
    </div></li>`;
  }).join('') + '</ul>';

  cont.querySelectorAll('[data-firmar]').forEach(b => b.addEventListener('click', async () => {
    let quien;
    try { quien = firmante(); } catch (e) { return mpEst(e.message, 'mal'); }
    const razon = cont.querySelector(`[data-razon="${b.dataset.firmar}"]`).value.trim();
    mpEst('Firmando…');
    const { error } = await db.rpc('firmar_conexion', {
      p_conexion_id: b.dataset.firmar, p_veredicto: b.dataset.v, p_razon: razon, p_firmante: quien
    });
    if (error) return mpEst(error.message, 'mal');
    await pintarConexiones(b.dataset.p);
    mpEst('Firmada.', 'bien');
  }));
}
