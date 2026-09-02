# -*- coding: utf-8 -*-
"""Genera interno/memoria.html a partir de reactor.html.

El motor de la cadena NO se reescribe: se copia literal. Sólo se parchea lo
imprescindible (clave de almacenamiento distinta y un botón en la etapa Piezas)
y se añade encima la capa de Memoria del Reactor. Así, cuando reactor.html
cambie, se vuelve a ejecutar esto y la copia sigue siendo fiel.
"""
import io, re

s = io.open('reactor.html', encoding='utf8').read()

# --- trozos que se copian literalmente ---
CSS = [(255, 7038), (15629, 17517), (17519, 21695)]
css = "\n".join(s[a:b] for a, b in CSS)

i_app = s.find('<div class="app">')
i_prompts = s.find('<script type="text/plain" id="sys-problema"')
markup = s[i_app:i_prompts] + '\n</div><!-- cierra .app: en reactor.html se cierra despues de los prompts -->\n'

i_eng = s.find('<script>', i_prompts)
j_eng = s.find('</script>', i_eng)
prompts = s[i_prompts:i_eng]
motor = s[i_eng + 8:j_eng]

# --- parche 1: almacenamiento propio, para no pisar el de la página pública ---
m = re.search(r"const KEY\s*=\s*['\"]([^'\"]+)['\"]", motor)
assert m, "no encuentro la clave de almacenamiento"
motor = motor.replace(m.group(0), "const KEY = 'reactor-interno-v1'")
m2 = re.search(r"localStorage\.getItem\('reactor-sesion'\)", motor)
if m2:
    motor = motor.replace("'reactor-sesion'", "'reactor-interno-sesion'")

# --- parche 2: el botón de mapeo, junto al de adjuntar, sólo en Piezas ---
viejo = """<div style="margin-top:7px"><button class="attach-btn" onclick="pickFile('mat-${a.id}')">Adjuntar archivo</button></div>"""
nuevo = """<div style="margin-top:7px"><button class="attach-btn" onclick="pickFile('mat-${a.id}')">Adjuntar archivo</button>${a.id==='piezas'?' <button class="attach-btn mapeo-btn" onclick="abrirMapeo()">Mapeo de recursos de I+D</button>':''}</div>"""
assert viejo in motor, "no encuentro la fila de botones de matices"
motor = motor.replace(viejo, nuevo)

extra_css = """
.wrap-i{max-width:1080px;margin:0 auto;padding:30px 24px 0}
.kick-fila{display:flex;align-items:center;justify-content:space-between;gap:16px;margin:0 0 10px}
.kick-i{font:600 12px/1 'Inter',sans-serif;letter-spacing:.14em;text-transform:uppercase;color:#5c6360;margin:0}
.a-web{font:600 11px/1 'Inter',sans-serif;letter-spacing:.12em;text-transform:uppercase;color:#5c6360;text-decoration:none;border:1px solid #e4e7e6;padding:9px 13px;white-space:nowrap}
.a-web:hover{color:#22525C;border-color:#32717E}
.aviso-i{background:#EAF0F1;padding:14px 16px;font-size:14.5px;line-height:1.45;color:#20302c;margin:0 0 18px;max-width:1080px}
.mapeo-btn{border-color:#32717E !important;color:#22525C !important;font-weight:600}
.mp-panel{position:fixed;inset:0;background:rgba(12,18,17,.55);z-index:60;display:none;overflow:auto;padding:26px 16px}
.mp-panel.on{display:block}
.mp-caja{max-width:940px;margin:0 auto;background:#fff;padding:24px 26px 32px;border-radius:3px}
.mp-caja h2{font-family:'Archivo',sans-serif;font-size:22px;margin:0 0 4px}
.mp-cerrar{float:right;border:1px solid #e4e7e6;background:#fff;font:inherit;font-size:14px;padding:7px 12px;cursor:pointer}
.mp-fila{display:flex;gap:10px;flex-wrap:wrap;align-items:center;margin:14px 0}
.mp-fila select,.mp-fila input{border:1px solid #e4e7e6;padding:9px 11px;font:inherit;font-size:14.5px;min-width:200px}
.mp-b{border:1px solid #e4e7e6;background:#fff;color:#41504b;font:inherit;font-size:14px;padding:9px 14px;cursor:pointer}
.mp-b.p{background:#16211f;color:#fff;border-color:#16211f}
.mp-b:disabled{opacity:.45;cursor:default}
.mp-est{font-size:13.5px;color:#5c6360}
.mp-est.mal{color:#9b4a3d;font-weight:600}
.mp-est.bien{color:#2f6b4f;font-weight:600}
.mp-pieza{border-top:1px solid #eceae4;padding:13px 0}
.mp-cat{font:600 10.5px/1 'Inter',sans-serif;letter-spacing:.1em;text-transform:uppercase;color:#22525C;border:1px solid #e4e7e6;padding:4px 7px;margin-right:9px}
.mp-pieza b{font-size:15px}
.mp-meta{font-size:13px;color:#5c6360;margin-top:3px}
.mp-term{width:100%;margin-top:7px;border:1px solid #e4e7e6;padding:8px 10px;font:inherit;font-size:14px}
.mp-res{margin:9px 0 0 0;padding:0;list-style:none}
.mp-res li{border-top:1px dotted #e4e7e6;padding:9px 0;font-size:14px}
.mp-res .uni{font:600 10.5px/1 'Inter',sans-serif;letter-spacing:.1em;color:#22525C;margin-right:8px}
.mp-firma{display:flex;gap:7px;margin-top:7px;flex-wrap:wrap}
.mp-firma input{flex:1;min-width:220px;border:1px solid #e4e7e6;padding:7px 10px;font:inherit;font-size:13.5px}
.mp-si{color:#2f6b4f;border-color:#cfe0d6}
.mp-no{color:#9b4a3d;border-color:#e8d5d1}
.mp-sello{font-size:13.5px;margin-top:6px}
.mp-sello .s{color:#2f6b4f;font-weight:600}
.mp-sello .n{color:#9b4a3d;font-weight:600}

/* --- guardia de sesion: el documento nace cerrado y solo se abre con sesion --- */
html.cerrado body > *:not(#guardia){display:none !important}
#guardia{max-width:560px;margin:14vh auto 0;padding:0 22px}
.gu-caja{border:1px solid #e4e7e6;padding:26px 26px 22px}
.gu-caja h1{font-family:'Archivo',sans-serif;font-size:22px;margin:0 0 8px}
.gu-p{margin:0 0 16px;color:#5c6360;font-size:15px}
.gu-b{display:inline-block;background:#16211f;color:#fff;text-decoration:none;font-size:14px;padding:10px 16px}
.gu-nota{font-size:13px;color:#5c6360;margin:16px 0 0;line-height:1.45}
.gu-quien{display:flex;align-items:center;gap:9px;font-size:12.5px;color:#5c6360}
.gu-quien button{border:1px solid #e4e7e6;background:#fff;font:inherit;font-size:12.5px;padding:6px 10px;cursor:pointer}
.gu-quien button:hover{border-color:#32717E;color:#22525C}
"""

import os
AQUI = os.path.dirname(os.path.abspath(__file__))
capa    = io.open(os.path.join(AQUI, 'capa_memoria.js'), encoding='utf8').read()
guardia = io.open(os.path.join(AQUI, 'guardia.js'),      encoding='utf8').read()

# Tamano del catalogo. Se comprueba con:
#   select count(*), count(distinct universidad) from recurso;
FICHAS, UNIVERSIDADES = "8.122", "40"

html = f"""<!doctype html>
<html lang="es" class="cerrado">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<!-- El área privada no debe aparecer en buscadores. No sustituye a la
     autenticación: es higiene, para que la consola no se indexe. -->
<meta name="robots" content="noindex, nofollow, noarchive">
<title>Memoria del Reactor · Área interna</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@300..800&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js"></script>
{css}
<style>{extra_css}</style>
</head>
<body>

<div id="guardia"><div class="gu-caja"><h1>Comprobando la sesión…</h1><p class="gu-p">Un momento.</p></div></div>

<div class="wrap-i">
  <div class="kick-fila"><p class="kick-i">Área interna</p><a class="a-web" href="./"><span aria-hidden="true">&larr;</span> Volver al área interna</a></div>
  <div class="aviso-i">
    <p style="margin:0 0 8px"><b>Esta es la cadena completa, en privado.</b> Es el mismo motor que la página pública, con su propio historial: lo que hagas aquí no toca lo de <code>reactor.html</code>.</p>
    <p style="margin:0"><b>En la etapa 02 Piezas</b>, junto a «Adjuntar archivo», tienes <b>Mapeo de recursos de I+D</b>: busca en {FICHAS} grupos de investigación de {UNIVERSIDADES} universidades quién tiene cada pieza, y deja constancia firmada de lo que sirve y de lo que no.</p>
  </div>
</div>

{markup}
{prompts}
<script>
{motor}
</script>
<script>
{capa}
</script>
<script>
{guardia}
</script>
</body>
</html>
"""
io.open('interno/memoria.html', 'w', encoding='utf8').write(html)
print("memoria.html generado:", len(html), "caracteres")
print("  css:", len(css), "| markup:", len(markup), "| prompts:", len(prompts), "| motor:", len(motor), "| capa:", len(capa))
