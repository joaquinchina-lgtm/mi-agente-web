-- ============================================================================
--  Memoria del Reactor · migración 0003 · dos correcciones encontradas al
--  probar la pantalla contra la base real con la clave publicable.
-- ============================================================================

-- 1. La política RLS de lectura sobre `recurso` NO basta: PostgREST devuelve
--    401 "permission denied for table recurso" porque falta el GRANT. En vez de
--    conceder SELECT sobre la tabla a anon, se expone sólo el recuento por RPC.
--    Así ninguna tabla queda accesible directamente y la pantalla no depende de
--    privilegios de tabla.
create or replace function mr_total_recursos()
returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from recurso;
$$;
grant execute on function mr_total_recursos() to anon, authenticated;

-- 2. proponer_conexiones multiplicaba el límite por tres para sobrepescar antes
--    de filtrar por cobertura, pero insertaba TODO lo sobrepescado: pedir 10
--    metía 30 propuestas. Treinta fichas sin firmar delante de un equipo es
--    ruido, no ayuda. Ahora sobrepesca igual pero corta en p_limite.
create or replace function proponer_conexiones(
  p_escenario_id uuid,
  p_consulta text,
  p_limite int default 10
)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  insert into conexion (recurso_id, escenario_id, veredicto, propuesta_por, score)
  select b.id, p_escenario_id, 'por_verificar', 'modelo', b.score
  from (
    select id, score from buscar_recursos(p_consulta, p_limite * 3)
    where terminos >= 2
    order by score desc
    limit greatest(1, least(p_limite, 30))
  ) b
  on conflict (recurso_id, escenario_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
grant execute on function proponer_conexiones(uuid, text, int) to anon, authenticated;

-- 3. Limpieza de la prueba técnica (borra en cascada escenario y conexiones).
delete from problema where declaracion = 'PRUEBA TECNICA - borrar';
