-- 0010_ejecuciones.sql
--
-- Saca la ejecucion de la cadena del navegador. A partir de aqui, una ejecucion
-- y sus siete etapas viven en la base de datos: sobreviven a una recarga, al
-- cierre de la pestaña y al cambio de ordenador.
--
-- Solo CREA. No toca ninguna tabla ni funcion existente.

begin;

-- ---------------------------------------------------------------- estructura

create table if not exists public.organizacion (
  id     uuid primary key default gen_random_uuid(),
  nombre text not null,
  slug   text not null unique,
  creada timestamptz not null default now()
);

create table if not exists public.grupo (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizacion(id) on delete cascade,
  nombre          text not null,
  edicion         text,
  creado          timestamptz not null default now()
);
create index if not exists grupo_org on public.grupo(organizacion_id);

-- grupo_id nulo = facilitador de toda la organizacion
create table if not exists public.miembro (
  id              uuid primary key default gen_random_uuid(),
  organizacion_id uuid not null references public.organizacion(id) on delete cascade,
  grupo_id        uuid references public.grupo(id) on delete cascade,
  email           text not null,
  rol             text not null default 'participante'
                  check (rol in ('facilitador','participante')),
  user_id         uuid references auth.users(id) on delete set null,
  creado          timestamptz not null default now()
);
create index if not exists miembro_user  on public.miembro(user_id);
create index if not exists miembro_email on public.miembro(lower(email));

create table if not exists public.ejecucion (
  id          uuid primary key default gen_random_uuid(),
  grupo_id    uuid not null references public.grupo(id) on delete cascade,
  modulo      smallint not null check (modulo between 1 and 4),
  titulo      text,
  problema    text not null,
  estado      text not null default 'en_curso'
              check (estado in ('en_curso','completa','parada')),
  creada_por  uuid references auth.users(id) on delete set null,
  creada      timestamptz not null default now(),
  actualizada timestamptz not null default now()
);
create index if not exists ejecucion_grupo on public.ejecucion(grupo_id, modulo);

-- La tabla que importa. `entrada` se guarda a proposito: sin ella, la salida
-- no es interpretable despues, y es el material del motor de conocimiento.
create table if not exists public.etapa (
  id              uuid primary key default gen_random_uuid(),
  ejecucion_id    uuid not null references public.ejecucion(id) on delete cascade,
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
create index if not exists etapa_ejecucion on public.etapa(ejecucion_id, orden);
create index if not exists etapa_en_curso  on public.etapa(lanzada) where estado = 'en_curso';

create or replace function public.mr_toca_actualizada() returns trigger
language plpgsql as $fn$
begin new.actualizada := now(); return new; end;
$fn$;

drop trigger if exists ejecucion_actualizada on public.ejecucion;
create trigger ejecucion_actualizada before update on public.ejecucion
for each row execute function public.mr_toca_actualizada();

-- ---------------------------------------------------------------- visibilidad

create or replace function public.mr_ve_org(o uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.miembro m
     where m.user_id = auth.uid() and m.organizacion_id = o and m.grupo_id is null
  );
$fn$;

create or replace function public.mr_ve_grupo(g uuid) returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.miembro m
     where m.user_id = auth.uid()
       and ( m.grupo_id = g
             or ( m.grupo_id is null
                  and m.organizacion_id = (select organizacion_id from public.grupo where id = g) ) )
  );
$fn$;

alter table public.organizacion enable row level security;
alter table public.grupo        enable row level security;
alter table public.miembro      enable row level security;
alter table public.ejecucion    enable row level security;
alter table public.etapa        enable row level security;

drop policy if exists org_ver     on public.organizacion;
drop policy if exists grupo_ver   on public.grupo;
drop policy if exists miembro_ver on public.miembro;
drop policy if exists ejec_todo   on public.ejecucion;
drop policy if exists etapa_todo  on public.etapa;

create policy org_ver on public.organizacion for select to authenticated
  using ( public.mr_ve_org(id) );

create policy grupo_ver on public.grupo for select to authenticated
  using ( public.mr_ve_grupo(id) );

create policy miembro_ver on public.miembro for select to authenticated
  using ( user_id = auth.uid() or public.mr_ve_org(organizacion_id) );

create policy ejec_todo on public.ejecucion for all to authenticated
  using ( public.mr_ve_grupo(grupo_id) ) with check ( public.mr_ve_grupo(grupo_id) );

create policy etapa_todo on public.etapa for all to authenticated
  using ( public.mr_ve_grupo((select grupo_id from public.ejecucion e where e.id = ejecucion_id)) )
  with check ( public.mr_ve_grupo((select grupo_id from public.ejecucion e where e.id = ejecucion_id)) );

-- nada de esto es publico
revoke all on public.organizacion, public.grupo, public.miembro,
              public.ejecucion, public.etapa from public, anon;
grant select on public.organizacion, public.grupo, public.miembro to authenticated;
grant select, insert, update, delete on public.ejecucion, public.etapa to authenticated;
revoke execute on function public.mr_ve_org(uuid), public.mr_ve_grupo(uuid) from public, anon;
grant  execute on function public.mr_ve_org(uuid), public.mr_ve_grupo(uuid) to authenticated;

-- ---------------------------------------------------------------- semilla
-- Una organizacion, un grupo y Joaquin como facilitador, para poder trabajar
-- hoy mismo siendo el unico usuario.

insert into public.organizacion (nombre, slug)
select 'Joaquin Romero Roldan', 'jrr'
where not exists (select 1 from public.organizacion where slug = 'jrr');

insert into public.grupo (organizacion_id, nombre, edicion)
select o.id, 'Facilitador', 'interno'
from public.organizacion o
where o.slug = 'jrr'
  and not exists (select 1 from public.grupo g where g.organizacion_id = o.id and g.nombre = 'Facilitador');

insert into public.miembro (organizacion_id, grupo_id, email, rol, user_id)
select o.id, null, u.email, 'facilitador', u.id
from public.organizacion o, auth.users u
where o.slug = 'jrr'
  and not exists (select 1 from public.miembro m where m.user_id = u.id and m.organizacion_id = o.id);

commit;
