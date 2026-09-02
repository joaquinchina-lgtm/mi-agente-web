#!/usr/bin/env python3
"""
Prepara recursos_unificados.csv para cargarlo en la tabla `recurso`.

El CSV de origen viene con BOM, separado por ';' y con una columna `extras`
que es JSON entre comillas. Postgres no lo traga tal cual: este script lo
normaliza a coma, UTF-8 sin BOM, columnas en el orden exacto de la tabla y
vacíos como NULL en los campos numéricos y jsonb.

Uso:
    python preparar_recursos.py "<ruta>/recursos_unificados.csv" recurso.csv

Y después, contra Supabase (Connection string > psql):
    \copy recurso(universidad,universidad_nombre,ccaa,tipo_fuente,codigo,nombre,
      acronimo,responsable,unidad,area,lineas,n_lineas,calidad_lineas,
      palabras_clave,descripcion,servicios,equipamiento,oferta_tecnologica,
      url,web,tipo_registro,extras,fichero_origen)
      from 'recurso.csv' with (format csv, header true)

Comprobado el 02/09/2026 sobre las 7.795 filas reales: 0 duplicados por
(universidad, codigo, nombre), que es la clave única de la tabla.
"""
import csv, json, sys

COLS = ['universidad','universidad_nombre','ccaa','tipo_fuente','codigo','nombre',
        'acronimo','responsable','unidad','area','lineas','n_lineas','calidad_lineas',
        'palabras_clave','descripcion','servicios','equipamiento','oferta_tecnologica',
        'url','web','tipo_registro','extras','fichero_origen']

def main(origen, destino):
    csv.field_size_limit(10**7)
    vistos, filas, repes, malos_json = set(), 0, 0, 0
    with open(origen, encoding='utf-8-sig', newline='') as f, \
         open(destino, 'w', encoding='utf-8', newline='') as g:
        w = csv.DictWriter(g, fieldnames=COLS, extrasaction='ignore')
        w.writeheader()
        for r in csv.DictReader(f, delimiter=';'):
            clave = (r.get('universidad',''), r.get('codigo') or '', r.get('nombre',''))
            if clave in vistos:
                repes += 1
                continue
            vistos.add(clave)
            # n_lineas es int en la tabla: '' rompe el copy
            r['n_lineas'] = (r.get('n_lineas') or '').strip() or None
            # extras es jsonb: si no parsea, mejor NULL que abortar la carga entera
            ex = (r.get('extras') or '').strip()
            if ex:
                try:
                    json.loads(ex)
                except ValueError:
                    ex, malos_json = '', malos_json + 1
            r['extras'] = ex or None
            for c in COLS:
                if r.get(c) is not None and isinstance(r[c], str):
                    r[c] = r[c].strip() or None
            w.writerow(r)
            filas += 1
    print(f"{filas} filas escritas en {destino}")
    if repes:      print(f"  {repes} omitidas por clave repetida (universidad, codigo, nombre)")
    if malos_json: print(f"  {malos_json} campos `extras` no eran JSON válido: guardados como NULL")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
