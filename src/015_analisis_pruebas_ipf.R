#!/usr/bin/env Rscript
# 015_analisis_pruebas_ipf.R
#
# Puerto en R/tidyverse de src/015_analisis_pruebas_ipf.py: análisis de las dos
# pruebas de validación de la estimación IPF de trabajadores por cuenta propia
# y familiares (TCP/TF) de baja calificación no agrícolas.
#
#   Prueba 1 (validez interna, método): EPH Argentina.
#       Insumo: data/eph_ipf_comparacion_agg_test.csv
#   Prueba 2 (validez externa, pipeline completo): muestras censales IPUMS
#       (47 países) vs estimación IPF sobre tablas OIT.
#       Insumos: data/ipums_ifp_v2_tcp_by_calif.csv
#                --estimacion (CSV largo iso3c,calificacion,ocupacion,rama,freq)
#                data/estimacion/tabla_tcps_final_sums.csv
#
# El mapeo país->iso3c usa data/outputs/country_classification.csv en vez de
# pycountry (no disponible en R): 45 de los 47 países de IPUMS matchean por
# nombre exacto; Iran y Palestine se recodifican a mano antes del join.
#
# Uso (correr con la raíz del repo como working directory, igual que 011-014/102/103):
#   Rscript src/015_analisis_pruebas_ipf.R --estimacion <csv> --sufijo <str>

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(tibble)
})
options(readr.show_col_types = FALSE)

# ----------------------------------------------------------------------
# Paleta y estilo (misma paleta que 015_analisis_pruebas_ipf.py)
# ----------------------------------------------------------------------
SURFACE  <- "#fcfcfb"
INK      <- "#0b0b0b"
INK2     <- "#52514e"
MUTED    <- "#898781"
GRID_COL <- "#e1e0d9"
BASELINE <- "#c3c2b7"
S1 <- "#2a78d6"   # azul -> estimación (IPF / raking)
S2 <- "#1baf7a"   # aqua -> observado (EPH / IPUMS)
S6 <- "#e34948"   # rojo -> modelo del bug / resaltado

theme_set(
  theme_minimal(base_size = 9) +
    theme(
      panel.background  = element_rect(fill = SURFACE, color = NA),
      plot.background   = element_rect(fill = SURFACE, color = NA),
      legend.background = element_rect(fill = SURFACE, color = NA),
      legend.key        = element_rect(fill = SURFACE, color = NA),
      panel.grid.major  = element_line(color = GRID_COL, linewidth = 0.3),
      panel.grid.minor  = element_blank(),
      axis.text   = element_text(color = MUTED),
      axis.title  = element_text(color = INK2),
      plot.title  = element_text(color = INK, size = 10),
      legend.text = element_text(color = INK2),
      strip.background = element_rect(fill = SURFACE, color = GRID_COL),
      strip.text  = element_text(color = INK2)
    )
)

# ----------------------------------------------------------------------
# Rutas (relativas a la raíz del repo, igual que el resto de src/*.R —
# correr con la raíz del repo como working directory)
# ----------------------------------------------------------------------
DATA  <- "./data"
OUT   <- "./data/test_ipf"
FIGS  <- "./reports/figs"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(trailingOnly = TRUE)
get_flag <- function(flag, default) {
  idx <- which(args == flag)
  if (length(idx) == 1 && idx < length(args)) return(args[idx + 1])
  default
}
ESTIMACION_PATH <- get_flag("--estimacion",
                             file.path(DATA, "estimacion", "20260824_estimacion_tcp_final_v2.csv"))
SUF <- get_flag("--sufijo", "")

insert_suffix <- function(name, suf) {
  ext  <- tools::file_ext(name)
  base <- tools::file_path_sans_ext(name)
  if (nzchar(ext)) paste0(base, suf, ".", ext) else paste0(base, suf)
}
O  <- function(name) file.path(OUT, insert_suffix(name, SUF))
Fp <- function(name) file.path(FIGS, insert_suffix(name, SUF))

KEY_CALIF <- "1.Baja"
KEY_OCUP  <- "3.TCP_fliares"
KEY_RAMA  <- "2.No_agro"
is_key <- function(calificacion, ocupacion, rama) {
  calificacion == KEY_CALIF & ocupacion == KEY_OCUP & rama == KEY_RAMA
}

# ========================================================================
# PRUEBA 1 -- EPH (Argentina)
# ========================================================================
cat(strrep("=", 70), "\n")
cat("PRUEBA 1 -- EPH-IPF (Argentina)\n")
cat(strrep("=", 70), "\n")

eph <- read_csv(file.path(DATA, "eph_ipf_comparacion_agg_test.csv")) %>%
  mutate(across(c(prop, prop_est, prop_wei, prop_est_wei), ~ .x * 100, .names = "{.col}_pp")) %>%
  mutate(err_pp = prop_est_pp - prop_pp,
         err_wei_pp = prop_est_wei_pp - prop_wei_pp)

print(
  eph %>%
    select(calif_agg, cat_ocup_agg, agro, n, prop_wei_pp, prop_est_wei_pp, err_wei_pp, error_porc_wei) %>%
    mutate(across(where(is.numeric), ~ round(.x, 4))),
  n = Inf
)

mae_eph     <- mean(abs(eph$err_wei_pp))
max_eph     <- max(abs(eph$err_wei_pp))
dissim_eph  <- 0.5 * sum(abs(eph$err_wei_pp))
pearson_eph <- cor(eph$prop_wei_pp, eph$prop_est_wei_pp)

cat(sprintf("\nMAE ponderado: %.4f pp | max |err|: %.4f pp\n", mae_eph, max_eph))
cat(sprintf("Índice de disimilitud (0.5*sum|dif|): %.3f pp\n", dissim_eph))
cat(sprintf("Pearson obs vs est (pond.): %.6f\n", pearson_eph))

e <- eph %>%
  mutate(celda = paste0(str_remove(calif_agg, "_calif"), " x ", cat_ocup_agg, " x ", agro)) %>%
  arrange(prop_wei_pp) %>%
  mutate(celda = factor(celda, levels = celda))

e_pts <- bind_rows(
  e %>% transmute(celda, valor = prop_wei_pp, fuente = "EPH observado"),
  e %>% transmute(celda, valor = prop_est_wei_pp, fuente = "IPF estimado")
)

fig1 <- ggplot() +
  geom_segment(data = e, aes(x = prop_wei_pp, xend = prop_est_wei_pp, y = celda, yend = celda),
               color = BASELINE, linewidth = 0.6) +
  geom_point(data = e_pts, aes(x = valor, y = celda, color = fuente, shape = fuente),
             size = 2.4, stroke = 1.1) +
  scale_color_manual(values = c("EPH observado" = S2, "IPF estimado" = S1)) +
  scale_shape_manual(values = c("EPH observado" = 16, "IPF estimado" = 1)) +
  scale_x_log10() +
  labs(x = "% del empleo total (escala log)", y = NULL, color = NULL, shape = NULL,
       title = "Prueba EPH (Argentina): distribución conjunta observada vs. estimada por IPF") +
  theme(axis.text.y = element_text(size = 8, color = INK2), legend.position = "bottom")
ggsave(Fp("fig1_eph_obs_vs_ipf.png"), fig1, width = 7.2, height = 4.2, dpi = 160, bg = SURFACE)

# ========================================================================
# PRUEBA 2 -- IPUMS vs raking OIT-IPF
# ========================================================================
cat("\n", strrep("=", 70), "\n", sep = "")
cat("PRUEBA 2 -- IPUMS-IPF (validez externa, 47 países)\n")
cat(strrep("=", 70), "\n")

ip <- read_csv(file.path(DATA, "ipums_ifp_v2_tcp_by_calif.csv"))
country_class <- read_csv(file.path(DATA, "outputs", "country_classification.csv"))

ip <- ip %>%
  mutate(country_join = case_match(COUNTRY_lab,
                                    "Iran" ~ "Iran, Islamic Rep.",
                                    "Palestine" ~ "West Bank and Gaza",
                                    .default = COUNTRY_lab)) %>%
  left_join(country_class %>% select(iso3c, country), by = c("country_join" = "country"))

stopifnot("países IPUMS sin iso3c" = all(!is.na(ip$iso3c)))

ip <- ip %>%
  mutate(
    ocupacion = if_else(cat_ocup %in% c("Own account worker", "Unpaid worker"),
                         "3.TCP_fliares", "1.Asalariado_patr"),
    rama = if_else(rama_agg == "Agro", "1.Agro", "2.No_agro"),
    calificacion = case_match(skill_level,
                               "Level 1" ~ "1.Baja",
                               "Level 2" ~ "2.Media",
                               "Level 3-4" ~ "3.Alta")
  )

ipa <- ip %>%
  group_by(iso3c, calificacion, ocupacion, rama) %>%
  summarise(n_raw = sum(n_raw), n_wei = sum(n_wei), .groups = "drop") %>%
  group_by(iso3c) %>%
  mutate(ipums_porc = 100 * n_wei / sum(n_wei)) %>%
  ungroup()

rk <- read_csv(ESTIMACION_PATH) %>%
  mutate(calificacion = if_else(calificacion == "3-Alta", "3.Alta", calificacion)) %>%
  rename(raking_porc = freq)

comp <- inner_join(
    rk,
    ipa %>% select(iso3c, calificacion, ocupacion, rama, ipums_porc, n_raw),
    by = c("iso3c", "calificacion", "ocupacion", "rama")
  ) %>%
  mutate(diff = raking_porc - ipums_porc)

tf <- read_csv(file.path(DATA, "estimacion", "tabla_tcps_final_sums.csv")) %>%
  distinct(iso3c, .keep_all = TRUE)

comp <- comp %>%
  left_join(tf %>% select(iso3c, region, income_group_2, cluster_pimsa, prop_tcp_fliares_no_agro),
            by = "iso3c")

faltantes <- setdiff(unique(ipa$iso3c), unique(rk$iso3c))
cat(sprintf("Países IPUMS: %d | con estimación raking: %d (falta: %s)\n",
            n_distinct(ipa$iso3c), n_distinct(comp$iso3c), paste(sort(faltantes), collapse = ", ")))
cat(sprintf("Celdas comparadas: %d\n", nrow(comp)))
cat(sprintf("Global  Pearson %.3f | Spearman %.3f | MAE %.2f pp | mediana |dif| %.2f pp\n",
            cor(comp$raking_porc, comp$ipums_porc),
            cor(comp$raking_porc, comp$ipums_porc, method = "spearman"),
            mean(abs(comp$diff)), median(abs(comp$diff))))

met <- comp %>%
  group_by(rama, ocupacion, calificacion) %>%
  summarise(
    n_paises = n(),
    pearson = cor(raking_porc, ipums_porc),
    spearman = cor(raking_porc, ipums_porc, method = "spearman"),
    MAE_pp = mean(abs(diff)),
    bias_pp = mean(diff),
    media_ipums = mean(ipums_porc),
    media_raking = mean(raking_porc),
    .groups = "drop"
  ) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))

cat("\nMétricas por celda:\n")
print(met, n = Inf)
write_csv(met, O("metricas_por_celda.csv"))
write_csv(comp, O("comp_raking_ipums_full.csv"))

key <- comp %>%
  filter(is_key(calificacion, ocupacion, rama)) %>%
  mutate(rank_ipums = rank(ipums_porc), rank_raking = rank(raking_porc)) %>%
  arrange(diff)
write_csv(key, O("celda_clave_paises.csv"))

cat(sprintf("\nCelda clave (TCP_fliares x No_agro x Baja): n=%d\n", nrow(key)))
cat(sprintf("Pearson %.3f | Spearman %.3f | MAE %.2f pp | bias %.2f pp\n",
            cor(key$raking_porc, key$ipums_porc),
            cor(key$raking_porc, key$ipums_porc, method = "spearman"),
            mean(abs(key$diff)), mean(key$diff)))

# --- Figura 2: scatter por celda (12 paneles) ---
rama_order  <- c("1.Agro", "2.No_agro")
ocup_order  <- c("1.Asalariado_patr", "3.TCP_fliares")
calif_order <- c("1.Baja", "2.Media", "3.Alta")
# Orden rama -> ocupacion -> calificacion (igual que el `order` de la versión Python).
panel_levels <- character(0)
for (r in rama_order) for (o in ocup_order) for (c in calif_order) {
  panel_levels <- c(panel_levels, paste(r, o, c, sep = " x "))
}

comp <- comp %>% mutate(panel = factor(paste(rama, ocupacion, calificacion, sep = " x "),
                                        levels = panel_levels))
met_panel <- met %>%
  mutate(panel = factor(paste(rama, ocupacion, calificacion, sep = " x "), levels = panel_levels),
         label = sprintf("ρ=%.2f", spearman))

key_panel <- paste(KEY_RAMA, KEY_OCUP, KEY_CALIF, sep = " x ")
highlight_df <- tibble(panel = factor(key_panel, levels = panel_levels))

fig2 <- ggplot(comp, aes(x = ipums_porc, y = raking_porc)) +
  geom_abline(slope = 1, intercept = 0, color = BASELINE, linewidth = 0.5) +
  geom_point(color = S1, alpha = 0.75, size = 1.3) +
  geom_text(data = met_panel, aes(x = -Inf, y = Inf, label = label),
            hjust = -0.15, vjust = 1.4, size = 2.8, color = INK2, inherit.aes = FALSE) +
  geom_rect(data = highlight_df, aes(xmin = -Inf, xmax = Inf, ymin = -Inf, ymax = Inf),
            fill = NA, color = S6, linewidth = 1.2, inherit.aes = FALSE) +
  facet_wrap(~panel, nrow = 3, scales = "free") +
  labs(x = "IPUMS (censo, % del empleo)", y = "OIT-IPF (raking, % del empleo)",
       title = "Prueba IPUMS: estimación OIT-IPF vs. censo, por celda de la trivariada",
       subtitle = "46 países; recuadro rojo = celda de interés") +
  theme(strip.text = element_text(size = 7))
ggsave(Fp("fig2_ipums_scatter_celdas.png"), fig2, width = 10.5, height = 7.6, dpi = 160, bg = SURFACE)

# --- Figura 3: celda clave, scatter con etiquetas de país ---
fig3 <- ggplot(key, aes(x = ipums_porc, y = raking_porc)) +
  geom_abline(slope = 1, intercept = 0, color = BASELINE) +
  geom_point(color = S1, size = 2) +
  geom_text(aes(label = iso3c), color = INK2, size = 2.5, hjust = -0.2, vjust = 0) +
  labs(x = "IPUMS (censo): TCP/TF baja calif. no agro, % del empleo",
       y = "OIT-IPF (raking), % del empleo",
       title = sprintf("Celda de interés por país (ρ Spearman = %.2f; recta = identidad)",
                        cor(key$raking_porc, key$ipums_porc, method = "spearman")))
ggsave(Fp("fig3_celda_clave_scatter.png"), fig3, width = 6.6, height = 6, dpi = 160, bg = SURFACE)

# ========================================================================
# SELF-TEST IPF sobre IPUMS: error atribuible sólo al supuesto del método
# ========================================================================
cat("\n", strrep("=", 70), "\n", sep = "")
cat("SELF-TEST IPF sobre trivariadas IPUMS\n")
cat(strrep("=", 70), "\n")

CAL <- c("1.Baja", "2.Media", "3.Alta")
OCU <- c("1.Asalariado_patr", "3.TCP_fliares")
RAM <- c("1.Agro", "2.No_agro")

ipf3 <- function(joint, iters = 2000, tol = 1e-12) {
  t12 <- apply(joint, c(1, 2), sum)
  t13 <- apply(joint, c(1, 3), sum)
  t23 <- apply(joint, c(2, 3), sum)
  x <- array(sum(joint) / length(joint), dim = dim(joint))
  for (it in seq_len(iters)) {
    m <- apply(x, c(1, 2), sum)
    x <- sweep(x, c(1, 2), ifelse(m > 0, t12 / ifelse(m == 0, 1, m), 0), `*`)
    m <- apply(x, c(1, 3), sum)
    x <- sweep(x, c(1, 3), ifelse(m > 0, t13 / ifelse(m == 0, 1, m), 0), `*`)
    m <- apply(x, c(2, 3), sum)
    x <- sweep(x, c(2, 3), ifelse(m > 0, t23 / ifelse(m == 0, 1, m), 0), `*`)
    if (max(abs(apply(x, c(1, 2), sum) - t12)) < tol) break
  }
  dimnames(x) <- dimnames(joint)
  x
}

build_array <- function(d) {
  J <- array(0, dim = c(3, 2, 2), dimnames = list(CAL, OCU, RAM))
  for (i in seq_len(nrow(d))) {
    J[d$calificacion[i], d$ocupacion[i], d$rama[i]] <- d$ipums_porc[i]
  }
  J
}

run_selftest_country <- function(iso, d) {
  J <- build_array(d)
  est <- ipf3(J)
  out <- expand.grid(calificacion = CAL, ocupacion = OCU, rama = RAM, stringsAsFactors = FALSE)
  out$iso3c <- iso
  out$ipums_true <- J[cbind(out$calificacion, out$ocupacion, out$rama)]
  out$ipf_self <- est[cbind(out$calificacion, out$ocupacion, out$rama)]
  out %>% select(iso3c, calificacion, ocupacion, rama, ipums_true, ipf_self)
}

st <- map_dfr(split(comp, comp$iso3c), ~ run_selftest_country(unique(.x$iso3c), .x)) %>%
  mutate(err = ipf_self - ipums_true)
write_csv(st, O("selftest_ipf_ipums.csv"))

kst <- st %>% filter(is_key(calificacion, ocupacion, rama))
cat(sprintf("MAE global: %.3f pp | p90 |err|: %.3f pp | max: %.3f pp\n",
            mean(abs(st$err)), quantile(abs(st$err), 0.9, names = FALSE), max(abs(st$err))))
cat(sprintf("Celda clave: MAE %.3f pp | bias %.3f pp | Spearman %.3f\n",
            mean(abs(kst$err)), mean(kst$err), cor(kst$ipums_true, kst$ipf_self, method = "spearman")))

# --- Figura 4: ECDF de |error| en la celda clave, método vs pipeline ---
ecdf_df <- bind_rows(
  tibble(err_abs = abs(kst$err), fuente = "Sólo supuesto IPF (self-test IPUMS)"),
  tibble(err_abs = abs(key$diff), fuente = "Pipeline completo OIT-IPF vs. IPUMS")
)
fig4 <- ggplot(ecdf_df, aes(x = err_abs, color = fuente)) +
  stat_ecdf(geom = "step", linewidth = 1) +
  scale_color_manual(values = c("Sólo supuesto IPF (self-test IPUMS)" = S1,
                                 "Pipeline completo OIT-IPF vs. IPUMS" = S2)) +
  ylim(0, 1.02) +
  labs(x = "|error| en la celda de interés (puntos porcentuales)",
       y = "Proporción acumulada de países", color = NULL,
       title = "Descomposición del error en la celda de interés (46 países)") +
  theme(legend.position = "bottom")
ggsave(Fp("fig4_ecdf_error_descomposicion.png"), fig4, width = 6.6, height = 4.2, dpi = 160, bg = SURFACE)

# ========================================================================
# MARGEN DE RAMA (agro) -- diagnóstico
# ========================================================================
cat("\n", strrep("=", 70), "\n", sep = "")
cat("MARGEN DE RAMA (agro) -- diagnóstico\n")
cat(strrep("=", 70), "\n")

marg <- comp %>%
  group_by(iso3c, rama) %>%
  summarise(raking_porc = sum(raking_porc), ipums_porc = sum(ipums_porc), .groups = "drop")
agro <- marg %>% filter(rama == "1.Agro") %>% mutate(diff_agro = raking_porc - ipums_porc)

cat(sprintf("Margen %%Agro raking-IPUMS: bias %.1f pp | MAE %.1f pp | r %.3f\n",
            mean(agro$diff_agro), mean(abs(agro$diff_agro)), cor(agro$raking_porc, agro$ipums_porc)))

# Curva del bug: si "No agro" se promedia entre las 5 categorías ECO del
# agregado ILOSTAT en lugar de sumarse, el margen agro observado en la
# estimación sería f(a) = a / (a + (100-a)/5).
a_grid <- seq(0.2, 95, length.out = 400)
curva_bug <- tibble(a_grid = a_grid, f_bug = 100 * a_grid / (a_grid + (100 - a_grid) / 5))
top8 <- agro %>% slice_max(diff_agro, n = 8)

fig5 <- ggplot() +
  geom_abline(slope = 1, intercept = 0, color = BASELINE) +
  geom_line(data = curva_bug, aes(x = a_grid, y = f_bug), color = S6, linewidth = 1) +
  geom_point(data = agro, aes(x = ipums_porc, y = raking_porc), color = S1, size = 2) +
  geom_text(data = top8, aes(x = ipums_porc, y = raking_porc, label = iso3c),
            color = INK2, size = 2.5, hjust = -0.15) +
  coord_cartesian(xlim = c(0, max(agro$ipums_porc) * 1.08), ylim = c(0, 92)) +
  labs(x = "% empleo agro según IPUMS (censo)",
       y = "% empleo agro implícito en la estimación OIT-IPF",
       title = "El margen de rama de la estimación sigue la curva del error de agregación")
ggsave(Fp("fig5_margen_agro_bug.png"), fig5, width = 6.6, height = 5, dpi = 160, bg = SURFACE)

# Margen TCP x No_agro: IPF vs. cálculo directo OIT (013) vs. IPUMS
m_ipf <- comp %>% filter(ocupacion == "3.TCP_fliares", rama == "2.No_agro") %>%
  group_by(iso3c) %>% summarise(ipf = sum(raking_porc), .groups = "drop")
m_oit <- tf %>% select(iso3c, oit_directo = prop_tcp_fliares_no_agro)
m_ipu <- comp %>% filter(ocupacion == "3.TCP_fliares", rama == "2.No_agro") %>%
  group_by(iso3c) %>% summarise(ipums = sum(ipums_porc), .groups = "drop")
m <- reduce(list(m_ipf, m_oit, m_ipu), full_join, by = "iso3c") %>% drop_na()

cat(sprintf("\nMargen TCP/TF x No_agro (n=%d):\n", nrow(m)))
cat(sprintf("  IPF vs IPUMS        : MAE %.2f pp | r %.3f | rho %.3f\n",
            mean(abs(m$ipf - m$ipums)), cor(m$ipf, m$ipums), cor(m$ipf, m$ipums, method = "spearman")))
cat(sprintf("  OIT-directo vs IPUMS: MAE %.2f pp | r %.3f | rho %.3f\n",
            mean(abs(m$oit_directo - m$ipums)), cor(m$oit_directo, m$ipums),
            cor(m$oit_directo, m$ipums, method = "spearman")))
write_csv(m %>% mutate(across(where(is.numeric), ~ round(.x, 3))), O("margen_tcp_noagro_3fuentes.csv"))

cat("\nListo. Salidas en data/test_ipf/ y reports/figs/\n")
