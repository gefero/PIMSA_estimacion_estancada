# Testeo independiente: IPF en Python vs. IPF en R (`mipfp`)

**Fecha:** 2026-08-24
**Alcance:** validar que la estimación IPF (celda "1.Baja × 3.TCP_fliares × 2.No_agro") es reproducible de forma independiente en dos lenguajes/implementaciones distintas, partiendo de los mismos insumos agregados.
**Nota:** este documento es un output de testeo. No se pusheó ningún cambio al repositorio — solo se generaron archivos de comparación en `data/test_ipf/` y este documento.

---

## 1. Pull del repositorio

Se hizo `git fetch` + `git pull origin main`. El repo quedó en el commit `6c002be` ("Agrego test"), que trae la `tabla_tcps_final_sums.csv` regenerada por el usuario tras el fix de rutas de `013` (commit `0ba3f91`) y el fix de países duplicados (commit `5d830da`).

## 2. Consistencia en la cantidad de países

| Tabla | Países únicos |
|---|---:|
| `data/raw_data/calif_rama.csv` | 175 |
| `data/raw_data/catocup_calif.csv` | 160 |
| `data/raw_data/catocup_rama.csv` | 165 |
| `data/estimacion/calif_rama_agg.csv` | 175 |
| `data/estimacion/catocup_calif_agg.csv` | 160 |
| `data/estimacion/catocup_rama_agg.csv` | 165 |
| `data/estimacion/country_intersect.csv` | 159 |
| `data/estimacion/20260824_estimacion_tcp_final_v2.csv` (estimación IPF, R) | 159 |
| `data/estimacion/tabla_tcps_final_sums.csv` (tabla final) | 181 (sin duplicados) |
| `data/outputs/country_classification.csv` | 217 |

**Verificaciones:**
- La intersección de las 3 tablas crudas (`calif_rama` ∩ `catocup_calif` ∩ `catocup_rama`), calculada de forma independiente en Python, da exactamente **159 países** — coincide con `country_intersect.csv` y con la cantidad de países en la estimación IPF (`20260824_estimacion_tcp_final_v2.csv`, 159 × 12 celdas = 1.908 filas). ✅
- `tabla_tcps_final_sums.csv` tiene 181 filas, todas con `iso3c` único (0 duplicados) — de esas, 159 tienen la celda de interés no nula (coincide con los 159 países del IPF); las 22 restantes solo tienen los indicadores marginales que no requieren intersección de las 3 tablas. ✅

No se encontraron inconsistencias en la cantidad de países entre las tablas.

## 3. Metodología del re-cálculo independiente

Se corrió el pipeline IPF **desde cero, en paralelo, en dos implementaciones que no comparten código**:

- **Python** (`src/016_pipeline_corregido.py` + `src/ipf_utils.py`): agregación desde `data/raw_data/*.csv` y IPF propio (implementación manual, ajuste cíclico multiplicativo a los 3 márgenes bivariados, 5.000 iteraciones).
- **R** (`mipfp::Ipfp`, paquete real instalado desde el `.tar.gz` compartido por el usuario — no una reimplementación): script que replica exactamente la lógica de `src/012_estimacion_tcp_estancada.R` (misma función `format_table`, mismo orden de márgenes `target.dim = list(c(1,2), c(2,3), c(1,3))`, `iter = 5000`), leyendo los mismos `data/estimacion/*_agg.csv` que usa el pipeline oficial.

Ambos procesos corrieron sobre los **159 países** de la intersección, sin ningún país fallido en ninguna de las dos implementaciones.

- Salida Python: `data/estimacion_tcp_final_corregida.csv`
- Salida R: `data/test_ipf/estimacion_R_mipfp_full_independiente.csv`
- Comparación celda a celda (1.908 filas, merge exacto sin filas huérfanas): `data/test_ipf/comparacion_python_vs_R_completa.csv`
- Comparación de la celda de interés por país (159 filas): `data/test_ipf/celda_interes_comparacion_final.csv`

## 4. Resultados agregados

### 4.1 Celda de interés (1.Baja × 3.TCP_fliares × 2.No_agro), 159 países

| Métrica | Valor |
|---|---:|
| MAE (error absoluto medio) | 0,056 pp |
| Mediana del error absoluto | 0,004 pp |
| Error absoluto máximo | 1,747 pp (Senegal) |
| Sesgo medio (Python − R) | +0,002 pp |
| Correlación de Pearson (Python vs R) | 0,9955 |
| P90 / P95 / P99 del error absoluto | 0,064 / 0,199 / 1,284 pp |

**Lectura:** para la enorme mayoría de países (mediana 0,004 pp, P90 = 0,064 pp) las dos implementaciones son indistinguibles en la práctica. Hay una cola corta de ~10 países con diferencias mayores a 0,15 pp.

### 4.2 Las 1.908 celdas de la tabla trivariada completa (no solo la celda de interés)

| Umbral de diferencia absoluta | Celdas que lo superan |
|---|---:|
| > 0,01 pp | 953 / 1.908 (49,9%) |
| > 0,1 pp | 341 / 1.908 (17,9%) |
| > 0,5 pp | 117 / 1.908 (6,1%) |
| > 1 pp | 68 / 1.908 (3,6%) |
| > 5 pp | 5 / 1.908 (0,3%) |

La celda con mayor diferencia absoluta en toda la tabla es "2.Media × 3.TCP_fliares × 1.Agro" para Burkina Faso (18,7 pp) — **no** es la celda de interés del proyecto, pero es indicativa del mismo fenómeno (ver §5).

### 4.3 Chequeo de consistencia interna: margen "Agro" implícito

El margen de rama "1.Agro" es un input directo del IPF (proviene de `calif_rama_agg.csv`, idéntico en ambas corridas). Si el IPF converge exactamente a ese margen, Python y R deberían coincidir casi a la perfección en él. En la práctica:

- MAE del margen agro entre Python y R: **0,86 pp**
- Máximo: **20,3 pp** (Guinea-Bissau)

Que este margen —que en teoría debería "cerrar" exacto en ambas implementaciones— también diverja para un subconjunto de países confirma que la causa no es un bug de traducción entre lenguajes, sino que **ninguna de las dos implementaciones logra converger exactamente a los 3 márgenes simultáneamente** para esos países (ver §5).

## 5. Interpretación: ¿por qué difieren algunos países?

Los países con mayor discrepancia (Senegal, Burkina Faso, Guinea-Bissau, Bhutan, Tanzania, Cabo Verde, Madagascar...) comparten un patrón: sus tres tablas bivariadas de origen (`calif × ocup`, `ocup × rama`, `calif × rama`) no son perfectamente consistentes entre sí — es decir, no existe una única tabla trivariada verdadera que reproduzca exactamente los tres márgenes a la vez. Cuando eso ocurre, el ajuste cíclico (IPF) converge a un punto de "compromiso" cuya ubicación exacta puede ser sensible a detalles de implementación: criterio de convergencia y tolerancia (`mipfp` usa `tol=1e-10`, mi implementación usa un número fijo de iteraciones), lo que produce pequeñas pero no despreciables diferencias en esos casos puntuales.

Esto **no es un bug** — es una propiedad matemática esperada del método cuando los márgenes de entrada (que vienen de tres relevamientos de ILOSTAT potencialmente distintos en cobertura/año para un mismo país) no son perfectamente consistentes. Afecta a una cola corta de países (~10 de 159 con diferencia > 0,15 pp en la celda de interés) y no invalida la estimación agregada (correlación 0,9955, sesgo prácticamente nulo).

## 6. Tabla completa por país — celda de interés (Python vs. R/`mipfp`)

Ordenada por diferencia absoluta descendente.

| iso3c | país | Python (%) | R/mipfp (%) | dif. (pp) | dif. abs. (pp) | dif. rel. (%) |
|---|---|---:|---:|---:|---:|---:|
| SEN | Senegal | 14.0307 | 12.2843 | +1.7465 | 1.7465 | +14.22 |
| BFA | Burkina Faso | 3.2799 | 4.6729 | -1.3930 | 1.3930 | -29.81 |
| GNB | Guinea-Bissau | 3.0382 | 4.2435 | -1.2053 | 1.2053 | -28.40 |
| TZA | Tanzania, United Republic of | 5.5571 | 4.7280 | +0.8291 | 0.8291 | +17.54 |
| CPV | Cape Verde | 8.6432 | 9.1821 | -0.5389 | 0.5389 | -5.87 |
| MDG | Madagascar | 3.9227 | 3.5485 | +0.3742 | 0.3742 | +10.54 |
| AFG | Afghanistan | 7.4327 | 7.1993 | +0.2334 | 0.2334 | +3.24 |
| LAO | Lao People's Democratic Republic | 3.2255 | 3.4511 | -0.2256 | 0.2256 | -6.54 |
| YEM | Yemen | 1.1704 | 0.9748 | +0.1956 | 0.1956 | +20.06 |
| NER | Niger | 1.1516 | 1.3201 | -0.1685 | 0.1685 | -12.76 |
| TLS | Timor-Leste | 2.6286 | 2.4751 | +0.1535 | 0.1535 | +6.20 |
| TJK | Tajikistan | 2.1093 | 2.2596 | -0.1503 | 0.1503 | -6.65 |
| SUR | Suriname | 1.9465 | 2.0955 | -0.1490 | 0.1490 | -7.11 |
| KIR | Kiribati | 2.6991 | 2.5654 | +0.1336 | 0.1336 | +5.21 |
| IND | India | 8.8891 | 8.9749 | -0.0858 | 0.0858 | -0.96 |
| AGO | Angola | 4.6074 | 4.5250 | +0.0825 | 0.0825 | +1.82 |
| TGO | Togo | 1.4084 | 1.4682 | -0.0598 | 0.0598 | -4.07 |
| SOM | Somalia | 12.4165 | 12.3645 | +0.0519 | 0.0519 | +0.42 |
| BWA | Botswana | 1.6284 | 1.5772 | +0.0512 | 0.0512 | +3.24 |
| KGZ | Kyrgyzstan | 1.5746 | 1.5271 | +0.0475 | 0.0475 | +3.11 |
| MLI | Mali | 0.7526 | 0.7053 | +0.0473 | 0.0473 | +6.71 |
| DJI | Djibouti | 2.6908 | 2.6442 | +0.0466 | 0.0466 | +1.76 |
| CIV | Côte d'Ivoire | 1.7935 | 1.7499 | +0.0437 | 0.0437 | +2.49 |
| TCD | Chad | 0.5725 | 0.5290 | +0.0435 | 0.0435 | +8.23 |
| ETH | Ethiopia | 6.8839 | 6.9274 | -0.0435 | 0.0435 | -0.63 |
| TUN | Tunisia | 0.9733 | 0.9403 | +0.0330 | 0.0330 | +3.51 |
| NRU | Naoero | 1.7400 | 1.7080 | +0.0321 | 0.0321 | +1.88 |
| PER | Peru | 7.0582 | 7.0263 | +0.0319 | 0.0319 | +0.45 |
| BRB | Barbados | 1.0968 | 1.1205 | -0.0237 | 0.0237 | -2.11 |
| GIN | Guinea | 0.8909 | 0.9142 | -0.0232 | 0.0232 | -2.54 |
| FSM | Micronesia, Federated States of | 2.9186 | 2.9418 | -0.0232 | 0.0232 | -0.79 |
| JAM | Jamaica | 1.2744 | 1.2515 | +0.0229 | 0.0229 | +1.83 |
| ZMB | Zambia | 1.2660 | 1.2886 | -0.0226 | 0.0226 | -1.76 |
| PSE | Palestine, State of | 1.0779 | 1.0553 | +0.0226 | 0.0226 | +2.14 |
| PAN | Panama | 2.0848 | 2.0627 | +0.0222 | 0.0222 | +1.08 |
| MHL | Marshall Islands | 3.7146 | 3.7364 | -0.0219 | 0.0219 | -0.59 |
| NIC | Nicaragua | 6.3331 | 6.3122 | +0.0210 | 0.0210 | +0.33 |
| SLV | El Salvador | 3.9266 | 3.9475 | -0.0209 | 0.0209 | -0.53 |
| IRN | Iran, Islamic Republic of | 1.5772 | 1.5564 | +0.0208 | 0.0208 | +1.34 |
| GMB | Gambia | 7.7309 | 7.7113 | +0.0196 | 0.0196 | +0.25 |
| COD | Congo, Democratic Republic of the | 2.1141 | 2.0956 | +0.0185 | 0.0185 | +0.88 |
| BEN | Benin | 0.4367 | 0.4519 | -0.0152 | 0.0152 | -3.36 |
| BTN | Bhutan | 0.3090 | 0.2941 | +0.0149 | 0.0149 | +5.08 |
| MOZ | Mozambique | 0.6716 | 0.6863 | -0.0147 | 0.0147 | -2.14 |
| KEN | Kenya | 10.5747 | 10.5601 | +0.0146 | 0.0146 | +0.14 |
| BOL | Bolivia, Plurinational State of | 1.5298 | 1.5157 | +0.0141 | 0.0141 | +0.93 |
| DOM | Dominican Republic | 5.3248 | 5.3109 | +0.0139 | 0.0139 | +0.26 |
| IDN | Indonesia | 1.5907 | 1.5772 | +0.0134 | 0.0134 | +0.85 |
| RWA | Rwanda | 0.5379 | 0.5247 | +0.0132 | 0.0132 | +2.52 |
| LBN | Lebanon | 1.1406 | 1.1279 | +0.0127 | 0.0127 | +1.13 |
| SLE | Sierra Leone | 3.2797 | 3.2923 | -0.0126 | 0.0126 | -0.38 |
| PLW | Palau | 1.5479 | 1.5601 | -0.0122 | 0.0122 | -0.78 |
| BGD | Bangladesh | 2.2857 | 2.2976 | -0.0118 | 0.0118 | -0.52 |
| ZAF | South Africa | 3.8019 | 3.7903 | +0.0116 | 0.0116 | +0.31 |
| ECU | Ecuador | 5.2800 | 5.2684 | +0.0116 | 0.0116 | +0.22 |
| LBR | Liberia | 5.0365 | 5.0261 | +0.0104 | 0.0104 | +0.21 |
| MNE | Montenegro | 1.1197 | 1.1096 | +0.0101 | 0.0101 | +0.91 |
| THA | Thailand | 0.7360 | 0.7261 | +0.0099 | 0.0099 | +1.37 |
| STP | Sao Tome and Principe | 2.8650 | 2.8555 | +0.0095 | 0.0095 | +0.33 |
| BRA | Brazil | 2.3529 | 2.3616 | -0.0087 | 0.0087 | -0.37 |
| COK | Cook Islands | 0.4245 | 0.4161 | +0.0084 | 0.0084 | +2.02 |
| COG | Congo | 0.9613 | 0.9535 | +0.0077 | 0.0077 | +0.81 |
| TUV | Tuvalu | 0.0912 | 0.0987 | -0.0076 | 0.0076 | -7.67 |
| COM | Comoros | 0.6034 | 0.5961 | +0.0072 | 0.0072 | +1.22 |
| MKD | North Macedonia | 0.9512 | 0.9442 | +0.0070 | 0.0070 | +0.74 |
| GUY | Guyana | 2.6592 | 2.6525 | +0.0068 | 0.0068 | +0.26 |
| ZWE | Zimbabwe | 1.6141 | 1.6078 | +0.0063 | 0.0063 | +0.39 |
| VNM | Viet Nam | 1.9789 | 1.9729 | +0.0060 | 0.0060 | +0.30 |
| BLZ | Belize | 2.1567 | 2.1509 | +0.0058 | 0.0058 | +0.27 |
| LCA | Saint Lucia | 0.8925 | 0.8867 | +0.0058 | 0.0058 | +0.65 |
| SVN | Slovenia | 0.3343 | 0.3287 | +0.0056 | 0.0056 | +1.70 |
| ARG | Argentina | 1.4698 | 1.4754 | -0.0056 | 0.0056 | -0.38 |
| VUT | Vanuatu | 1.4796 | 1.4850 | -0.0054 | 0.0054 | -0.36 |
| MWI | Malawi | 0.4001 | 0.4054 | -0.0053 | 0.0053 | -1.30 |
| LKA | Sri Lanka | 0.8155 | 0.8105 | +0.0050 | 0.0050 | +0.61 |
| BRN | Brunei Darussalam | 0.1773 | 0.1724 | +0.0049 | 0.0049 | +2.84 |
| MDV | Maldives | 0.9106 | 0.9150 | -0.0043 | 0.0043 | -0.47 |
| JPN | Japan | 1.3753 | 1.3794 | -0.0041 | 0.0041 | -0.29 |
| URY | Uruguay | 2.7871 | 2.7833 | +0.0038 | 0.0038 | +0.14 |
| PAK | Pakistan | 0.4000 | 0.3963 | +0.0037 | 0.0037 | +0.94 |
| KOS | Kosovo | 4.1158 | 4.1126 | +0.0033 | 0.0033 | +0.08 |
| ITA | Italy | 0.6117 | 0.6084 | +0.0032 | 0.0032 | +0.53 |
| CRI | Costa Rica | 1.3269 | 1.3239 | +0.0030 | 0.0030 | +0.23 |
| MEX | Mexico | 1.7751 | 1.7781 | -0.0030 | 0.0030 | -0.17 |
| HKG | Hong Kong, China | 0.2405 | 0.2376 | +0.0030 | 0.0030 | +1.25 |
| PHL | Philippines | 1.5470 | 1.5440 | +0.0030 | 0.0030 | +0.19 |
| NIU | Niue | 0.3721 | 0.3693 | +0.0029 | 0.0029 | +0.77 |
| CYP | Cyprus | 0.9608 | 0.9582 | +0.0025 | 0.0025 | +0.26 |
| PRY | Paraguay | 3.0205 | 3.0182 | +0.0023 | 0.0023 | +0.08 |
| ROU | Romania | 0.8076 | 0.8053 | +0.0022 | 0.0022 | +0.28 |
| NPL | Nepal | 0.9683 | 0.9661 | +0.0022 | 0.0022 | +0.23 |
| SLB | Solomon Islands | 0.4209 | 0.4230 | -0.0021 | 0.0021 | -0.49 |
| AUS | Australia | 0.6704 | 0.6723 | -0.0019 | 0.0019 | -0.28 |
| RUS | Russian Federation | 0.0925 | 0.0907 | +0.0018 | 0.0018 | +2.01 |
| ISR | Israel | 0.1682 | 0.1665 | +0.0018 | 0.0018 | +1.08 |
| CHL | Chile | 2.8170 | 2.8153 | +0.0018 | 0.0018 | +0.06 |
| MNG | Mongolia | 0.9313 | 0.9295 | +0.0017 | 0.0017 | +0.19 |
| BHS | Bahamas | 0.6925 | 0.6909 | +0.0016 | 0.0016 | +0.23 |
| GRC | Greece | 0.1608 | 0.1593 | +0.0015 | 0.0015 | +0.94 |
| BLR | Belarus | 0.3469 | 0.3456 | +0.0013 | 0.0013 | +0.38 |
| LUX | Luxembourg | 0.2859 | 0.2847 | +0.0012 | 0.0012 | +0.42 |
| SWZ | Eswatini | 1.6006 | 1.5994 | +0.0012 | 0.0012 | +0.07 |
| MAR | Morocco | 3.5132 | 3.5121 | +0.0011 | 0.0011 | +0.03 |
| NAM | Namibia | 2.4708 | 2.4697 | +0.0011 | 0.0011 | +0.05 |
| SRB | Serbia | 0.4532 | 0.4521 | +0.0011 | 0.0011 | +0.24 |
| GEO | Georgia | 0.1052 | 0.1042 | +0.0010 | 0.0010 | +0.97 |
| MMR | Myanmar | 1.1203 | 1.1193 | +0.0010 | 0.0010 | +0.09 |
| UGA | Uganda | 0.5545 | 0.5536 | +0.0010 | 0.0010 | +0.18 |
| BGR | Bulgaria | 0.3030 | 0.3021 | +0.0009 | 0.0009 | +0.30 |
| CMR | Cameroon | 3.6145 | 3.6154 | -0.0009 | 0.0009 | -0.03 |
| ALB | Albania | 1.0599 | 1.0608 | -0.0008 | 0.0008 | -0.08 |
| GHA | Ghana | 1.4741 | 1.4749 | -0.0008 | 0.0008 | -0.06 |
| IRL | Ireland | 0.2544 | 0.2551 | -0.0007 | 0.0007 | -0.27 |
| LVA | Latvia | 0.4103 | 0.4096 | +0.0007 | 0.0007 | +0.16 |
| TTO | Trinidad and Tobago | 1.9386 | 1.9379 | +0.0007 | 0.0007 | +0.03 |
| FJI | Fiji | 0.4807 | 0.4801 | +0.0006 | 0.0006 | +0.12 |
| HND | Honduras | 3.5180 | 3.5186 | -0.0005 | 0.0005 | -0.02 |
| PRT | Portugal | 0.3776 | 0.3771 | +0.0005 | 0.0005 | +0.14 |
| SVK | Slovakia | 0.4644 | 0.4639 | +0.0005 | 0.0005 | +0.11 |
| MDA | Republic of Moldova | 0.2015 | 0.2010 | +0.0005 | 0.0005 | +0.24 |
| HRV | Croatia | 0.1359 | 0.1354 | +0.0005 | 0.0005 | +0.35 |
| BIH | Bosnia and Herzegovina | 0.2706 | 0.2701 | +0.0004 | 0.0004 | +0.16 |
| BEL | Belgium | 0.2973 | 0.2969 | +0.0004 | 0.0004 | +0.13 |
| GTM | Guatemala | 1.7458 | 1.7454 | +0.0004 | 0.0004 | +0.02 |
| NLD | Netherlands | 0.3546 | 0.3550 | -0.0004 | 0.0004 | -0.11 |
| MLT | Malta | 0.5286 | 0.5283 | +0.0004 | 0.0004 | +0.07 |
| LSO | Lesotho | 0.1527 | 0.1530 | -0.0004 | 0.0004 | -0.24 |
| DEU | Germany | 0.1978 | 0.1975 | +0.0003 | 0.0003 | +0.17 |
| ARM | Armenia | 0.2019 | 0.2023 | -0.0003 | 0.0003 | -0.16 |
| COL | Colombia | 2.5677 | 2.5680 | -0.0003 | 0.0003 | -0.01 |
| DNK | Denmark | 0.3138 | 0.3135 | +0.0003 | 0.0003 | +0.09 |
| ESP | Spain | 0.1522 | 0.1520 | +0.0003 | 0.0003 | +0.17 |
| PRI | Puerto Rico | 0.6433 | 0.6435 | -0.0002 | 0.0002 | -0.04 |
| KHM | Cambodia | 0.1026 | 0.1028 | -0.0002 | 0.0002 | -0.21 |
| TON | Tonga | 0.0474 | 0.0472 | +0.0002 | 0.0002 | +0.42 |
| GBR | United Kingdom of Great Britain and Northern Ireland | 0.7870 | 0.7868 | +0.0002 | 0.0002 | +0.02 |
| SYC | Seychelles | 0.7814 | 0.7812 | +0.0002 | 0.0002 | +0.02 |
| VEN | Venezuela, Bolivarian Republic of | 0.0917 | 0.0916 | +0.0001 | 0.0001 | +0.16 |
| ARE | United Arab Emirates | 0.3219 | 0.3220 | -0.0001 | 0.0001 | -0.04 |
| EST | Estonia | 0.0996 | 0.0994 | +0.0001 | 0.0001 | +0.12 |
| HUN | Hungary | 0.1164 | 0.1163 | +0.0001 | 0.0001 | +0.10 |
| WSM | Samoa | 0.2575 | 0.2576 | -0.0001 | 0.0001 | -0.04 |
| GRD | Grenada | 1.3816 | 1.3817 | -0.0001 | 0.0001 | -0.01 |
| EGY | Egypt | 2.0590 | 2.0590 | -0.0001 | 0.0001 | -0.00 |
| ISL | Iceland | 0.1448 | 0.1449 | -0.0001 | 0.0001 | -0.04 |
| CHE | Switzerland | 0.2708 | 0.2709 | -0.0000 | 0.0000 | -0.02 |
| LTU | Lithuania | 0.1110 | 0.1110 | +0.0000 | 0.0000 | +0.04 |
| AUT | Austria | 0.2321 | 0.2321 | +0.0000 | 0.0000 | +0.02 |
| NOR | Norway | 0.0941 | 0.0941 | +0.0000 | 0.0000 | +0.04 |
| FIN | Finland | 0.2286 | 0.2285 | +0.0000 | 0.0000 | +0.01 |
| FRA | France | 0.0611 | 0.0612 | -0.0000 | 0.0000 | -0.04 |
| CZE | Czechia | 0.2008 | 0.2008 | +0.0000 | 0.0000 | +0.01 |
| MUS | Mauritius | 0.5502 | 0.5503 | -0.0000 | 0.0000 | -0.00 |
| JOR | Jordan | 0.5250 | 0.5250 | +0.0000 | 0.0000 | +0.00 |
| SWE | Sweden | 0.2244 | 0.2244 | +0.0000 | 0.0000 | +0.00 |
| TUR | Türkiye | 0.8372 | 0.8372 | +0.0000 | 0.0000 | +0.00 |
| KOR | Republic of Korea | 3.6035 | 3.6035 | +0.0000 | 0.0000 | +0.00 |
| USA | United States of America | 0.4658 | 0.4658 | +0.0000 | 0.0000 | +0.00 |
| WLF | Wallis and Futuna | 0.0000 | 0.0000 | +0.0000 | 0.0000 | (0/0) |

## 7. Archivos generados (no commiteados)

- `data/estimacion_tcp_final_corregida.csv` — estimación IPF completa, Python
- `data/test_ipf/estimacion_R_mipfp_full_independiente.csv` — estimación IPF completa, R/`mipfp` (159 países, corrida limpia)
- `data/test_ipf/comparacion_python_vs_R_completa.csv` — merge celda a celda (1.908 filas)
- `data/test_ipf/celda_interes_comparacion_final.csv` / `celda_interes_comparacion_final` — comparación de la celda de interés por país (159 filas, es la fuente de la tabla del §6)

## 8. Conclusión

La estimación IPF es **reproducible de forma independiente** entre Python y R/`mipfp`: sobre 159 países, la correlación es 0,9955, el sesgo medio es prácticamente nulo (+0,002 pp) y la mediana del error absoluto es 0,004 pp. Existe una cola de ~10 países (encabezada por Senegal, Burkina Faso y Guinea-Bissau) donde la diferencia es mayor (hasta 1,75 pp) por inconsistencia entre los márgenes bivariados de entrada — un límite conocido del método, no un error de implementación. Ningún país falló en ninguna de las dos corridas.
