-- 0010_ejecuciones.sql
--
-- Saca la ejecucion de la cadena del navegador. A partir de aqui, una ejecucion
-- y sus siete etapas viven en la base de datos: sobreviven a una recarga, al
-- cierre de la pestaña y al cambio de ordenador.
--
-- OJO CON LOS NOMBRES. El esquema ya tiene `grupo` (agrupacion de respuestas a
-- una pregunta, del diagnostico) y `escenario` (del mapeo de I+D). No son lo
-- mismo que esto. Por eso todo lo nuevo lleva prefijo rx_ (reactor).
-- `organizacion` SI se reutiliza: ya significa la organizacion cliente (UPNA,
-- Oviedo, Orfeon) y tener una sola idea de organizacion en todo el sistema es
-- justo lo que necesita el conocimiento acumulado.
--
-- Solo CREA. No toca ninguna tabla, funcion ni politica existente.

begin;

-- ---------------------------------------------------------------- estructura

create table if not exists public.rx_grupo (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizacion(id) on delete cascade,
  nombre          text not null,
  edicion         text,
  creado          timestamptz not null default now()
);
create index if not exists rx_grupo_org on public.rx_grupo(organizacion_id);

-- grupo_id nulo = facilitador de toda la organizacion
create table if not exists public.rx_miembro (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizacion(id) on delete cascade,
  grupo_id        uuid references public.rx_grupo(id) on delete cascade,
  email           text not null,
  rol             text not null default 'participante'
                  check (rol in ('facilitador','participante')),
  user_id         uuid references auth.users(id) on delete set null,
  creado          timestamptz not null default now()
);
create index if not exists rx_miembro_user  on public.rx_miembro(user_id);
create index if not exists rx_miembro_email on public.rx_miembro(lower(email));

create table if not exists public.rx_ejecucion (
  id          uuid primary key default gen_random_uuid(),
  grupo_id    uuid not null references public.rx_grupo(id) on delete cascade,
  modulo      smallint not null check (modulo between 1 and 4),
  titulo      text,
  problema    text not null,
  estado      text not null default 'en_curso'
              check (estado in ('en_curso','completa','parada')),
  creada_por  uuid references auth.users(id) on delete set null,
  creada      timestamptz not null default now(),
  actualizada timestamptz not null default now()
);
create index if not exists rx_ejecucion_grupo on public.rx_ejecucion(grupo_id, modulo);

-- La tabla que importa. `entrada` se guarda a proposito: sin ella la salida no
-- es interpretable despues, y es el material del motor de conocimiento.
create table if not exists public.rx_etapa (
  id              uuid primary key default gen_random_uuid(),
  ejecucion_id    uuid not null references public.rx_ejecucion(id) on delete cascade,
  agente          text not null check (agente in
                  ('problema','piezas','personas','escala','impacto','critico','orquestador')),
  orden           smallint not null check (orden between 1 and 7),
  estado          text not null default 'pendiente'
                  check (estado in ('pendiente','en_curso','hecha','fallida')),
  entrada         text,
  salida          text,
  matices         text,
  modelo          text,
  tokens_entrada  int,
  tokens_salida   int,
  coste_milesimas int,
  intentos        smallint not null default 0,
  error           text,
  lanzada         timestamptz,
  terminada       timestamptz,
  unique (ejecucion_id, agente)
);
create index if not exists rx_etapa_ejecucion on public.rx_etapa(ejecucion_id, orden);
create index if not exists rx_etapa_en_curso  on public.rx_etapa(lanzada) where estado = 'en_curso';

create or replace function public.rx_toca_actualizada() returns trigger
language plpgsql as $fn$
begin new.actualizada := now(); return new; end;
$fn$;

drop trigger if exists rx_ejecucion_actualizada on public.rx_ejecucion;
create trigger rx_ejecucion_actualizada before update on public.rx_ejecucion
for each row execute function public.rx_toca_actualizada();

-- ---------------------------------------------------------------- visibilidad

create or replace function public.rx_ve_org(o uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.rx_miembro m
     where m.user_id = auth.uid() and m.organizacion_id = o and m.grupo_id is null
  );
$fn$;

create or replace function public.rx_ve_grupo(g uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.rx_miembro m
     where m.user_id = auth.uid()
       and ( m.grupo_id = g
             or ( m.grupo_id is null
                  and m.organizacion_id = (select organizacion_id from public.rx_grupo where id = g) ) )
  );
$fn$;

create or replace function public.rx_ve_ejecucion(e uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select public.rx_ve_grupo((select grupo_id from public.rx_ejecucion where id = e));
$fn$;

alter table public.rx_grupo     enable row level security;
alter table public.rx_miembro   enable row level security;
alter table public.rx_ejecucion enable row level security;
alter table public.rx_etapa     enable row level security;

drop policy if exists rx_grupo_ver   on public.rx_grupo;
drop policy if exists rx_miembro_ver on public.rx_miembro;
drop policy if exists rx_ejec_todo   on public.rx_ejecucion;
drop policy if exists rx_etapa_todo  on public.rx_etapa;

create policy rx_grupo_ver on public.rx_grupo for select to authenticated
  using ( public.rx_ve_grupo(id) );

create policy rx_miembro_ver on public.rx_miembro for select to authenticated
  using ( user_id = auth.uid() or public.rx_ve_org(organizacion_id) );

create policy rx_ejec_todo on public.rx_ejecucion for all to authenticated
  using ( public.rx_ve_grupo(grupo_id) ) with check ( public.rx_ve_grupo(grupo_id) );

create policy rx_etapa_todo on public.rx_etapa for all to authenticated
  using ( public.rx_ve_ejecucion(ejecucion_id) )
  with check ( public.rx_ve_ejecucion(ejecucion_id) );

-- nada de esto es publico
revoke all on public.rx_grupo, public.rx_miembro, public.rx_ejecucion, public.rx_etapa
  from public, anon;
grant select on public.rx_grupo, public.rx_miembro to authenticated;
grant select, insert, update, delete on public.rx_ejecucion, public.rx_etapa to authenticated;
revoke execute on function public.rx_ve_org(uuid), public.rx_ve_grupo(uuid), public.rx_ve_ejecucion(uuid)
  from public, anon;
grant  execute on function public.rx_ve_org(uuid), public.rx_ve_grupo(uuid), public.rx_ve_ejecucion(uuid)
  to authenticated;

-- ---------------------------------------------------------------- semilla
-- Un grupo y Joaquin como facilitador, colgando de una organizacion que ya
-- exista; si no hay ninguna suya, se crea una.

insert into public.organizacion (propietario, nombre)
select u.id, 'Joaquin Romero Roldan'
from auth.users u
where not exists (select 1 from public.organizacion o where o.propietario = u.id);

insert into public.rx_grupo (organizacion_id, nombre, edicion)
select o.id, 'Facilitador', 'interno'
from public.organizacion o
where o.propietario = (select id from auth.users order by created_at limit 1)
  and not exists (select 1 from public.rx_grupo g where g.organizacion_id = o.id and g.nombre = 'Facilitador')
limit 1;

insert into public.rx_miembro (organizacion_id, grupo_id, email, rol, user_id)
select g.organizacion_id, null, u.email, 'facilitador', u.id
from public.rx_grupo g, auth.users u
where g.nombre = 'Facilitador'
  and not exists (select 1 from public.rx_miembro m where m.user_id = u.id and m.organizacion_id = g.organizacion_id);

commit;
