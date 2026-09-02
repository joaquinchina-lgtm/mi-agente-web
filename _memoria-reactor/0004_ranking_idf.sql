-- ============================================================================
--  Memoria del Reactor · migración 0004 · el buscador aprende a distinguir
--  palabras raras de palabras comunes.
--
--  EL PROBLEMA: ts_rank de Postgres puntúa por dónde y cuántas veces aparece un
--  término, pero NO por lo informativo que es. En este corpus "análisis" sale en
--  1.998 grupos y "batería" en 26, y pesaban lo mismo. Buscando "baterías de
--  estado sólido" salían grupos de física del estado sólido y de energía solar,
--  y ninguno de electroquímica.
--
--  LA CORRECCIÓN: se calcula la frecuencia documental de cada lexema del corpus
--  (lexema_df) y cada término de la consulta pesa por ln(N/df) — un término que
--  sale en 26 grupos informa mucho más que uno que sale en 1.998. La puntuación
--  se divide por la masa informativa total de la consulta, así que queda
--  entre 0 y 1 y es COMPARABLE entre búsquedas distintas, cosa que antes no era.
--
--  Medido: 28 ms sobre 7.795 recursos. Con el cambio, el segundo resultado de
--  "baterías de estado sólido" es Electroquímica Aplicada (UAM).
--
--  MANTENIMIENTO: lexema_df es una vista materializada. Cada vez que se carguen
--  recursos nuevos hay que refrescarla con select mr_refrescar_indice();
--  si no, los términos nuevos no tendrán frecuencia y se tratarán como raros.
-- ============================================================================

-- OJO: la tabla va CUALIFICADA dentro de ts_stat. `create materialized view`
-- ejecuta esa consulta con un search_path restringido y sin `public.` falla
-- con «relation "recurso" does not exist». En local no salta; en Supabase sí.
create materialized view if not exists lexema_df as
  select word as lexema, ndoc from ts_stat('select busqueda from public.recurso');
create unique index if not exists lexema_df_idx on lexema_df(lexema);

create or replace function mr_refrescar_indice()
returns int language sql security definer set search_path = public as $$
  refresh materialized view lexema_df;
  select count(*)::int from lexema_df;
$$;

create or replace function buscar_recursos(
  consulta text, limite int default 20, filtro_universidad text default null)
returns table (id uuid, nombre text, universidad text, responsable text,
               area text, lineas text, url text, score real, terminos int)
language sql stable security definer set search_path = public, extensions as $$
  with n as (select count(*)::numeric as total from recurso),
  lex as (
    select distinct unnest(tsvector_to_array(to_tsvector('es_sin_acentos', consulta))) as lexema
  ),
  pes as (
    select l.lexema, ln( (select total from n) / greatest(coalesce(d.ndoc,1),1) ) as idf
    from lex l left join lexema_df d on d.lexema = l.lexema
  ),
  tot as (select sum(idf) as masa, string_agg(lexema,' | ')::tsquery as tsq from pes)
  select * from (
    select r.id, r.nombre, r.universidad, r.responsable, r.area,
           left(r.lineas,400) as lineas, r.url,
           (m.puntos / nullif(tot.masa,0))::real as score, m.cubiertos as terminos
    from recurso r, tot,
      lateral (
        select coalesce(sum(p.idf * ts_rank_cd(r.busqueda, p.lexema::tsquery, 32)),0) as puntos,
               count(*)::int as cubiertos
        from pes p where r.busqueda @@ p.lexema::tsquery
      ) m
    where tot.tsq is not null and r.busqueda @@ tot.tsq
      and (filtro_universidad is null or r.universidad = filtro_universidad)
  ) s
  order by s.score desc, s.terminos desc, s.nombre
  limit greatest(1, least(limite,100));
$$;

grant execute on function buscar_recursos(text, int, text) to anon, authenticated;
revoke all on function mr_refrescar_indice() from public;
