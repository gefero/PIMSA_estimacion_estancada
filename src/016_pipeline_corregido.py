#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
016_pipeline_corregido.py

Pipeline de estimación IPF con la agregación CORREGIDA, reproducible desde
las tablas crudas de ILOSTAT versionadas en el repo (data/raw_data/).

Equivale a correr 011 (corregido) + 012 + los indicadores marginales de 013:
  1. Lee las tres tablas largas crudas (exports pre-agregación de 011).
  2. Agrega correctamente: sum de las categorías finas DENTRO de cada año,
     luego mean entre años. (El bug original hacía mean directo, dividiendo
     "No_agro" por ~5 y las categorías ICSE agrupadas por ~2-3.)
  3. Descarta 9.SD, normaliza cada bivariada a 100 y corre el IPF por país.
  4. Recalcula los indicadores marginales de 013 desde los crudos.

Salidas:
  data/estimacion_tcp_final_corregida.csv       trivariada larga por país
  data/tabla_tcps_final_sums_corregida.csv      indicadores por país
Chequeos integrados: aborta con AssertionError si algo no cierra.
"""

import os
import numpy as np
import pandas as pd

from ipf_utils import CAL, OCU, RAM, ipf3_targets

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
RAW = os.path.join(DATA, "raw_data")

USECOLS = ["ref_area", "ref_area.label", "time", "obs_value"]

# ----------------------------------------------------------------------
# 1. Carga de crudos
# ----------------------------------------------------------------------
cr = pd.read_csv(os.path.join(RAW, "calif_rama.csv"),
                 usecols=USECOLS + ["rama2", "calif"])
tr = pd.read_csv(os.path.join(RAW, "catocup_rama.csv"),
                 usecols=USECOLS + ["rama2", "catocup"])
tc = pd.read_csv(os.path.join(RAW, "catocup_calif.csv"),
                 usecols=USECOLS + ["catocup", "calif"])
# los crudos actuales aún traen la etiqueta vieja
tc["calif"] = tc.calif.replace({"3-Alta": "3.Alta"})

labels = (pd.concat([t[["ref_area", "ref_area.label"]] for t in (cr, tr, tc)])
          .drop_duplicates("ref_area").set_index("ref_area")["ref_area.label"])

paises = sorted(set(cr.ref_area) & set(tr.ref_area) & set(tc.ref_area))
print(f"Países en la intersección de las tres tablas: {len(paises)}")


# ----------------------------------------------------------------------
# 2. Agregación corregida
# ----------------------------------------------------------------------
def agg_corregida(df, dims):
    """sum de categorías finas dentro de cada año -> mean entre años."""
    return (df.groupby(["ref_area", "time"] + dims).obs_value.sum()
              .groupby(["ref_area"] + dims).mean()
              .rename("n").reset_index())


a_tc = agg_corregida(tc, ["catocup", "calif"])   # ocup x calif
a_tr = agg_corregida(tr, ["catocup", "rama2"])   # ocup x rama
a_cr = agg_corregida(cr, ["calif", "rama2"])     # calif x rama


def tabla_pct(df, iso, fila, col, flev, clev):
    """Matriz bivariada de un país, sin 9.SD, normalizada a 100."""
    d = df[(df.ref_area == iso) & df[fila].isin(flev) & df[col].isin(clev)]
    m = (d.pivot_table(index=fila, columns=col, values="n", aggfunc="sum")
         .reindex(index=flev, columns=clev).fillna(0).values)
    s = m.sum()
    return m / s * 100 if s > 0 else m


# ----------------------------------------------------------------------
# 3. IPF por país
# ----------------------------------------------------------------------
rows = []
for iso in paises:
    t12 = tabla_pct(a_tc, iso, "calif", "catocup", CAL, OCU)  # calif x ocup
    t23 = tabla_pct(a_tr, iso, "catocup", "rama2", OCU, RAM)  # ocup x rama
    t13 = tabla_pct(a_cr, iso, "calif", "rama2", CAL, RAM)    # calif x rama
    if t12.sum() == 0 or t23.sum() == 0 or t13.sum() == 0:
        print(f"  {iso}: tabla vacía tras filtrar 9.SD — se omite")
        continue
    x = ipf3_targets(t12, t13, t23)
    for i, c in enumerate(CAL):
        for j, o in enumerate(OCU):
            for k, r in enumerate(RAM):
                rows.append((iso, c, o, r, x[i, j, k]))

est = pd.DataFrame(rows, columns=["iso3c", "calificacion", "ocupacion",
                                  "rama", "freq"])

# ---- chequeos de la estimación ----
sumas = est.groupby("iso3c").freq.sum()
assert np.allclose(sumas, 100, atol=0.5), \
    f"trivariadas que no suman 100: {sumas[(sumas-100).abs()>0.5].index.tolist()}"
assert not est.calificacion.str.contains("3-Alta").any()
assert est.iso3c.value_counts().max() == 12

est.to_csv(os.path.join(DATA, "estimacion_tcp_final_corregida.csv"), index=False)
print(f"Estimación corregida: {est.iso3c.nunique()} países -> "
      "data/estimacion_tcp_final_corregida.csv")

# ----------------------------------------------------------------------
# 4. Indicadores marginales (equivalente a 013, desde crudos corregidos)
# ----------------------------------------------------------------------
tr_ok = tr[(tr.catocup != "9.SD") & (tr.rama2 != "9.SD")]
tc_ok = tc[(tc.catocup != "9.SD") & (tc.calif != "9.SD")]
cr_ok = cr[(cr.rama2 != "9.SD") & (cr.calif != "9.SD")]


def total_tabla(df):
    """Total de empleo por país: sum de celdas dentro del año -> mean años."""
    return (df.groupby(["ref_area", "time"]).obs_value.sum()
            .groupby("ref_area").mean())


# Cada indicador se normaliza por el total de SU PROPIA tabla bivariada, como
# en 013: las tres tablas OIT tienen coberturas distintas y no comparten total.
tot_tr = total_tabla(tr_ok)   # total según catocup_rama (= ocup_totales de 013)
tot_tc = total_tabla(tc_ok)   # total según catocup_calif
tot_cr = total_tabla(cr_ok)   # total según calif_rama
ocup_tot = tot_tr.rename("n_ocup_totales")


def indicador(df, tot, filtro, nombre):
    d = df.query(filtro)
    n = (d.groupby(["ref_area", "time"]).obs_value.sum()
         .groupby("ref_area").mean())
    return (100 * n / tot).rename("prop_" + nombre), n.rename("n_" + nombre)


p_tcp, n_tcp = indicador(tr_ok, tot_tr, "catocup=='3.TCP_fliares'",
                         "tcp_fliares_totales")
p_tcp_cb, n_tcp_cb = indicador(tc_ok, tot_tc,
                               "catocup=='3.TCP_fliares' & calif=='1.Baja'",
                               "tcp_fliares_calif_baja")
p_tcp_na, n_tcp_na = indicador(tr_ok, tot_tr,
                               "catocup=='3.TCP_fliares' & rama2=='2.No_agro'",
                               "tcp_fliares_no_agro")
p_na_cb, n_na_cb = indicador(cr_ok, tot_cr,
                             "calif=='1.Baja' & rama2=='2.No_agro'",
                             "no_agro_calif_baja")

# share global de cada país en el empleo total (peso de 014)
prop_ocup = (100 * ocup_tot / ocup_tot.sum()).rename("prop_ocup_totales")

celda = (est[(est.calificacion == "1.Baja") & (est.ocupacion == "3.TCP_fliares")
             & (est.rama == "2.No_agro")]
         .set_index("iso3c").freq.rename("prop_tcp_fliares_no_agro_calif_baja"))

tabla = pd.concat([ocup_tot, n_tcp, n_tcp_cb, n_tcp_na, n_na_cb,
                   prop_ocup, p_tcp, p_tcp_cb, p_tcp_na, p_na_cb, celda], axis=1)
tabla.insert(0, "ref_area.label", labels.reindex(tabla.index))

# clasificación de países (dedupeada) desde la tabla publicada
clasif = (pd.read_csv(os.path.join(DATA, "tabla_tcps_final_sums.csv"))
          .drop_duplicates("iso3c")
          .set_index("iso3c")[["country", "region", "income_group",
                               "income_group_2", "cluster_pimsa",
                               "peq_estado", "excl_tamaño", "ocde"]])
tabla = clasif.join(tabla, how="right").reset_index(names="iso3c")

assert not tabla.iso3c.duplicated().any(), "iso3c duplicados en la tabla final"
tabla.to_csv(os.path.join(DATA, "tabla_tcps_final_sums_corregida.csv"),
             index=False)
print(f"Tabla final corregida: {len(tabla)} países -> "
      "data/tabla_tcps_final_sums_corregida.csv")

# ----------------------------------------------------------------------
# 5. Chequeos de validez de los márgenes corregidos
# ----------------------------------------------------------------------
agro = est[est.rama == "1.Agro"].groupby("iso3c").freq.sum()

# spot-checks contra valores conocidos de ILOSTAT (promedios 2009-2019 aprox.)
SPOT = {"PER": (24, 30), "FRA": (2, 4), "BRA": (8, 13), "USA": (1, 3),
        "ECU": (24, 31), "ARG": (0.2, 2)}
for iso, (lo, hi) in SPOT.items():
    assert lo <= agro[iso] <= hi, \
        f"margen agro de {iso} = {agro[iso]:.1f}%, fuera de [{lo},{hi}]"
print("Spot-checks de margen agro: OK",
      {k: round(agro[k], 1) for k in SPOT})

# margen agro vs censos IPUMS (si la comparación de 015 está disponible)
comp_path = os.path.join(DATA, "test_ipf", "comp_raking_ipums_full.csv")
if os.path.exists(comp_path):
    comp = pd.read_csv(comp_path)
    ipums_agro = comp[comp.rama == "1.Agro"].groupby("iso3c").ipums_porc.sum()
    j = pd.concat([agro.rename("corr"), ipums_agro.rename("ipums")],
                  axis=1).dropna()
    bias = (j.corr - j.ipums).mean()
    print(f"Margen agro corregido vs IPUMS (n={len(j)}): bias {bias:+.1f} pp | "
          f"r {j.corr.corr(j.ipums):.3f}  (estimación previa: +24.8 pp)")
    assert abs(bias) < 5, f"bias del margen agro vs IPUMS = {bias:.1f} pp"

print("\nTodos los chequeos pasaron.")
