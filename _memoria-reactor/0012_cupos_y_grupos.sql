-- 0012_cupos_y_grupos.sql
--
-- Modelo B: una cuenta por grupo, con cupo de ejecuciones y techo de gasto.
--
-- Decisiones de Joaquin (4/09/2026):
--   * Una cuenta por GRUPO, no por persona. La evaluacion individual va por el
--     canal del programa, no por aqui.
--   * Cupo: 2 cadenas por modulo y grupo (8 en todo el programa, 4 modulos).
--   * Techo de gasto: 10 EUR/mes por grupo. El de organizacion no es un
--     presupuesto, es un detector de averias: 50 EUR/mes.
--   * Los grupos NO son fijos: hay reactores de un grupo y podria haber mas de
--     cinco. Nada de numeros cableados: todo son campos por grupo.
--
-- Solo CREA y añade columnas. No toca nada existente.

begin;

alter table public.rx_grupo
  add column if not exists cupo_por_modulo   smallint not null default 2,
  add column if not exists tope_milesimas_mes integer  not null default 10000,
  add column if not exists activo            boolean  not null default true;

alter table public.rx_miembro
  add column if not exists aviso_datos_aceptado timestamptz;

-- Techo por organizacion. Red de seguridad ante un fallo en bucle, no un
-- presupuesto: el cupo por grupo ya acota el gasto de forma determinista.
create table if not exists public.rx_tope (
  organizacion_id    uuid primary key references public.organizacion(id) on delete cascade,
  milesimas_mes      integer not null default 50000,
  actualizado        timestamptz not null default now()
);

-- ------------------------------------------------------------ enlace de cuenta
-- La cuenta del grupo se da de alta ANTES, con su correo. Cuando entra por
-- primera vez, esto engancha su user_id con la fila que ya existia. Sin esto
-- habria que editar a mano cada grupo despues de que entrase.
create or replace function public.rx_enlazar_miembro() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  update public.rx_miembro
     set user_id = new.id
   where user_id is null
     and lower(email) = lower(new.email);
  return new;
end;
$fn$;

drop trigger if exists rx_enlazar_miembro on auth.users;
create trigger rx_enlazar_miembro after insert on auth.users
for each row execute function public.rx_enlazar_miembro();

-- Para las cuentas que ya existan antes de esta migracion.
update public.rx_miembro m
   set user_id = u.id
  from auth.users u
 where m.user_id is null and lower(m.email) = lower(u.email);

-- --------------------------------------------------------------- cupo y gasto

create or replace function public.rx_cadenas_en_modulo(g uuid, m smallint)
returns integer
language sql stable security definer set search_path = public as $fn$
  select count(*)::int from public.rx_ejecucion e
   where e.grupo_id = g and e.modulo = m;
$fn$;

create or replace function public.rx_gasto_mes_grupo(g uuid)
returns integer
language sql stable security definer set search_path = public as $fn$
  select coalesce(sum(t.coste_milesimas), 0)::int
    from public.rx_etapa t
    join public.rx_ejecucion e on e.id = t.ejecucion_id
   where e.grupo_id = g
     and t.terminada >= date_trunc('month', now());
$fn$;

create or replace function public.rx_gasto_mes_org(o uuid)
returns integer
language sql stable security definer set search_path = public as $fn$
  select coalesce(sum(t.coste_milesimas), 0)::int
    from public.rx_etapa t
    join public.rx_ejecucion e on e.id = t.ejecucion_id
    join public.rx_grupo g     on g.id = e.grupo_id
   where g.organizacion_id = o
     and t.terminada >= date_trunc('month', now());
$fn$;

-- Un solo sitio decide si se puede seguir gastando. Lo llaman tanto "crear
-- ejecucion" como "lanzar etapa": un cupo que solo se mira al crear se salta
-- relanzando etapas.
create or replace function public.rx_puede(g uuid, m smallint, crear boolean)
returns jsonb
language plpgsql stable security definer set search_path = public as $fn$
declare
  fila   public.rx_grupo%rowtype;
  tope_o integer;
  usadas integer;
  gasto_g integer;
  gasto_o integer;
begin
  select * into fila from public.rx_grupo where id = g;
  if not found then
    return jsonb_build_object('puede', false, 'motivo', 'Ese grupo no existe.');
  end if;
  if not public.rx_ve_grupo(g) then
    return jsonb_build_object('puede', false, 'motivo', 'Ese grupo no es tuyo.');
  end if;
  if not fila.activo then
    return jsonb_build_object('puede', false,
      'motivo', 'Este grupo está cerrado. Habla con el facilitador.');
  end if;

  usadas  := public.rx_cadenas_en_modulo(g, m);
  gasto_g := public.rx_gasto_mes_grupo(g);
  select coalesce(t.milesimas_mes, 50000) into tope_o
    from public.rx_tope t where t.organizacion_id = fila.organizacion_id;
  tope_o  := coalesce(tope_o, 50000);
  gasto_o := public.rx_gasto_mes_org(fila.organizacion_id);

  if crear and usadas >= fila.cupo_por_modulo then
    return jsonb_build_object('puede', false, 'usadas', usadas, 'cupo', fila.cupo_por_modulo,
      'motivo', format('Habéis usado las %s ejecuciones del módulo %s. Si necesitáis otra, pídesela al facilitador.',
                       fila.cupo_por_modulo, m));
  end if;
  if gasto_g >= fila.tope_milesimas_mes then
    return jsonb_build_object('puede', false, 'motivo',
      'Se ha alcanzado el tope de gasto del grupo para este mes.');
  end if;
  if gasto_o >= tope_o then
    return jsonb_build_object('puede', false, 'motivo',
      'Se ha alcanzado el tope de gasto de la organización para este mes.');
  end if;

  return jsonb_build_object('puede', true, 'usadas', usadas, 'cupo', fila.cupo_por_modulo,
                            'gasto_grupo_milesimas', gasto_g,
                            'restantes', greatest(fila.cupo_por_modulo - usadas, 0));
end;
$fn$;

-- Lo que la pagina necesita saber nada mas entrar: quien soy y que grupo tengo.
create or replace function public.rx_quien_soy()
returns jsonb
language sql stable security definer set search_path = public as $fn$
  select coalesce(
    (select jsonb_build_object(
       'grupo_id', g.id, 'grupo', g.nombre, 'edicion', g.edicion,
       'organizacion', o.nombre, 'organizacion_id', o.id,
       'rol', m.rol, 'activo', g.activo,
       'cupo_por_modulo', g.cupo_por_modulo,
       'aviso_datos_aceptado', m.aviso_datos_aceptado)
       from public.rx_miembro m
       join public.organizacion o on o.id = m.organizacion_id
       left join public.rx_grupo g on g.id = coalesce(m.grupo_id,
              (select gg.id from public.rx_grupo gg
                where gg.organizacion_id = m.organizacion_id order by gg.creado limit 1))
      where m.user_id = auth.uid()
      limit 1),
    jsonb_build_object('grupo_id', null));
$fn$;

create or replace function public.rx_aceptar_aviso()
returns timestamptz
language sql volatile security definer set search_path = public as $fn$
  update public.rx_miembro set aviso_datos_aceptado = now()
   where user_id = auth.uid() and aviso_datos_aceptado is null
  returning aviso_datos_aceptado;
$fn$;

-- ------------------------------------------------------------------ permisos

alter table public.rx_tope enable row level security;
drop policy if exists rx_tope_ver on public.rx_tope;
create policy rx_tope_ver on public.rx_tope for select to authenticated
  using ( public.rx_ve_org(organizacion_id) );

revoke all on public.rx_tope from public, anon;
grant select on public.rx_tope to authenticated;

revoke execute on function
  public.rx_cadenas_en_modulo(uuid, smallint), public.rx_gasto_mes_grupo(uuid),
  public.rx_gasto_mes_org(uuid), public.rx_puede(uuid, smallint, boolean),
  public.rx_quien_soy(), public.rx_aceptar_aviso()
  from public, anon;
grant execute on function
  public.rx_cadenas_en_modulo(uuid, smallint), public.rx_gasto_mes_grupo(uuid),
  public.rx_gasto_mes_org(uuid), public.rx_puede(uuid, smallint, boolean),
  public.rx_quien_soy(), public.rx_aceptar_aviso()
  to authenticated;

-- El facilitador no tiene cupo: es quien lo reparte.
update public.rx_grupo set cupo_por_modulo = 999, tope_milesimas_mes = 200000
 where nombre = 'Facilitador';

commit;
