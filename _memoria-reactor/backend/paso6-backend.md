# Paso 6 · Backend `jr-gpt-backend-1.onrender.com`

Comprobado hoy contra el servicio en vivo, no leído del código.

---

## Primero, dos cosas que no esperabas

### A. Hacer el repositorio privado NO cerró los datos

El repositorio ya es privado. El **servicio** sigue abierto:

```
GET https://jr-gpt-backend-1.onrender.com/api/csv_search?query=navarra
→ 200 · 362 fichas · sin autenticación · CORS abierto a cualquiera
```

Ficheros que sirve ahora mismo a quien los pida:

```
UNAV_groups.csv          ← universidad privada, la excluiste a propósito de tu catálogo
UIB_groups.csv
UPNA_groups.csv
25_navarra_pymes_preliminar.csv
25_aragon_pymes_preliminar.csv
25_paisvasco_pymes_preliminar.csv
500_agrofood_pymes_fullcols_vFinal.csv
500_biomed_pymes_fullcols_vFinal.csv
500_deeptech_pymes_fullcols_vFinal.csv
500_digital_pymes_fullcols_DEF.csv
500_energia_pymes_fullcols_vFinal.csv
```

Y esto **no es un descuido**: tu propia `gpts.html`, que es pública, usa
`csv_search` y `csv_report`. Es una funcionalidad tuya. Lo que hay que decidir
no es si la apagas, sino **qué ficheros alimenta**.

La corrección mínima que no rompe nada: **borrar `UNAV_groups.csv` de la
carpeta `knowledge/` del backend**. Un fichero. `gpts.html` sigue funcionando.

Aparte: `/api/csv_report` genera un PDF con tu nombre, tu correo y tu teléfono
móvil, y cualquiera puede generarlo con una URL. Es tu tarjeta de visita, así
que puede que te dé igual; conviene que sea una decisión y no un descuido.

### B. `/api/save` no guarda nada

```
GET /health → {"db": false, "knowledge": 4040, "status": "ok"}
```

`DATABASE_URL` no está configurada en Render. Cada vez que la cadena de agentes
intenta guardar una etapa, el backend devuelve un 500. Llevas quién sabe cuánto
creyendo que se registra el trabajo de las sesiones. **No se registra ninguno.**

---

## El encargo: el tope de gasto

### Lo que está mal

**1. El cliente elige el modelo.** Verificado en vivo:

```
POST /api/ask  {"message":"Di solo OK","model":"gpt-4o"}  →  200 {"reply":"OK"}
```

La línea culpable:

```python
model = (data.get("model") or OPENAI_MODEL).strip()
```

Cualquiera puede pedir el modelo más caro del catálogo contra tu clave.

**2. Cero límite de peticiones.** Ni por IP, ni por hora, ni por tamaño. Un
bucle de tres líneas agota tu tope de OpenAI en una tarde.

**3. CORS abierto.** `ALLOWED_ORIGINS` trae `"*"` en el conjunto por defecto,
así que `cors_origins` acaba siendo `"*"`. Curiosamente **`joaquinromero.com`
no está en la lista**: funciona solo gracias al comodín. Si quitas el comodín
sin añadir tu dominio, tumbas tu propia web.

**4. `ALLOW_CHAT`** se define y no se usa en ninguna parte. Código muerto.

### Lo que hay que entender antes de tocar nada

Un contador en memoria en el plan gratuito de Render **se borra cada vez que el
servicio se duerme**, y se duerme solo tras unos minutos sin tráfico. Es un
freno, no un muro. **Tu muro de verdad es el tope de gasto que ya pusiste en
OpenAI.** Lo que sigue reduce la probabilidad de llegar a él por accidente o por
abuso casual; no te protege de alguien decidido.

Si algún día esto importa de verdad, la respuesta no es un contador: es una
clave por cliente o un proxy con estado. Hoy no toca.

---

## Los cambios, exactos

Cuatro ediciones en `backend.py`. Las he escrito para que las pegues en el
editor web de GitHub: cada una identifica una línea única del fichero.

### Edición 1 · después de la línea `DEBUG = os.getenv(...)`

Añade debajo:

```python
# Modelos que este servicio acepta. Cualquier otro se ignora y se usa el de
# por defecto: asi nadie puede pedir un modelo caro desde fuera.
MODELOS_PERMITIDOS = set(
    m.strip() for m in os.getenv("MODELOS_PERMITIDOS", "gpt-4o-mini").split(",") if m.strip()
)
# Freno por IP y hora, y tamano maximo de lo que se manda al modelo.
# El contador vive en memoria: en Render gratuito se reinicia cuando el
# servicio se duerme. Es un freno, no un muro.
TOPE_HORA   = int(os.getenv("TOPE_HORA", "120"))
MAX_MENSAJE = int(os.getenv("MAX_MENSAJE", "12000"))
MAX_SISTEMA = int(os.getenv("MAX_SISTEMA", "20000"))
```

### Edición 2 · sustituye el bloque de `ALLOWED_ORIGINS`

Cambia la línea que empieza por `ALLOWED_ORIGINS = {"https://joaquinchina-lgtm.github.io"`
por esta, **con tu dominio dentro y sin comodín**:

```python
    ALLOWED_ORIGINS = {"https://joaquinromero.com",
                       "https://joaquinchina-lgtm.github.io",
                       "http://localhost:5173", "http://127.0.0.1:5500"}
```

### Edición 3 · justo antes de `@app.route("/api/ask"...)`

```python
import time as _time
from collections import defaultdict as _dd
_VISITAS = _dd(list)

def _ip() -> str:
    reenviada = request.headers.get("X-Forwarded-For", "")
    return (reenviada.split(",")[0].strip() if reenviada else request.remote_addr) or "?"

def _pasa_el_tope(ip: str) -> bool:
    """Ventana deslizante de una hora. Si algun dia hay mas de un worker,
    esto cuenta por worker."""
    ahora = _time.time()
    v = _VISITAS[ip]
    v[:] = [t for t in v if ahora - t < 3600]
    if len(v) >= TOPE_HORA:
        return False
    v.append(ahora)
    return True
```

### Edición 4 · dentro de `def ask():`

Sustituye estas tres líneas:

```python
    msg = (data.get("message") or "").strip()
    system = data.get("system") or "Eres un asistente útil y riguroso."
    model = (data.get("model") or OPENAI_MODEL).strip()
```

por estas:

```python
    if not _pasa_el_tope(_ip()):
        return jsonify(error={"message": "Demasiadas peticiones desde esta direccion. Prueba dentro de un rato."}), 429
    msg = (data.get("message") or "").strip()[:MAX_MENSAJE]
    system = str(data.get("system") or "Eres un asistente útil y riguroso.")[:MAX_SISTEMA]
    # El cliente NO elige el modelo.
    pedido = (data.get("model") or "").strip()
    model = pedido if pedido in MODELOS_PERMITIDOS else OPENAI_MODEL
```

---

## Y en Render, ahora mismo, sin tocar código

Settings → Environment:

| variable | valor | para qué |
|---|---|---|
| `CORS_ALLOW_ORIGINS` | `https://joaquinromero.com,https://joaquinchina-lgtm.github.io` | quita el comodín hoy, sin esperar al despliegue |
| `MODELOS_PERMITIDOS` | `gpt-4o-mini` | tras la edición 1 |
| `TOPE_HORA` | `120` | tras la edición 3 |
| `DATABASE_URL` | la cadena de conexión de tu Supabase | para que `/api/save` deje de fallar |

`CORS_ALLOW_ORIGINS` funciona **ya**, sin ningún cambio de código: el fichero
actual lo lee si existe. Es lo más barato que puedes hacer en un minuto.

---

## Cómo comprobar que ha funcionado

Con el servicio ya desplegado, desde la consola del navegador en tu web:

```js
// 1. debe responder con gpt-4o-mini aunque pidas otro modelo
await fetch('https://jr-gpt-backend-1.onrender.com/api/ask',{method:'POST',
  headers:{'Content-Type':'application/json'},
  body:JSON.stringify({message:'di OK',system:'responde OK',model:'gpt-4o'})}).then(r=>r.json())

// 2. la base ya no debe decir false
await fetch('https://jr-gpt-backend-1.onrender.com/health').then(r=>r.json())
```

El punto 1 seguirá devolviendo `OK`: lo que cambia es **con qué modelo**, y eso
no se ve en la respuesta. Para verificarlo de verdad, mira el desglose por
modelo en tu panel de OpenAI al día siguiente.
