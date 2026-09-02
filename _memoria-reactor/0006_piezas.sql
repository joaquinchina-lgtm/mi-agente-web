-- ============================================================================
--  Memoria del Reactor · migración 0006 · las piezas entran en el sistema
--
--  El agente Piezas de reactor.html ya devuelve exactamente
--    Pieza | Categoría | Escala inicial | Qué revela | Siguiente escala
--  que es la tabla `pieza` de la 0001. Esta migración añade lo que falta para
--  cerrar el circuito: los términos con que buscar cada pieza en el catálogo, y
--  la traza de qué pieza originó cada conexión propuesta.
--
--  Por qué importa `pieza_id` en `conexion`: el canvas M2 puntúa el "grado de
--  reutilización y repropósito de las piezas". Sin saber qué pieza llevó a qué
--  grupo, eso no se puede medir entre ediciones.
-- ============================================================================

alter table pieza    add column if not exists terminos text;
alter table conexion add column if not exists pieza_id uuid references pieza(id) on delete set null;
create index if not exists conexion_pieza_idx on conexion (pieza_id) where pieza_id is not null;

comment on column pieza.terminos is
  'La pieza traducida al idioma del catálogo. La pieza está escrita como lo que '
  'el equipo necesita; el catálogo, como lo que un grupo sabe hacer.';

-- Guarda de una vez las piezas de una etapa. Idempotente por (escenario, nombre):
-- reejecutar el agente y volver a guardar actualiza, no duplica.
create or replace function mr_guardar_piezas(p_escenario_id uuid, p_piezas jsonb)
returns setof pieza
language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  if p_escenario_id is null then raise exception 'Falta el escenario'; end if;
  for j in select * from jsonb_array_elements(p_piezas) loop
    if coalesce(btrim(j->>'nombre'),'') = '' then continue; end if;
    update pieza set
      categoria = coalesce((j->>'categoria')::categoria_pieza, categoria),
      escala_inicial = coalesce((j->>'escala')::escala, escala_inicial),
      que_revela = coalesce(j->>'que_revela', que_revela),
      siguiente_escala = coalesce(j->>'siguiente_escala', siguiente_escala),
      terminos = coalesce(j->>'terminos', terminos)
    where escenario_id = p_escenario_id and lower(btrim(nombre)) = lower(btrim(j->>'nombre'));
    if not found then
      insert into pieza (escenario_id, nombre, categoria, escala_inicial,
                         que_revela, siguiente_escala, terminos, procedencia)
      values (p_escenario_id, btrim(j->>'nombre'),
              coalesce((j->>'categoria')::categoria_pieza, 'auxiliar'),
              coalesce((j->>'escala')::escala, 'mesa'),
              j->>'que_revela', j->>'siguiente_escala', j->>'terminos', 'modelo');
    end if;
  end loop;
  return query select * from pieza where escenario_id = p_escenario_id order by categoria, nombre;
end $$;

create or replace function mr_piezas(p_escenario_id uuid)
returns table (id uuid, nombre text, categoria categoria_pieza, escala_inicial escala,
               que_revela text, siguiente_escala text, terminos text,
               recurso_id uuid, propuestas int, firmadas int)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, p.categoria, p.escala_inicial, p.que_revela,
         p.siguiente_escala, p.terminos, p.recurso_id,
         (select count(*)::int from conexion c where c.pieza_id = p.id and c.firmado_por is null),
         (select count(*)::int from conexion c where c.pieza_id = p.id and c.firmado_por is not null)
  from pieza p where p.escenario_id = p_escenario_id
  order by p.categoria, p.nombre;
$$;

-- Igual que antes, pero dejando constancia de qué pieza originó la propuesta.
create or replace function proponer_conexiones(
  p_escenario_id uuid, p_consulta text, p_limite int default 10,
  p_pieza_id uuid default null)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  insert into conexion (recurso_id, escenario_id, pieza_id, veredicto, propuesta_por, score)
  select b.id, p_escenario_id, p_pieza_id, 'por_verificar', 'modelo', b.score
  from (
    select id, score from buscar_recursos(p_consulta, p_limite * 3)
    where terminos >= 2 order by score desc
    limit greatest(1, least(p_limite, 30))
  ) b
  on conflict (recurso_id, escenario_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on function mr_guardar_piezas(uuid, jsonb) to anon, authenticated;
grant execute on function mr_piezas(uuid) to anon, authenticated;
grant execute on function proponer_conexiones(uuid, text, int, uuid) to anon, authenticated;
