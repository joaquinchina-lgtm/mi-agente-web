-- 0008_cerrar_area_privada.sql
--
-- Hasta ahora TODAS las funciones del Reactor estaban concedidas a PUBLIC y a
-- anon. Con la clave publicable en un repositorio publico, eso significa que
-- cualquiera podia leer los escenarios de clientes, las piezas, las conexiones
-- y las firmas, y ademas escribir en ellos.
--
-- Criterio de corte:
--   PUBLICO   el catalogo de grupos de I+D. Es informacion publica de
--             universidades publicas, y ademas la consulta el GPT via Action.
--   PRIVADO   todo lo que toca el trabajo con un cliente: escenarios, piezas,
--             conexiones, firmas y atributos aportados.
--
-- NO EJECUTAR hasta que el area interna sepa iniciar sesion: en cuanto corra
-- esto, /interno/memoria.html deja de funcionar sin usuario autenticado.

begin;

-- ---- sigue publico (lo usa el GPT y la busqueda de catalogo) ----
--   buscar_recursos(text,int,text)
--   consulta_amplia(text)
--   mr_total_recursos()

-- ---- pasa a exigir sesion ----
do $$
declare f text;
begin
  foreach f in array array[
    'mr_organizaciones()',
    'mr_escenarios()',
    'mr_crear_escenario(uuid, text, text, smallint, visibilidad, uuid)',
    'mr_piezas(uuid)',
    'mr_guardar_piezas(uuid, jsonb)',
    'mr_conexiones(uuid)',
    'proponer_conexiones(uuid, text, integer)',
    'proponer_conexiones(uuid, text, integer, uuid)',
    'firmar_conexion(uuid, veredicto, text, text)',
    'aportar_atributo(uuid, text, text, procedencia, text, uuid, visibilidad)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant  execute on function public.%s to authenticated', f);
  end loop;
end $$;

commit;

-- ---- comprobacion: ninguna de las privadas debe listar anon ni el = inicial ----
select p.proname as funcion, array_to_string(p.proacl,' | ') as acl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and (p.proname like 'mr\_%' or p.proname in
  ('proponer_conexiones','firmar_conexion','aportar_atributo','consulta_amplia','buscar_recursos'))
order by 1;
