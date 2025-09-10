// /api/jr-agent.js  (Vercel Function - Node.js runtime)
module.exports = async (req, res) => {
  // CORS para que tu GitHub Pages pueda llamar a Vercel
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const question = (body.question || '').trim();
    if (!question) return res.status(400).json({ error: "Falta el campo 'question'." });

    // Llamada segura a OpenAI (Chat Completions). Tu API key va en variable de entorno.
    const r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type':'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: 'Responde en español, tono claro y directo. Eres asesor en innovación/transferencia.' },
          { role: 'user', content: question }
        ],
        temperature: 0.3
      })
    });

    if (!r.ok) {
      const errTxt = await r.text();
      return res.status(r.status).json({ error: 'OpenAI error', detail: errTxt });
    }

    const data = await r.json();
    const text = data?.choices?.[0]?.message?.content?.trim() || 'Sin respuesta.';
    res.setHeader('Content-Type','text/plain; charset=utf-8');
    return res.status(200).send(text);
  } catch (e) {
    return res.status(500).json({ error: 'Server error', detail: String(e) });
  }
};
