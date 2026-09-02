-- ============================================================================
--  Memoria del Reactor · migración 0001
--  Se apoya en el esquema que ya usa la consola (organizacion, sector, sesion,
--  grupo). NO crea servidor ni proyecto nuevo: mismas convenciones —tablas en
--  singular, snake_case, escrituras por RPC SECURITY DEFINER, RLS deniega todo.
--
--  Decisión deliberada: NO se instala pgvector en esta migración. Con 7.795
--  recursos y líneas de 493 caracteres de media, la búsqueda de texto completo
--  en español de Postgres es suficiente y no añade dependencias ni coste. Si
--  falla en una sesión real, se añade pgvector entonces y no antes.
-- ============================================================================

-- En Supabase las extensiones viven en el esquema extensions, no en public.
-- Sin esto, with unaccent en la configuración de búsqueda y gin_trgm_ops en
-- el índice no se resuelven y la migración aborta a mitad.
-- Claves uuid, no bigserial: es la convención de la consola. Comprobado el
-- 02/09/2026 contra el proyecto real: organizacion.id, sesion.id y grupo.id
-- son uuid, y una FK bigint contra ellas aborta la migración entera.
create schema if not exists extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm with schema extensions;
set search_path = public, extensions;

-- Configuración de búsqueda: español + sin acentos, para que "biomedicina"
-- encuentre "Biomedicina" y "análisis" encuentre "analisis".
do $$
begin
  if not exists (select 1 from pg_ts_config where cfgname = 'es_sin_acentos') then
    create text search configuration es_sin_acentos (copy = spanish);
    alter text search configuration es_sin_acentos
      alter mapping for hword, hword_part, word with unaccent, spanish_stem;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------

-- De dónde sale un dato. Va en el registro, no en una nota al pie.
create type procedencia as enum ('documento', 'sesion', 'modelo');

-- La línea de confidencialidad. 'cliente' no se acumula entre organizaciones
-- ni alimenta a otros instrumentos; 'metodo' es material reutilizable propio.
create type visibilidad as enum ('cliente', 'metodo');

-- Taxonomía literal del agente Piezas.
create type categoria_pieza as enum ('datos', 'tecnologica', 'conocimiento', 'auxiliar');
create type escala as enum ('mesa', 'comunidad', 'piloto', 'proceso');

-- Veredicto de una conexión entre una capacidad y un escenario.
create type veredicto as enum ('sirve', 'no_sirve', 'por_verificar');

-- ---------------------------------------------------------------------------
-- 1. Catálogo de capacidades externas (recursos_unificados.csv)
--    Inmutable: es lo que dice la fuente. Nada que aporte una persona se
--    escribe aquí — va a recurso_atributo.
-- ---------------------------------------------------------------------------
create table recurso (
  id                  uuid primary key default gen_random_uuid(),
  universidad         text not null,
  universidad_nombre  text,
  ccaa                text,
  tipo_fuente         text,
  codigo              text,
  nombre              text not null,
  acronimo            text,
  responsable         text,
  unidad              text,
  area                text,
  lineas              text,
  n_lineas            int,
  calidad_lineas      text,
  palabras_clave      text,
  descripcion         text,
  servicios           text,
  equipamiento        text,
  oferta_tecnologica  text,
  url                 text,
  web                 text,
  tipo_registro       text,
  extras              jsonb,
  fichero_origen      text,
  importado_en        timestamptz not null default now(),
  busqueda            tsvector generated always as (
      setweight(to_tsvector('es_sin_acentos', coalesce(nombre, '')),             'A') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(palabras_clave, '')),     'A') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(oferta_tecnologica, '')), 'A') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(lineas, '')),             'B') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(servicios, '')),          'B') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(equipamiento, '')),       'B') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(descripcion, '')),        'C') ||
      setweight(to_tsvector('es_sin_acentos', coalesce(area, '')),               'D')
  ) stored,
  unique (universidad, codigo, nombre)
);

create index recurso_busqueda_idx on recurso using gin (busqueda);
create index recurso_nombre_trgm_idx on recurso using gin (nombre extensions.gin_trgm_ops);
create index recurso_universidad_idx on recurso (universidad);

comment on table recurso is
  'Catálogo importado de capacidades de I+D. Solo lo que publica la fuente. '
  'Nunca se edita a mano: lo que aporta una persona va a recurso_atributo.';

-- ---------------------------------------------------------------------------
-- 2. Lo que el catálogo NO trae y la transferencia real exige
--    (madurez/TRL, titularidad, disponibilidad, contacto validado).
--    Lo aportan personas en sesión. Por eso lleva firma obligatoria.
-- ---------------------------------------------------------------------------
create table recurso_atributo (
  id           uuid primary key default gen_random_uuid(),
  recurso_id   uuid not null references recurso(id) on delete cascade,
  clave        text not null
               check (clave in ('madurez','titularidad','disponibilidad',
                                'contacto','coste','restriccion','nota')),
  valor        text not null,
  procedencia  procedencia not null,
  visibilidad  visibilidad not null default 'metodo',
  sesion_id    uuid references sesion(id) on delete set null,
  firmado_por  text not null,
  firmado_en   timestamptz not null default now()
);

create index recurso_atributo_recurso_idx on recurso_atributo (recurso_id, clave);

comment on table recurso_atributo is
  'El dato que falta en el catálogo y que solo sabe una persona. '
  'firmado_por es NOT NULL a propósito: un atributo sin responsable no vale.';

-- ---------------------------------------------------------------------------
-- 3. El trabajo del Reactor. Cuelga de organizacion y sesion, que ya existen.
-- ---------------------------------------------------------------------------
create table problema (
  id               uuid primary key default gen_random_uuid(),
  organizacion_id  uuid not null references organizacion(id) on delete cascade,
  sesion_id        uuid references sesion(id) on delete set null,
  grupo_id         uuid references grupo(id) on delete set null,
  visibilidad      visibilidad not null default 'cliente',
  -- Esquema literal del agente Problema
  declaracion      text not null,
  capacidad_nueva  text,
  verificador      text,
  variantes        jsonb not null default '[]'::jsonb,
  -- Estructura Reconocible / Resoluble / Verificable
  es_reconocible   boolean,
  es_resoluble     boolean,
  es_verificable   boolean,
  procedencia      procedencia not null default 'sesion',
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);

create index problema_organizacion_idx on problema (organizacion_id);

comment on column problema.visibilidad is
  'Por defecto ''cliente''. En industria el problema es lo más sensible de la '
  'sala: se sube a ''metodo'' solo por decisión explícita.';

-- El escenario es la entidad central del método, no la idea ni el proyecto.
create table escenario (
  id              uuid primary key default gen_random_uuid(),
  problema_id     uuid not null references problema(id) on delete cascade,
  modulo          smallint not null check (modulo between 1 and 4),
  orden           smallint not null check (orden between 1 and 3),
  titulo          text not null,
  descripcion     text,
  estructura      text,   -- M2: estructura de la organización
  aplicaciones    text,   -- M2: posibles aplicaciones
  prototipado     text,   -- M3: cómo se prototipa el problema
  hoja_de_ruta    text,   -- M3: árbol de decisión
  modelo_negocio  jsonb,  -- M4: los 9 bloques del canvas
  riesgos         jsonb not null default '[]'::jsonb,
  incertidumbres  jsonb not null default '[]'::jsonb,
  seleccionado    boolean not null default false,
  creado_en       timestamptz not null default now(),
  unique (problema_id, modulo, orden)
);

create index escenario_problema_idx on escenario (problema_id, modulo);

-- Piezas: esquema literal del agente Piezas.
create table pieza (
  id               uuid primary key default gen_random_uuid(),
  escenario_id     uuid not null references escenario(id) on delete cascade,
  nombre           text not null,
  categoria        categoria_pieza not null,
  escala_inicial   escala not null,
  que_revela       text,
  siguiente_escala text,
  -- Si la pieza está respaldada por una capacidad del catálogo, aquí se ata.
  -- Nulo es normal: muchas piezas son datos abiertos o software.
  recurso_id       uuid references recurso(id) on delete set null,
  procedencia      procedencia not null default 'modelo',
  creado_en        timestamptz not null default now()
);

create index pieza_escenario_idx on pieza (escenario_id);
create index pieza_recurso_idx on pieza (recurso_id) where recurso_id is not null;

comment on table pieza is
  'M2 puntúa el grado de reutilización y repropósito de las piezas. Esta tabla, '
  'consultada entre ediciones, es el único sitio donde eso se puede medir.';

-- ---------------------------------------------------------------------------
-- 4. LA ARISTA FIRMADA. El corazón del sistema.
--    Una fila sin firmado_por es una PROPUESTA de la máquina.
--    Una fila con firmado_por es una AFIRMACIÓN de una persona.
--    El índice parcial impide dos firmas contradictorias sobre el mismo par.
-- ---------------------------------------------------------------------------
create table conexion (
  id            uuid primary key default gen_random_uuid(),
  recurso_id    uuid not null references recurso(id) on delete cascade,
  escenario_id  uuid not null references escenario(id) on delete cascade,
  veredicto     veredicto not null default 'por_verificar',
  razon         text,
  propuesta_por procedencia not null default 'modelo',
  score         real,          -- ranking de la búsqueda que la propuso
  firmado_por   text,          -- NULL = todavía es solo una propuesta
  firmado_en    timestamptz,
  creado_en     timestamptz not null default now(),
  constraint firma_completa check (
    (firmado_por is null and firmado_en is null) or
    (firmado_por is not null and firmado_en is not null)
  ),
  constraint veredicto_exige_firma check (
    veredicto = 'por_verificar' or firmado_por is not null
  )
);

create unique index conexion_par_idx on conexion (recurso_id, escenario_id);
create index conexion_pendientes_idx on conexion (escenario_id) where firmado_por is null;

comment on constraint veredicto_exige_firma on conexion is
  'Un modelo no puede afirmar que una capacidad sirve para un problema. '
  'Solo puede proponerlo. El veredicto lo pone una persona con nombre.';

-- ---------------------------------------------------------------------------
-- 5. Vistas de lectura, en la convención v_* de la consola
-- ---------------------------------------------------------------------------
create view v_conexiones_firmadas as
select c.id, c.veredicto, c.razon, c.firmado_por, c.firmado_en,
       r.id as recurso_id, r.nombre as recurso, r.universidad, r.responsable, r.url,
       e.id as escenario_id, e.titulo as escenario, e.modulo,
       p.id as problema_id, p.declaracion, p.visibilidad, p.organizacion_id, p.sesion_id
from conexion c
join recurso  r on r.id = c.recurso_id
join escenario e on e.id = c.escenario_id
join problema  p on p.id = e.problema_id
where c.firmado_por is not null;

-- Solo material reutilizable. Es la vista que puede alimentar a otros
-- instrumentos y acumularse entre clientes. La de arriba, no.
create view v_metodo_reutilizable as
select * from v_conexiones_firmadas where visibilidad = 'metodo';

create view v_cobertura_recurso as
select r.id, r.nombre, r.universidad,
       (r.lineas is not null and r.lineas <> '')             as tiene_lineas,
       (r.oferta_tecnologica is not null
        and r.oferta_tecnologica <> '')                      as tiene_oferta,
       exists (select 1 from recurso_atributo a
               where a.recurso_id = r.id and a.clave = 'madurez')      as tiene_madurez,
       exists (select 1 from recurso_atributo a
               where a.recurso_id = r.id and a.clave = 'titularidad')  as tiene_titularidad,
       (select count(*) from conexion c
        where c.recurso_id = r.id and c.firmado_por is not null)       as veces_firmado
from recurso r;

-- ---------------------------------------------------------------------------
-- 6. RLS: deniega todo. El acceso va por RPC, como en el resto de la consola.
-- ---------------------------------------------------------------------------
alter table recurso           enable row level security;
alter table recurso_atributo  enable row level security;
alter table problema          enable row level security;
alter table escenario         enable row level security;
alter table pieza             enable row level security;
alter table conexion          enable row level security;

-- Única excepción: el catálogo es consultable en lectura. No contiene nada
-- del cliente: son capacidades que las universidades ya publican.
create policy recurso_lectura on recurso for select to anon, authenticated using (true);

-- ---------------------------------------------------------------------------
-- 7. RPC
-- ---------------------------------------------------------------------------

-- Convierte una frase en una consulta OR ponderada.
--
-- POR QUÉ NO websearch_to_tsquery NI plainto_tsquery: ambas unen los términos
-- con AND. Probado contra el corpus real de 7.795 grupos con el problema del
-- Reactor UPNA ("ola de calor salud pública epidemiología clima"): devuelven
-- CERO filas, porque ningún grupo declara los cinco términos a la vez. Un
-- buscador que exige coincidencia total no sirve para descubrir capacidades:
-- lo que se busca es precisamente al que tiene una parte del problema.
-- to_tsvector ya aplica unaccent, stemming en español y quita vacías.
create or replace function consulta_amplia(consulta text)
returns tsquery
language sql immutable strict as $$
  select nullif(string_agg(lexema, ' | '), '')::tsquery
  from (
    select distinct unnest(tsvector_to_array(
             to_tsvector('es_sin_acentos', consulta))) as lexema
  ) t;
$$;

-- Buscar capacidades. Devuelve candidatos, NO conexiones.
--
-- El ranking usa ts_rank con los pesos por defecto (A=1.0, B=0.4, C=0.2,
-- D=0.1), que en el índice de recurso significan: nombre, palabras clave y
-- oferta tecnológica pesan más que las líneas, y éstas más que la descripción.
-- Devuelve además cuántos términos distintos ha cubierto cada grupo, que es
-- el dato que una persona necesita para decidir si merece abrirlo.
create or replace function buscar_recursos(
  consulta text,
  limite int default 20,
  filtro_universidad text default null
)
returns table (
  id uuid, nombre text, universidad text, responsable text,
  area text, lineas text, url text, score real, terminos int
)
language sql stable security definer set search_path = public, extensions as $$
  with q as (select consulta_amplia(consulta) as tsq,
                    tsvector_to_array(to_tsvector('es_sin_acentos', consulta)) as lex)
  select * from (
    select r.id, r.nombre, r.universidad, r.responsable, r.area,
           left(r.lineas, 400) as lineas, r.url,
           -- Mezcla deliberada: relevancia ts_rank amplificada por cobertura.
           -- Solo ts_rank deja tercero al grupo que cubre 6 de 7 términos;
           -- solo cobertura sube filas basura con puntuación 0,08. Verificado
           -- contra el corpus real con el problema del Reactor UPNA.
           (ts_rank(r.busqueda, q.tsq) * (1 + 0.25 * t.n))::real as score,
           t.n as terminos
    from recurso r, q,
         lateral (select count(*)::int as n from unnest(q.lex) l
                  where r.busqueda @@ l::tsquery) t
    where q.tsq is not null
      and r.busqueda @@ q.tsq
      and (filtro_universidad is null or r.universidad = filtro_universidad)
  ) s
  order by s.score desc, s.terminos desc, s.nombre
  limit greatest(1, least(limite, 100));
$$;

-- Proponer conexiones. Lo hace la máquina. Nunca firma.
create or replace function proponer_conexiones(
  p_escenario_id uuid,
  p_consulta text,
  p_limite int default 10
)
returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  -- Solo se proponen los que cubren al menos dos términos distintos de la
  -- consulta. Con OR puro, un grupo que solo comparte una palabra genérica
  -- ("sistema", "análisis") entra en la lista y la ensucia.
  insert into conexion (recurso_id, escenario_id, veredicto, propuesta_por, score)
  select b.id, p_escenario_id, 'por_verificar', 'modelo', b.score
  from buscar_recursos(p_consulta, p_limite * 3) b
  where b.terminos >= 2
  on conflict (recurso_id, escenario_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

-- Firmar. Lo hace una persona, con nombre y razón.
create or replace function firmar_conexion(
  p_conexion_id uuid,
  p_veredicto veredicto,
  p_razon text,
  p_firmante text
)
returns conexion
language plpgsql security definer set search_path = public, extensions as $$
declare fila conexion;
begin
  if p_firmante is null or btrim(p_firmante) = '' then
    raise exception 'Una conexión no se firma sin nombre';
  end if;
  if p_veredicto <> 'por_verificar' and (p_razon is null or btrim(p_razon) = '') then
    raise exception 'Un veredicto sin razón no es una firma, es un clic';
  end if;
  update conexion
     set veredicto = p_veredicto, razon = p_razon,
         firmado_por = btrim(p_firmante), firmado_en = now()
   where id = p_conexion_id
  returning * into fila;
  if not found then raise exception 'Conexión % no existe', p_conexion_id; end if;
  return fila;
end $$;

-- Aportar el dato que el catálogo no trae.
create or replace function aportar_atributo(
  p_recurso_id uuid, p_clave text, p_valor text,
  p_procedencia procedencia, p_firmante text,
  p_sesion_id uuid default null,
  p_visibilidad visibilidad default 'metodo'
)
returns recurso_atributo
language plpgsql security definer set search_path = public, extensions as $$
declare fila recurso_atributo;
begin
  if p_firmante is null or btrim(p_firmante) = '' then
    raise exception 'Un atributo sin responsable no vale';
  end if;
  insert into recurso_atributo
    (recurso_id, clave, valor, procedencia, visibilidad, sesion_id, firmado_por)
  values
    (p_recurso_id, p_clave, p_valor, p_procedencia, p_visibilidad, p_sesion_id, btrim(p_firmante))
  returning * into fila;
  return fila;
end $$;

revoke all on function proponer_conexiones(uuid, text, int) from public;
revoke all on function firmar_conexion(uuid, veredicto, text, text) from public;
revoke all on function aportar_atributo(uuid, text, text, procedencia, text, uuid, visibilidad) from public;
grant execute on function buscar_recursos(text, int, text) to anon, authenticated;
grant execute on function consulta_amplia(text) to anon, authenticated;
