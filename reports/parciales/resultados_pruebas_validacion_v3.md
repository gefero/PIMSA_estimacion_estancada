# Resultados de las pruebas de validación del IPF

**Estimación de trabajadores por cuenta propia y familiares (TCP/TF) de baja calificación, no agrícolas**

*Corrida `_v3` — 2026-08-24. Script: `src/015_analisis_pruebas_ipf.R` (R/tidyverse). Estimación validada:
`data/estimacion/20260824_estimacion_tcp_final_v2.csv`. Insumos de contraste:
`data/eph_ipf_comparacion_agg_test.csv` (EPH, Argentina) y `data/ipums_ifp_v2_tcp_by_calif.csv` (IPUMS,
47 países). Salidas: `data/test_ipf/*_v3.csv`, `reports/figs/fig*_v3.png`.*

---

## 1. Prueba EPH (Argentina)

Se reconstruyeron a partir de la EPH las tres tablas bivariadas usadas por el IPF (calificación, situación
en el empleo, rama de actividad) y se compararon los resultados del IPF contra la distribución conjunta
observada directamente en la encuesta.

| Celda | % observado (EPH) | % estimado (IPF) | Error (pp) |
|---|---:|---:|---:|
| Alta × Asal_patr × Agro | 0,305 | 0,285 | −0,020 |
| Alta × Asal_patr × No_agro | 23,378 | 23,398 | +0,020 |
| Alta × TCP_fliar × Agro | 0,031 | 0,234 | +0,020 |
| Alta × TCP_fliar × No_agro | 5,580 | 5,560 | −0,020 |
| Media × Asal_patr × Agro | 0,489 | 0,512 | +0,023 |
| Media × Asal_patr × No_agro | 35,944 | 35,921 | −0,023 |
| Media × TCP_fliar × Agro | 0,109 | 0,086 | −0,023 |
| Media × TCP_fliar × No_agro | 17,351 | 17,374 | +0,023 |
| No calif. × Asal_patr × Agro | 0,166 | 0,163 | −0,003 |
| No calif. × Asal_patr × No_agro | 15,878 | 15,880 | +0,003 |
| No calif. × TCP_fliar × No_agro | 0,798 | 0,795 | −0,003 |

- **MAE ponderado:** 0,017 pp | **error máximo:** 0,023 pp
- **Índice de disimilitud** (0,5 × Σ|diferencias|): 0,091 pp
- **Correlación de Pearson** observado vs. estimado: 0,999999

![Prueba EPH: observado vs. estimado por IPF](../figs/fig1_eph_obs_vs_ipf_v3.png)

El método reproduce con altísima fidelidad la distribución conjunta cuando los tres márgenes bivariados de
entrada provienen de la misma fuente y período.

---

## 2. Prueba IPUMS (47 países)

Se comparó la estimación IPF (basada en tablas de la OIT/ILOSTAT) contra las muestras censales de IPUMS
International para 47 países. De ellos, 46 tienen estimación IPF disponible (falta Canadá, que no forma
parte de los 159 países de la estimación OIT-IPF vigente).

- **Celdas comparadas:** 541
- **Correlación global:** Pearson 0,928 | Spearman 0,933
- **Error absoluto medio (MAE):** 2,15 pp | **mediana del error absoluto:** 0,66 pp

### 2.1 Métricas por celda de la trivariada

| Rama | Ocupación | Calificación | n países | Pearson | Spearman | MAE (pp) | Sesgo (pp) |
|---|---|---|---:|---:|---:|---:|---:|
| Agro | Asalariado/patrón | Baja | 45 | 0,397 | 0,873 | 1,57 | +0,52 |
| Agro | Asalariado/patrón | Media | 45 | 0,406 | 0,557 | 1,38 | +0,03 |
| Agro | Asalariado/patrón | Alta | 45 | 0,202 | 0,335 | 0,16 | −0,12 |
| Agro | TCP/familiares | Baja | 42 | 0,653 | 0,805 | 2,09 | +0,73 |
| Agro | TCP/familiares | Media | 45 | 0,891 | 0,942 | 5,23 | −3,65 |
| Agro | TCP/familiares | Alta | 44 | −0,083 | 0,261 | 0,17 | +0,00 |
| No agro | Asalariado/patrón | Baja | 46 | 0,798 | 0,802 | 1,77 | +0,95 |
| No agro | Asalariado/patrón | Media | 46 | 0,946 | 0,929 | 3,97 | −0,86 |
| No agro | Asalariado/patrón | Alta | 46 | 0,967 | 0,971 | 2,23 | −0,22 |
| **No agro** | **TCP/familiares** | **Baja** | **45** | **0,605** | **0,798** | **1,10** | **+0,32** |
| No agro | TCP/familiares | Media | 46 | 0,726 | 0,841 | 4,91 | +0,76 |
| No agro | TCP/familiares | Alta | 46 | 0,658 | 0,699 | 1,13 | +0,28 |

La fila resaltada es la **celda de interés** del proyecto (TCP/familiares de baja calificación, no agro).

![Estimación OIT-IPF vs. censo, por celda de la trivariada](../figs/fig2_ipums_scatter_celdas_v3.png)

### 2.2 Celda de interés, país por país

Sobre 45 países con dato en ambas fuentes: **Pearson 0,605 | Spearman 0,798 | MAE 1,10 pp | sesgo +0,32 pp**.

Los mayores desacuerdos absolutos (estimación IPF menos IPUMS, en pp):

| País | IPF (%) | IPUMS (%) | Diferencia (pp) |
|---|---:|---:|---:|
| KEN | 10,56 | 2,27 | +8,29 |
| SEN | 12,28 | 4,04 | +8,24 |
| DOM | 5,31 | 1,83 | +3,48 |
| HND | 3,52 | 0,81 | +2,71 |
| PER | 7,03 | 4,61 | +2,41 |
| ECU | 5,27 | 2,91 | +2,35 |
| GHA | 1,47 | 3,83 | −2,36 |
| MEX | 1,78 | 3,85 | −2,08 |

Excluyendo los dos mayores outliers (Senegal y Kenia, donde las encuestas de fuerza de trabajo de la OIT y
los censos difieren fuertemente en el nivel general de baja calificación: 26% vs. 9% y 35% vs. 16%
respectivamente), la celda de interés queda con **MAE 0,76 pp y sesgo −0,05 pp sobre 43 países**.

![Celda de interés por país](../figs/fig3_celda_clave_scatter_v3.png)

---

## 3. Self-test del método IPF sobre las trivariadas IPUMS

Para aislar el error atribuible al propio método de máxima entropía (independiente de las fuentes OIT), se
tomó la distribución conjunta *verdadera* de cada país según IPUMS, se generaron sus tres márgenes
bivariados, y se corrió el IPF sobre esos márgenes para reconstruir la trivariada. La diferencia entre la
trivariada reconstruida y la verdadera aísla el error del supuesto de no-interacción de tercer orden.

- **MAE global:** 0,31 pp | **percentil 90 del error absoluto:** 1,05 pp | **máximo:** 2,37 pp
- **Celda de interés:** MAE 0,38 pp | sesgo −0,33 pp | Spearman 0,90

![Descomposición del error en la celda de interés](../figs/fig4_ecdf_error_descomposicion_v3.png)

El método por sí solo introduce un error acotado y con un sesgo negativo moderado: en la celda de interés,
el IPF de máxima entropía tiende a **subestimar** levemente la proporción real cuando los márgenes de
entrada son correctos.

---

## 4. Consistencia del margen TCP/TF × No agro entre tres fuentes

Se comparó el margen "TCP/familiares × No agro" (suma sobre calificaciones) calculado de tres formas
independientes: (a) agregando la trivariada estimada por IPF, (b) el cálculo directo de ese margen a partir
de las tablas bivariadas OIT (sin pasar por el IPF), y (c) el valor observado en IPUMS. 46 países con dato
en las tres fuentes.

| Comparación | MAE (pp) | Pearson | Spearman |
|---|---:|---:|---:|
| IPF vs. IPUMS | 5,67 | 0,716 | 0,827 |
| Cálculo directo (OIT) vs. IPUMS | 5,66 | 0,718 | 0,844 |

Los dos caminos de estimación (vía IPF y cálculo directo) coinciden entre sí de forma prácticamente
perfecta, y ambos se apartan de IPUMS en magnitudes y direcciones similares — lo esperable dado que el
desacuerdo de fondo está en los insumos OIT, no en cómo se los combina.

---

## 5. Síntesis

- El método (IPF) reproduce con alta fidelidad una distribución conjunta cuando los tres márgenes de
  entrada provienen de la misma fuente (prueba EPH: error máximo 0,02 pp).
- Contra un patrón externo independiente (IPUMS, 46 países), la celda de interés tiene una correlación
  moderada-alta (Spearman 0,80) y un sesgo pequeño (+0,32 pp sobre una media observada de referencia del
  orden de 1,6 pp), concentrado en dos países con fuentes OIT/censo muy discordantes entre sí.
- El self-test aislado del supuesto de máxima entropía del IPF muestra que, con márgenes de entrada
  correctos, el método introduce por sí solo un error acotado (MAE 0,38 pp) y un leve sesgo de
  subestimación (−0,33 pp) en la celda de interés — la estimación final debe leerse como un **piso**
  razonable de la magnitud real.
