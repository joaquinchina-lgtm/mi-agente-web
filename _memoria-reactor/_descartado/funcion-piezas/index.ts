// ============================================================================
//  Edge Function: piezas-a-busquedas
//
//  ENTRADA: el texto que devuelve el AGENTE PIEZAS, pegado tal cual.
//  SALIDA:  una lista de piezas normalizadas, cada una con los términos de
//           disciplina con los que buscarla en el catálogo de I+D.
//
//  POR QUÉ ASÍ Y NO TRADUCIENDO EL PROBLEMA. Medido sobre la declaración real
//  del Reactor UPNA: de sus palabras discriminantes, ocho son verbos y
//  adjetivos —anticipar, provocar, explicar, fiable— que no aparecen en ninguna
//  ficha del catálogo. La salida del agente Piezas ya está mucho más cerca del
//  idioma del catálogo, así que es mejor punto de partida.
//
//  POR QUÉ SIGUE HACIENDO FALTA EL MODELO. Probadas las nueve piezas reales del
//  Reactor UPNA buscadas tal cual: aciertos claros (teledetección térmica para
//  los sensores; inferencia estadística para los árboles de decisión) mezclados
//  con ruido grave —"Papers sobre umbrales térmicos de mortalidad" devolvía
//  "Umbrales de la inclusión y el desarrollo", que casa por la palabra umbral en
//  otro sentido—. La pieza está escrita como LO QUE EL EQUIPO NECESITA; el
//  catálogo está escrito como LO QUE UN GRUPO SABE HACER. El modelo traduce
//  entre las dos, y de paso marca las piezas auxiliares, que no se buscan.
//
//  LO QUE NO HACE: no decide, no conecta y no firma. Propone; la persona edita.
//
//  SECRETOS (Supabase > Edge Functions > Secrets):
//    ANTHROPIC_API_KEY   obligatorio, de console.anthropic.com
//    ANTHROPIC_MODEL     opcional, por defecto claude-haiku-4-5-20251001
//    TOPE_DIARIO         opcional, por defecto 200
// ============================================================================

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SISTEMA = `Recibes la salida del "agente Piezas" de un programa de transferencia de I+D. Es una tabla o lista de piezas, cada una con nombre, categoría, escala inicial, qué revela y siguiente escala. El formato varía: puede venir como tabla, como lista o como texto corrido.

Tu trabajo es doble.

1. NORMALIZAR cada pieza a: nombre, categoria, escala, que_revela.
   - categoria: exactamente una de datos, tecnologica, conocimiento, auxiliar.
   - escala: exactamente una de mesa, comunidad, piloto, proceso.
   - Si el original no lo dice, deduce la más razonable.

2. TRADUCIR cada pieza a términos con los que buscarla en un catálogo de grupos de investigación de universidades españolas.
   El catálogo está escrito como LO QUE UN GRUPO SABE HACER —nombres de grupo, departamentos y líneas de investigación—, no como LO QUE UN EQUIPO NECESITA. Traduce de lo segundo a lo primero.
   - "Papers sobre umbrales térmicos de mortalidad" no se busca por "papers" ni por "umbrales": se busca por "epidemiologia ambiental mortalidad calor series temporales".
   - "Sensores low-cost de temperatura" se busca por "instrumentacion sensores ambientales teledeteccion termica microclima".
   - Entre 3 y 7 términos, minúscula, sin acentos necesarios, sin verbos, sin topónimos, sin marcas ni nombres de software.
   - Añade el sinónimo académico cuando la pieza usa lenguaje coloquial: "isla de calor" también es "clima urbano" y "termografia".

3. MARCAR buscar: false cuando ningún grupo de investigación puede aportar esa pieza. Es el caso de casi todas las auxiliares: software genérico, permisos, comités éticos, contactos institucionales. En esas, terminos va vacío.

Responde SOLO con JSON válido, sin texto alrededor:
{"piezas":[{"nombre":"...","categoria":"datos","escala":"mesa","que_revela":"...","terminos":"...","buscar":true}]}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const json = (cuerpo: unknown, estado = 200) =>
    new Response(JSON.stringify(cuerpo), {
      status: estado,
      headers: { ...CORS, "Content-Type": "application/json" },
    });

  try {
    const clave = Deno.env.get("ANTHROPIC_API_KEY");
    if (!clave) return json({ error: "Falta el secreto ANTHROPIC_API_KEY en Supabase > Edge Functions > Secrets." }, 500);
    const modelo = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-haiku-4-5-20251001";
    const tope = Number(Deno.env.get("TOPE_DIARIO") ?? "200");

    const cuerpo = await req.json().catch(() => ({}));
    const texto = String(cuerpo?.texto ?? "").trim();
    if (texto.length < 40) return json({ error: "Pega la salida del agente Piezas: hacen falta al menos 40 caracteres." }, 400);
    const recorte = texto.slice(0, 12000);

    const URL_SB = Deno.env.get("SUPABASE_URL")!;
    const SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const cab = { apikey: SERVICIO, Authorization: `Bearer ${SERVICIO}`, "Content-Type": "application/json" };

    // Tope diario: la clave publicable está en un repositorio público y esta
    // función cuesta dinero. Sin tope, cualquiera puede gastar el saldo.
    const rHoy = await fetch(`${URL_SB}/rest/v1/rpc/mr_traducciones_hoy`, { method: "POST", headers: cab, body: "{}" });
    const hoy = rHoy.ok ? Number(await rHoy.text()) : 0;
    if (hoy >= tope) return json({ error: `Tope de ${tope} traducciones alcanzado hoy. Revisa la tabla traduccion antes de subirlo.` }, 429);

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": clave, "anthropic-version": "2023-06-01", "Content-Type": "application/json" },
      body: JSON.stringify({ model: modelo, max_tokens: 2000, system: SISTEMA,
                             messages: [{ role: "user", content: recorte }] }),
    });

    const bruto = await r.text();
    const registrar = (campos: Record<string, unknown>) =>
      fetch(`${URL_SB}/rest/v1/traduccion`, { method: "POST", headers: cab,
        body: JSON.stringify({ problema: recorte.slice(0, 4000), ...campos }) });

    if (!r.ok) {
      await registrar({ error: bruto.slice(0, 500) });
      return json({ error: `El modelo ha devuelto ${r.status}. ${bruto.slice(0, 300)}` }, 502);
    }

    const datos = JSON.parse(bruto);
    const salida = (datos?.content ?? []).map((b: any) => b?.text ?? "").join("").trim();
    const a = salida.indexOf("{"), b = salida.lastIndexOf("}");
    let piezas: any = null;
    try { piezas = JSON.parse(salida.slice(a, b + 1))?.piezas ?? null; } catch { piezas = null; }
    if (!Array.isArray(piezas) || piezas.length === 0) {
      await registrar({ error: "respuesta no interpretable: " + salida.slice(0, 400) });
      return json({ error: "El modelo no ha devuelto piezas utilizables. Revisa que el texto pegado sea la salida del agente." }, 502);
    }

    // Saneado: los enum del esquema no se negocian con el modelo.
    const CAT = ["datos", "tecnologica", "conocimiento", "auxiliar"];
    const ESC = ["mesa", "comunidad", "piloto", "proceso"];
    piezas = piezas.map((p: any) => ({
      nombre: String(p?.nombre ?? "").slice(0, 300),
      categoria: CAT.includes(p?.categoria) ? p.categoria : "auxiliar",
      escala: ESC.includes(p?.escala) ? p.escala : "mesa",
      que_revela: String(p?.que_revela ?? "").slice(0, 1000),
      terminos: String(p?.terminos ?? "").slice(0, 300),
      buscar: p?.buscar === true && String(p?.terminos ?? "").trim().length > 0,
    })).filter((p: any) => p.nombre.length > 2);

    await registrar({ lineas: piezas });
    return json({ piezas, modelo });
  } catch (e) {
    return json({ error: "Fallo inesperado: " + String(e) }, 500);
  }
});
