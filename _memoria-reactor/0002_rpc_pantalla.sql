-- ============================================================================
--  Memoria del Reactor · migración 0002
--  Lo que la pantalla de interno/memoria.html necesita para funcionar.
--
--  RLS deniega todo en las tablas nuevas, así que la lectura también va por
--  RPC SECURITY DEFINER. Prefijo mr_ para no chocar con los RPC de la consola.
--
--  AVISO DE SEGURIDAD, deliberado y anotado: estos RPC se conceden a `anon`,
--  igual que los de la consola (guardar_item, guardar_votos...). La clave
--  publicable está en el repositorio PÚBLICO mi-agente-web, así que cualquiera
--  que la lea puede firmar conexiones. Para uso interno de Joaquín es asumible;
--  antes de que esto entre en una sala con participantes hay que poner
--  autenticación en /interno/ — que arregla además el resto de la consola.
-- ============================================================================

create or replace function mr_organizaciones()
returns table (id uuid, nombre text)
language sql stable security definer set search_path = public as $$
  select o.id, o.nombre from organizacion o order by o.nombre;
$$;

create or replace function mr_escenarios()
returns table (
  escenario_id uuid, titulo text, modulo smallint,
  problema_id uuid, declaracion text, visibilidad visibilidad,
  organizacion text, propuestas int, firmadas int
)
language sql stable security definer set search_path = public as $$
  select e.id, e.titulo, e.modulo, p.id, p.declaracion, p.visibilidad, o.nombre,
         (select count(*)::int from conexion c where c.escenario_id = e.id and c.firmado_por is null),
         (select count(*)::int from conexion c where c.escenario_id = e.id and c.firmado_por is not null)
  from escenario e
  join problema p on p.id = e.problema_id
  join organizacion o on o.id = p.organizacion_id
  order by e.creado_en desc;
$$;

-- Crea problema y escenario de una vez: en una pantalla mínima, pedir los dos
-- por separado sobra. El problema se puede reutilizar añadiendo escenarios.
create or replace function mr_crear_escenario(
  p_organizacion_id uuid,
  p_declaracion text,
  p_titulo text,
  p_modulo smallint default 2,
  p_visibilidad visibilidad default 'cliente',
  p_problema_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_problema uuid; v_orden smallint; v_escenario uuid;
begin
  if p_titulo is null or btrim(p_titulo) = '' then
    raise exception 'El escenario necesita un título';
  end if;
  if p_problema_id is not null then
    v_problema := p_problema_id;
  else
    if p_declaracion is null or btrim(p_declaracion) = '' then
      raise exception 'El problema necesita una declaración';
    end if;
    insert into problema (organizacion_id, declaracion, visibilidad, procedencia)
    values (p_organizacion_id, btrim(p_declaracion), p_visibilidad, 'sesion')
    returning id into v_problema;
  end if;
  select coalesce(max(orden), 0) + 1 into v_orden
  from escenario where problema_id = v_problema and modulo = p_modulo;
  if v_orden > 3 then
    raise exception 'El método admite tres escenarios por módulo, no más';
  end if;
  insert into escenario (problema_id, modulo, orden, titulo)
  values (v_problema, p_modulo, v_orden, btrim(p_titulo))
  returning id into v_escenario;
  return v_escenario;
end $$;

create or replace function mr_conexiones(p_escenario_id uuid)
returns table (
  id uuid, recurso_id uuid, recurso text, universidad text, responsable text,
  area text, lineas text, url text, score real,
  veredicto veredicto, razon text, firmado_por text, firmado_en timestamptz
)
language sql stable security definer set search_path = public as $$
  select c.id, r.id, r.nombre, r.universidad, r.responsable, r.area,
         left(r.lineas, 400), r.url, c.score,
         c.veredicto, c.razon, c.firmado_por, c.firmado_en
  from conexion c
  join recurso r on r.id = c.recurso_id
  where c.escenario_id = p_escenario_id
  order by (c.firmado_por is not null), c.score desc nulls last, r.nombre;
$$;

grant execute on function mr_organizaciones() to anon, authenticated;
grant execute on function mr_escenarios() to anon, authenticated;
grant execute on function mr_crear_escenario(uuid, text, text, smallint, visibilidad, uuid) to anon, authenticated;
grant execute on function mr_conexiones(uuid) to anon, authenticated;
grant execute on function proponer_conexiones(uuid, text, int) to anon, authenticated;
grant execute on function firmar_conexion(uuid, veredicto, text, text) to anon, authenticated;
grant execute on function aportar_atributo(uuid, text, text, procedencia, text, uuid, visibilidad) to anon, authenticated;
