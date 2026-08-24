#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
015_analisis_pruebas_ipf.py

Análisis de las dos pruebas de validación de la estimación IPF de
trabajadores por cuenta propia y familiares (TCP/TF) de baja calificación
no agrícolas:

  Prueba 1 (validez interna, método): EPH Argentina.
      Insumo: data/eph_ipf_comparacion_agg_test.csv
  Prueba 2 (validez externa, pipeline completo): muestras censales IPUMS
      (47 países) vs estimación IPF sobre tablas OIT.
      Insumos: data/ipums_ifp_v2_tcp_by_calif.csv
               data/20251118_estimacion_tcp_final.csv
               data/tabla_tcps_final_sums.csv

Además corre un "self-test" del IPF sobre las trivariadas IPUMS
(targets bivariados tomados de la propia conjunta censal), que aísla el
error atribuible al supuesto de no-interacción de tercer orden del
error atribuible a los insumos (fuentes/pipeline OIT).

Salidas:
  data/test_ipf/comp_raking_ipums_full.csv   comparación celda a celda
  data/test_ipf/metricas_por_celda.csv       métricas por celda-categoría
  data/test_ipf/selftest_ipf_ipums.csv       self-test IPF sobre IPUMS
  data/test_ipf/celda_clave_paises.csv       celda de interés por país
  reports/figs/*.png                          figuras del informe

Nota: script en Python (pandas/numpy/matplotlib) porque los scripts R
originales dependen de insumos no versionados (./data/estimacion_estancada/,
../PIMSA_spr_mundo/). Este script usa exclusivamente archivos del repo.
"""

import os
import numpy as np
import pandas as pd
import pycountry
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ----------------------------------------------------------------------
# Paleta y estilo (dataviz reference palette, modo claro)
# ----------------------------------------------------------------------
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK2 = "#52514e"
MUTED = "#898781"
GRID = "#e1e0d9"
BASELINE = "#c3c2b7"
S1 = "#2a78d6"   # azul   -> estimación (IPF / raking)
S2 = "#1baf7a"   # aqua   -> observado (EPH / IPUMS)
S6 = "#e34948"   # rojo   -> modelo del bug / resaltado

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE,
    "savefig.facecolor": SURFACE,
    "axes.edgecolor": BASELINE, "axes.linewidth": 0.8,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6,
    "text.color": INK, "axes.labelcolor": INK2,
    "xtick.color": MUTED, "ytick.color": MUTED,
    "font.family": "sans-serif", "font.size": 9,
    "axes.titlesize": 10, "axes.titlecolor": INK,
    "axes.spines.top": False, "axes.spines.right": False,
    "legend.frameon": False,
})

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(DATA, "test_ipf")
FIGS = os.path.join(ROOT, "reports", "figs")
os.makedirs(OUT, exist_ok=True)
os.makedirs(FIGS, exist_ok=True)

import argparse
_ap = argparse.ArgumentParser(description="Análisis de las pruebas EPH e IPUMS")
_ap.add_argument("--estimacion",
                 default=os.path.join(DATA, "20251118_estimacion_tcp_final.csv"),
                 help="CSV de estimación IPF (largo) a validar contra IPUMS")
_ap.add_argument("--sufijo", default="",
                 help="sufijo para los nombres de salida (p. ej. _v2)")
_args = _ap.parse_args()
ESTIMACION_PATH = _args.estimacion
SUF = _args.sufijo


def O(name):
    """Ruta de salida CSV en OUT con el sufijo aplicado antes de la extensión."""
    root, ext = os.path.splitext(name)
    return os.path.join(OUT, f"{root}{SUF}{ext}")


def F(name):
    """Ruta de figura en FIGS con el sufijo aplicado antes de la extensión."""
    root, ext = os.path.splitext(name)
    return os.path.join(FIGS, f"{root}{SUF}{ext}")


KEY = dict(calificacion="1.Baja", ocupacion="3.TCP_fliares", rama="2.No_agro")


def is_key(df):
    return ((df.calificacion == KEY["calificacion"])
            & (df.ocupacion == KEY["ocupacion"])
            & (df.rama == KEY["rama"]))


# ======================================================================
# PRUEBA 1 — EPH (Argentina)
# ======================================================================
print("=" * 70)
print("PRUEBA 1 — EPH-IPF (Argentina)")
print("=" * 70)

eph = pd.read_csv(os.path.join(DATA, "eph_ipf_comparacion_agg_test.csv"))
for c in ["prop", "prop_est", "prop_wei", "prop_est_wei"]:
    eph[c + "_pp"] = eph[c] * 100
eph["err_pp"] = eph.prop_est_pp - eph.prop_pp
eph["err_wei_pp"] = eph.prop_est_wei_pp - eph.prop_wei_pp

print(eph[["calif_agg", "cat_ocup_agg", "agro", "n",
           "prop_wei_pp", "prop_est_wei_pp", "err_wei_pp",
           "error_porc_wei"]].round(4).to_string(index=False))

print("\nMAE ponderado: %.4f pp | max |err|: %.4f pp"
      % (eph.err_wei_pp.abs().mean(), eph.err_wei_pp.abs().max()))
print("Índice de disimilitud (0.5*sum|dif|): %.3f pp"
      % (0.5 * eph.err_wei_pp.abs().sum()))
print("Pearson obs vs est (pond.): %.6f"
      % eph.prop_wei_pp.corr(eph.prop_est_wei_pp))

# --- Figura 1: observado vs estimado por celda (dumbbell, escala log) ---
e = eph.copy()
e["celda"] = (e.calif_agg.str.replace("_calif", "") + " × "
              + e.cat_ocup_agg + " × " + e.agro)
e = e.sort_values("prop_wei_pp")
fig, ax = plt.subplots(figsize=(7.2, 4.2))
y = np.arange(len(e))
ax.hlines(y, e.prop_wei_pp, e.prop_est_wei_pp, color=BASELINE, lw=1.5, zorder=1)
ax.scatter(e.prop_wei_pp, y, s=42, color=S2, zorder=3, label="EPH observado")
ax.scatter(e.prop_est_wei_pp, y, s=42, color=S1, zorder=2, label="IPF estimado",
           facecolors="none", edgecolors=S1, linewidths=1.8)
ax.set_xscale("log")
ax.set_yticks(y)
ax.set_yticklabels(e.celda, fontsize=8, color=INK2)
ax.set_xlabel("% del empleo total (escala log)")
ax.set_title("Prueba EPH (Argentina): distribución conjunta observada vs. estimada por IPF")
ax.legend(loc="lower right")
ax.grid(axis="y", visible=False)
fig.tight_layout()
fig.savefig(F("fig1_eph_obs_vs_ipf.png"), dpi=160)
plt.close(fig)

# ======================================================================
# PRUEBA 2 — IPUMS vs raking OIT-IPF
# ======================================================================
print("\n" + "=" * 70)
print("PRUEBA 2 — IPUMS-IPF (validez externa, 47 países)")
print("=" * 70)

ip = pd.read_csv(os.path.join(DATA, "ipums_ifp_v2_tcp_by_calif.csv"))

MANUAL_ISO = {"Iran": "IRN", "Palestine": "PSE", "Vietnam": "VNM",
              "Tanzania": "TZA", "Slovak Republic": "SVK", "Bolivia": "BOL"}


def to_iso3(name):
    if name in MANUAL_ISO:
        return MANUAL_ISO[name]
    try:
        return pycountry.countries.lookup(name).alpha_3
    except LookupError:
        return None


ip["iso3c"] = ip.COUNTRY_lab.map(to_iso3)
assert ip.iso3c.notna().all(), "países IPUMS sin iso3c"

# Mapeo de categorías (mismo criterio que src/103_comp_ipums_raking.R)
ip["ocupacion"] = np.where(
    ip.cat_ocup.isin(["Own account worker", "Unpaid worker"]),
    "3.TCP_fliares", "1.Asalariado_patr")
ip["rama"] = np.where(ip.rama_agg == "Agro", "1.Agro", "2.No_agro")
ip["calificacion"] = ip.skill_level.map(
    {"Level 1": "1.Baja", "Level 2": "2.Media", "Level 3-4": "3.Alta"})

ipa = (ip.groupby(["iso3c", "calificacion", "ocupacion", "rama"],
                  as_index=False)[["n_raw", "n_wei"]].sum())
ipa["ipums_porc"] = 100 * ipa.n_wei / ipa.groupby("iso3c").n_wei.transform("sum")

rk = pd.read_csv(ESTIMACION_PATH)
# Armonización de etiquetas: la salida del IPF trae "3-Alta" (typo en 011);
# el script 103 mapea IPUMS a "3.Alta" -> sin esta línea el join pierde
# todas las celdas de calificación alta.
rk["calificacion"] = rk.calificacion.replace({"3-Alta": "3.Alta"})
rk = rk.rename(columns={"freq": "raking_porc"})

comp = rk.merge(ipa[["iso3c", "calificacion", "ocupacion", "rama",
                     "ipums_porc", "n_raw"]],
                on=["iso3c", "calificacion", "ocupacion", "rama"], how="inner")
comp["diff"] = comp.raking_porc - comp.ipums_porc

tf = (pd.read_csv(os.path.join(DATA, "tabla_tcps_final_sums.csv"))
      .drop_duplicates(subset="iso3c", keep="first"))
comp = comp.merge(tf[["iso3c", "region", "income_group_2", "cluster_pimsa",
                      "prop_tcp_fliares_no_agro"]], on="iso3c", how="left")

print("Países IPUMS: %d | con estimación raking: %d (falta: %s)"
      % (ipa.iso3c.nunique(), comp.iso3c.nunique(),
         sorted(set(ipa.iso3c) - set(rk.iso3c))))
print("Celdas comparadas: %d" % len(comp))
print("Global  Pearson %.3f | Spearman %.3f | MAE %.2f pp | mediana |dif| %.2f pp"
      % (comp.raking_porc.corr(comp.ipums_porc),
         comp.raking_porc.corr(comp.ipums_porc, method="spearman"),
         comp["diff"].abs().mean(), comp["diff"].abs().median()))

# --- métricas por celda-categoría ---
met = (comp.groupby(["rama", "ocupacion", "calificacion"])
       .apply(lambda d: pd.Series({
           "n_paises": len(d),
           "pearson": d.raking_porc.corr(d.ipums_porc),
           "spearman": d.raking_porc.corr(d.ipums_porc, method="spearman"),
           "MAE_pp": d["diff"].abs().mean(),
           "bias_pp": d["diff"].mean(),
           "media_ipums": d.ipums_porc.mean(),
           "media_raking": d.raking_porc.mean()}), include_groups=False)
       .round(3).reset_index())
print("\nMétricas por celda:")
print(met.to_string(index=False))
met.to_csv(O("metricas_por_celda.csv"), index=False)
comp.to_csv(O("comp_raking_ipums_full.csv"), index=False)

# --- celda de interés ---
key = comp[is_key(comp)].copy()
key["rank_ipums"] = key.ipums_porc.rank()
key["rank_raking"] = key.raking_porc.rank()
key.sort_values("diff").to_csv(O("celda_clave_paises.csv"),
                               index=False)
print("\nCelda clave (TCP_fliares × No_agro × Baja): n=%d" % len(key))
print("Pearson %.3f | Spearman %.3f | MAE %.2f pp | bias %.2f pp"
      % (key.raking_porc.corr(key.ipums_porc),
         key.raking_porc.corr(key.ipums_porc, method="spearman"),
         key["diff"].abs().mean(), key["diff"].mean()))

# --- Figura 2: scatter por celda (12 paneles) ---
cells = met[["rama", "ocupacion", "calificacion"]].values.tolist()
fig, axes = plt.subplots(3, 4, figsize=(10.5, 7.6))
order = [(r, o, c) for r in ["1.Agro", "2.No_agro"]
         for o in ["1.Asalariado_patr", "3.TCP_fliares"]
         for c in ["1.Baja", "2.Media", "3.Alta"]]
for ax, (r, o, c) in zip(axes.flat, order):
    d = comp[(comp.rama == r) & (comp.ocupacion == o) & (comp.calificacion == c)]
    lim = max(d.raking_porc.max(), d.ipums_porc.max()) * 1.08 + 0.05
    ax.plot([0, lim], [0, lim], color=BASELINE, lw=1, zorder=1)
    ax.scatter(d.ipums_porc, d.raking_porc, s=16, color=S1, alpha=0.75, zorder=2)
    ax.set_xlim(0, lim); ax.set_ylim(0, lim)
    ax.set_title("%s × %s\n× %s" % (r[2:], o[2:], c[2:]), fontsize=8)
    rho = d.raking_porc.corr(d.ipums_porc, method="spearman")
    ax.text(0.05, 0.92, "ρ=%.2f" % rho, transform=ax.transAxes,
            fontsize=8, color=INK2, va="top")
    if (r, o, c) == ("2.No_agro", "3.TCP_fliares", "1.Baja"):
        for sp in ax.spines.values():
            sp.set_visible(True); sp.set_color(S6); sp.set_linewidth(1.4)
fig.supxlabel("IPUMS (censo, % del empleo)", color=INK2, fontsize=9)
fig.supylabel("OIT-IPF (raking, % del empleo)", color=INK2, fontsize=9)
fig.suptitle("Prueba IPUMS: estimación OIT-IPF vs. censo, por celda de la trivariada "
             "(46 países; recuadro rojo = celda de interés)", fontsize=10)
fig.tight_layout(rect=[0.01, 0.01, 1, 0.97])
fig.savefig(F("fig2_ipums_scatter_celdas.png"), dpi=160)
plt.close(fig)

# --- Figura 3: celda clave, scatter con etiquetas de país ---
fig, ax = plt.subplots(figsize=(6.6, 6))
lim = max(key.ipums_porc.max(), key.raking_porc.max()) * 1.1
ax.plot([0, lim], [0, lim], color=BASELINE, lw=1, zorder=1)
ax.scatter(key.ipums_porc, key.raking_porc, s=30, color=S1, zorder=2)
for _, r in key.iterrows():
    ax.annotate(r.iso3c, (r.ipums_porc, r.raking_porc), fontsize=7,
                color=INK2, xytext=(3, 3), textcoords="offset points")
ax.set_xlabel("IPUMS (censo): TCP/TF baja calif. no agro, % del empleo")
ax.set_ylabel("OIT-IPF (raking), % del empleo")
rho = key.raking_porc.corr(key.ipums_porc, method="spearman")
ax.set_title("Celda de interés por país (ρ Spearman = %.2f; recta = identidad)" % rho)
fig.tight_layout()
fig.savefig(F("fig3_celda_clave_scatter.png"), dpi=160)
plt.close(fig)

# ======================================================================
# SELF-TEST IPF sobre IPUMS: error atribuible sólo al supuesto del método
# ======================================================================
print("\n" + "=" * 70)
print("SELF-TEST IPF sobre trivariadas IPUMS")
print("=" * 70)

CAL = ["1.Baja", "2.Media", "3.Alta"]
OCU = ["1.Asalariado_patr", "3.TCP_fliares"]
RAM = ["1.Agro", "2.No_agro"]


def ipf3(joint, iters=2000, tol=1e-12):
    """IPF con seed uniforme y los tres márgenes bivariados de `joint`."""
    t12, t13, t23 = joint.sum(2), joint.sum(1), joint.sum(0)
    x = np.ones_like(joint) / joint.size * joint.sum()
    for _ in range(iters):
        m = x.sum(2)
        x *= np.where(m > 0, t12 / np.where(m == 0, 1, m), 0)[:, :, None]
        m = x.sum(1)
        x *= np.where(m > 0, t13 / np.where(m == 0, 1, m), 0)[:, None, :]
        m = x.sum(0)
        x *= np.where(m > 0, t23 / np.where(m == 0, 1, m), 0)[None, :, :]
        if np.abs(x.sum(2) - t12).max() < tol:
            break
    return x


rows = []
for iso, d in comp.groupby("iso3c"):
    J = np.zeros((3, 2, 2))
    for _, r in d.iterrows():
        J[CAL.index(r.calificacion), OCU.index(r.ocupacion),
          RAM.index(r.rama)] = r.ipums_porc
    est = ipf3(J)
    for i, c in enumerate(CAL):
        for j, o in enumerate(OCU):
            for k, rr in enumerate(RAM):
                rows.append(dict(iso3c=iso, calificacion=c, ocupacion=o,
                                 rama=rr, ipums_true=J[i, j, k],
                                 ipf_self=est[i, j, k]))
st = pd.DataFrame(rows)
st["err"] = st.ipf_self - st.ipums_true
st.to_csv(O("selftest_ipf_ipums.csv"), index=False)

kst = st[is_key(st)]
print("MAE global: %.3f pp | p90 |err|: %.3f pp | max: %.3f pp"
      % (st.err.abs().mean(), st.err.abs().quantile(0.9), st.err.abs().max()))
print("Celda clave: MAE %.3f pp | bias %.3f pp | Spearman %.3f"
      % (kst.err.abs().mean(), kst.err.mean(),
         kst.ipums_true.corr(kst.ipf_self, method="spearman")))

# --- Figura 4: ECDF de |error| en la celda clave, método vs pipeline ---
fig, ax = plt.subplots(figsize=(6.6, 4.2))
for vals, col, lab in [
        (kst.err.abs().values, S1, "Sólo supuesto IPF (self-test IPUMS)"),
        (key["diff"].abs().values, S2, "Pipeline completo OIT-IPF vs. IPUMS")]:
    v = np.sort(vals)
    ax.step(np.concatenate([[0], v]),
            np.linspace(0, 1, len(v) + 1), where="post", lw=2, color=col,
            label=lab)
ax.set_xlabel("|error| en la celda de interés (puntos porcentuales)")
ax.set_ylabel("Proporción acumulada de países")
ax.set_ylim(0, 1.02)
ax.set_title("Descomposición del error en la celda de interés (46 países)")
ax.legend(loc="lower right")
fig.tight_layout()
fig.savefig(F("fig4_ecdf_error_descomposicion.png"), dpi=160)
plt.close(fig)

# ======================================================================
# MARGEN DE RAMA: evidencia del problema de agregación en 011
# ======================================================================
print("\n" + "=" * 70)
print("MARGEN DE RAMA (agro) — diagnóstico")
print("=" * 70)

marg = (comp.groupby(["iso3c", "rama"])[["raking_porc", "ipums_porc"]]
        .sum().reset_index())
agro = marg[marg.rama == "1.Agro"].copy()
agro["diff_agro"] = agro.raking_porc - agro.ipums_porc
print("Margen %%Agro raking-IPUMS: bias %.1f pp | MAE %.1f pp | r %.3f"
      % (agro.diff_agro.mean(), agro.diff_agro.abs().mean(),
         agro.raking_porc.corr(agro.ipums_porc)))

# Curva del bug: si "No agro" se promedia entre las 5 categorías ECO del
# agregado ILOSTAT en lugar de sumarse, el margen agro observado en la
# estimación sería f(a) = a / (a + (100-a)/5).
a_grid = np.linspace(0.2, 95, 400)
f_bug = 100 * a_grid / (a_grid + (100 - a_grid) / 5)

fig, ax = plt.subplots(figsize=(6.6, 5))
ax.plot([0, 100], [0, 100], color=BASELINE, lw=1, label="Identidad")
ax.plot(a_grid, f_bug, color=S6, lw=2,
        label="Curva del bug: a/(a+(100−a)/5)")
ax.scatter(agro.ipums_porc, agro.raking_porc, s=26, color=S1, zorder=3,
           label="Países (margen % agro)")
for _, r in agro.nlargest(8, "diff_agro").iterrows():
    ax.annotate(r.iso3c, (r.ipums_porc, r.raking_porc), fontsize=7,
                color=INK2, xytext=(4, 0), textcoords="offset points")
ax.set_xlabel("% empleo agro según IPUMS (censo)")
ax.set_ylabel("% empleo agro implícito en la estimación OIT-IPF")
ax.set_title("El margen de rama de la estimación sigue la curva del error de agregación")
ax.legend(loc="lower right")
xmax = agro.ipums_porc.max() * 1.08
ax.set_xlim(0, xmax); ax.set_ylim(0, 92)
fig.tight_layout()
fig.savefig(F("fig5_margen_agro_bug.png"), dpi=160)
plt.close(fig)

# Margen TCP×No_agro: IPF vs cálculo directo OIT (013) vs IPUMS
m_ipf = (comp[(comp.ocupacion == "3.TCP_fliares") & (comp.rama == "2.No_agro")]
         .groupby("iso3c").raking_porc.sum().rename("ipf"))
m_oit = tf.set_index("iso3c").prop_tcp_fliares_no_agro.rename("oit_directo")
m_ipu = (comp[(comp.ocupacion == "3.TCP_fliares") & (comp.rama == "2.No_agro")]
         .groupby("iso3c").ipums_porc.sum().rename("ipums"))
m = pd.concat([m_ipf, m_oit, m_ipu], axis=1).dropna()
print("\nMargen TCP/TF × No_agro (n=%d):" % len(m))
print("  IPF vs IPUMS        : MAE %.2f pp | r %.3f | rho %.3f"
      % ((m.ipf - m.ipums).abs().mean(), m.ipf.corr(m.ipums),
         m.ipf.corr(m.ipums, method="spearman")))
print("  OIT-directo vs IPUMS: MAE %.2f pp | r %.3f | rho %.3f"
      % ((m.oit_directo - m.ipums).abs().mean(), m.oit_directo.corr(m.ipums),
         m.oit_directo.corr(m.ipums, method="spearman")))
m.round(3).to_csv(O("margen_tcp_noagro_3fuentes.csv"))

print("\nListo. Salidas en data/test_ipf/ y reports/figs/")
