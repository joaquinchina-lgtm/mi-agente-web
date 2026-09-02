/* ===========================================================================
   Guardia de sesión del área interna.

   No monta un login nuevo: /interno/index.html ya tiene uno (enlace por correo
   y contraseña). Como esta página vive en el mismo origen y usa el mismo
   proyecto de Supabase, la sesión ya está en el navegador. Aquí sólo se
   comprueba, y si no la hay se manda a la puerta que ya existe.

   Falla cerrado: el documento nace con <html class="cerrado">, que oculta todo
   menos este cartel. Si este script no llega a ejecutarse, no se ve nada.
   =========================================================================== */
(async () => {
  const cartel = document.getElementById('guardia');
  const volver = './#/admin';

  const abrir = (sesion) => {
    document.documentElement.classList.remove('cerrado');
    if (cartel) cartel.remove();
    const fila = document.querySelector('.kick-fila');
    if (fila && !document.getElementById('gu-quien')) {
      const d = document.createElement('div');
      d.id = 'gu-quien';
      d.className = 'gu-quien';
      d.innerHTML = '<span></span> <button type="button">Salir</button>';
      d.querySelector('span').textContent = sesion.user.email || 'sesión abierta';
      d.querySelector('button').onclick = async () => {
        await db.auth.signOut();
        location.href = volver;
      };
      fila.appendChild(d);
    }
  };

  const cerrar = (titulo, detalle) => {
    const c = document.getElementById('guardia');
    if (!c) return;
    c.innerHTML =
      '<div class="gu-caja"><h1></h1><p class="gu-p"></p>' +
      '<p><a class="gu-b" href="' + volver + '">Ir al acceso del área interna</a></p>' +
      '<p class="gu-nota">Se entra una sola vez: la sesión vale también para el resto ' +
      'del área interna. Si acabas de entrar en otra pestaña, recarga esta.</p></div>';
    c.querySelector('h1').textContent = titulo;
    c.querySelector('.gu-p').textContent = detalle;
  };

  if (typeof db === 'undefined' || !db.auth) {
    cerrar('No se ha podido comprobar la sesión',
           'La librería de Supabase no ha cargado. Recarga la página; si se repite, revisa la conexión.');
    return;
  }

  try {
    const { data, error } = await db.auth.getSession();
    if (error) throw error;
    if (data && data.session) abrir(data.session);
    else cerrar('Esta página es privada',
                'No hay ninguna sesión abierta en este navegador.');
  } catch (e) {
    cerrar('No se ha podido comprobar la sesión', String((e && e.message) || e));
  }

  /* Si la sesión se cierra en otra pestaña, esta se vuelve a cerrar sola. */
  db.auth.onAuthStateChange((evt, sesion) => {
    if (evt === 'SIGNED_OUT' || !sesion) {
      document.documentElement.classList.add('cerrado');
      const q = document.getElementById('gu-quien'); if (q) q.remove();
      if (!document.getElementById('guardia')) {
        const c = document.createElement('div'); c.id = 'guardia'; document.body.appendChild(c);
      }
      cerrar('La sesión se ha cerrado', 'Se cerró la sesión en esta u otra pestaña.');
    }
  });
})();
