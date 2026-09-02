-- ============================================================================
--  Memoria del Reactor · migración 0005 · registro y tope del traductor
--
--  El traductor llama a un modelo de pago desde una Edge Function. La pantalla
--  usa la clave publicable, que está en un repositorio PÚBLICO: sin tope,
--  cualquiera que la lea puede gastar el saldo de Joaquín. Esta tabla registra
--  cada llamada y permite cortar por volumen diario.
-- ============================================================================

create table if not exists traduccion (
  id          uuid primary key default gen_random_uuid(),
  problema    text not null,
  lineas      jsonb,
  error       text,
  creado_en   timestamptz not null default now()
);
create index if not exists traduccion_dia_idx on traduccion (creado_en desc);
alter table traduccion enable row level security;

comment on table traduccion is
  'Cada llamada al traductor. Sirve para el tope diario y para ver, pasado un '
  'tiempo, si las traducciones se parecen a lo que un mentor habría escrito.';

-- Devuelve cuántas traducciones van hoy. La Edge Function corta a partir del
-- tope; se cambia aquí y no hay que redesplegar la función.
create or replace function mr_traducciones_hoy()
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from traduccion where creado_en >= current_date;
$$;
revoke all on function mr_traducciones_hoy() from public;
