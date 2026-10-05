#!/usr/bin/env Rscript
# 019_distribuciones_apartado3.R
#
# Complementa 014 con la DISTRIBUCIÓN entre países de la celda de interés (TCP/TF de baja
# calificación no agraria, % del empleo) dentro de cada cluster PIMSA, grupo de ingreso y región.
# 014 sólo reporta medias ponderadas por empleo, que esconden (a) cuántos países hay en cada
# grupo, (b) la dispersión interna y (c) cuánto pesan los países grandes (India sola es el 57 %
# del peso de C4 y el 74 % del de South Asia). Acá se reportan, por grupo: n, media ponderada
# (la de 014), media simple, mediana, rango intercuartil, mínimo/máximo, país de mayor peso y la
# media ponderada sin ese país.
#
# También cruza la celda de interés con dos indicadores derivados de la trivariada estimada,
# para contrastar las lecturas teóricas del informe (peso de la agricultura en el empleo y
# absorción asalariada dentro del sector no agrario).
#
# Misma muestra que 014: países con todas las variables numéricas (drop_na(-c(region:cluster_pimsa))).
#
# Uso (raíz del repo como working directory):
#   LC_ALL=C.UTF-8 Rscript src/019_distribuciones_apartado3.R

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
})
options(readr.show_col_types = FALSE, width = 170)

OUT  <- "./data/estimacion"
FIGS <- "./reports/figs"
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

K <- "prop_tcp_fliares_no_agro_calif_baja"

tf <- read_csv(file.path(OUT, "tabla_tcps_final_sums.csv")) %>%
  drop_na(-c(region:cluster_pimsa))
est <- read_csv(file.path(OUT, "20260824_estimacion_tcp_final_v2.csv"))

# ----------------------------------------------------------------------
# Indicadores derivados de la trivariada (cada país suma 100 = empleo total)
# ----------------------------------------------------------------------
ind <- est %>% group_by(iso3c) %>% summarise(
  agro        = sum(freq[rama == "1.Agro"]),
  noagro      = sum(freq[rama == "2.No_agro"]),
  asal_noagro = sum(freq[rama == "2.No_agro" & ocupacion == "1.Asalariado_patr"]),
  tcp_noagro  = sum(freq[rama == "2.No_agro" & ocupacion == "3.TCP_fliares"]),
  .groups = "drop") %>%
  mutate(pct_asal_noagro = 100 * asal_noagro / noagro,
         pct_tcp_noagro  = 100 * tcp_noagro / noagro)

d <- tf %>% select(iso3c, country, region, income_group_2, cluster_pimsa, prop_ocup_totales,
                   celda = all_of(K)) %>%
  inner_join(ind, by = "iso3c") %>%
  mutate(w = prop_ocup_totales)
cat(sprintf("Países en la muestra: %d (de 181 filas; 22 no tienen la celda de interés y 4 más tienen otras variables en NA)\n", nrow(d)))

# ----------------------------------------------------------------------
# Tablas de distribución por grupo
# ----------------------------------------------------------------------
resumen <- function(g, etiqueta) {
  d %>% filter(!is.na(.data[[g]])) %>% group_by(grupo = .data[[g]]) %>% summarise(
    n = n(), peso_pct = sum(w),
    media_pond = weighted.mean(celda, w), media_simple = mean(celda), mediana = median(celda),
    p25 = quantile(celda, .25), p75 = quantile(celda, .75), minimo = min(celda), maximo = max(celda),
    pais_mayor_peso = iso3c[which.max(w)], peso_del_pais = max(w) / sum(w),
    media_pond_sin_pais = if (n() > 1) weighted.mean(celda[-which.max(w)], w[-which.max(w)]) else NA_real_,
    .groups = "drop") %>% mutate(dimension = etiqueta, .before = 1)
}
tab <- bind_rows(resumen("cluster_pimsa", "Cluster PIMSA"),
                 resumen("income_group_2", "Grupo de ingreso"),
                 resumen("region", "Región"))
write_csv(tab, file.path(OUT, "tcp_distribucion_celda_por_grupo.csv"))
cat("\n== Distribución de la celda de interés entre países, por grupo ==\n")
print(as.data.frame(tab %>% mutate(across(where(is.numeric), ~ round(.x, 2)))))

# ----------------------------------------------------------------------
# Gradientes entre países (Spearman) y comparación C1 vs. resto
# ----------------------------------------------------------------------
d <- d %>% mutate(cl = as.integer(substr(cluster_pimsa, 2, 2)), ing = as.integer(substr(income_group_2, 1, 2)))
cat("\n== Asociación entre países (Spearman) ==\n")
dc <- d %>% filter(!is.na(cl)); di <- d %>% filter(ing <= 4)
cat(sprintf("celda ~ cluster (C1..C5), n=%d: %.2f | sin C5 (C1..C4), n=%d: %.2f | celda ~ ingreso (1 alto..4 bajo), n=%d: %.2f\n",
            nrow(dc), cor(dc$celda, dc$cl, method = "spearman"),
            sum(dc$cl <= 4), cor(dc$celda[dc$cl <= 4], dc$cl[dc$cl <= 4], method = "spearman"),
            nrow(di), cor(di$celda, di$ing, method = "spearman")))
cat(sprintf("Mediana C1: %.2f | mediana C2-C5 juntos: %.2f | Wilcoxon C1 vs. C2-C5: p = %.2g\n",
            median(dc$celda[dc$cl == 1]), median(dc$celda[dc$cl > 1]),
            suppressWarnings(wilcox.test(dc$celda[dc$cl == 1], dc$celda[dc$cl > 1])$p.value)))
cat("Kruskal-Wallis entre C2..C5: p = ", signif(kruskal.test(celda ~ cl, dc %>% filter(cl >= 2))$p.value, 3), "\n")

# ----------------------------------------------------------------------
# Contraste con las lecturas teóricas: agro y absorción asalariada
# ----------------------------------------------------------------------
d <- d %>% mutate(
  tramo_agro = cut(agro, c(-Inf, 5, 15, 30, 50, Inf), labels = c("<5%", "5-15%", "15-30%", "30-50%", ">50%")),
  tramo_asal = cut(pct_asal_noagro, c(-Inf, 50, 65, 80, 90, Inf), labels = c("<50%", "50-65%", "65-80%", "80-90%", ">90%")),
  baja_en_tcp_noagro = 100 * celda / (pct_tcp_noagro * noagro / 100))

# Medidas ponderadas por empleo (base del análisis del informe) y, como referencia, medianas.
# `baja_en_tcp_noagro_pond` = participación de la baja calificación dentro del TCP/TF no agrario
# a nivel población: sum(w * celda) / sum(w * tcp_noagro), ambos en % del empleo del país.
tr <- function(v) d %>% group_by(tramo = .data[[v]]) %>% summarise(
  n = n(), peso_pct = sum(w),
  media_pond = weighted.mean(celda, w),
  tcp_noagro_pond = weighted.mean(pct_tcp_noagro, w),
  baja_en_tcp_noagro_pond = 100 * sum(w * celda) / sum(w * tcp_noagro),
  pais_mayor_peso = iso3c[which.max(w)], peso_del_pais = max(w) / sum(w),
  media_pond_sin_pais = if (n() > 1) weighted.mean(celda[-which.max(w)], w[-which.max(w)]) else NA_real_,
  mediana = median(celda), media_simple = mean(celda), .groups = "drop")
t_agro <- tr("tramo_agro"); t_asal <- tr("tramo_asal")
write_csv(bind_rows(t_agro %>% mutate(variable = "peso del agro en el empleo (%)"),
                    t_asal %>% mutate(variable = "% asalariado dentro del no agro")) %>% rename(tramo = tramo),
          file.path(OUT, "tcp_celda_por_tramos.csv"))
cat("\n== Celda de interés según peso del agro en el empleo ==\n"); print(as.data.frame(t_agro), digits = 3)
cat("\n== Celda de interés según % asalariado dentro del no agro ==\n"); print(as.data.frame(t_asal), digits = 3)
# Correlaciones ponderadas por empleo (Pearson ponderado) y sin ponderar (Spearman, referencia)
wcor <- function(a, b) { m <- cov.wt(cbind(d[[a]], d[[b]]), wt = d$w / sum(d$w), cor = TRUE); round(m$cor[1, 2], 2) }
sp <- function(a, b) round(cor(d[[a]], d[[b]], method = "spearman"), 2)
cat("\n== Correlaciones (ponderada por empleo | Spearman sin ponderar) ==\n")
for (par in list(c("celda", "agro"), c("celda", "pct_asal_noagro"), c("celda", "pct_tcp_noagro"),
                 c("baja_en_tcp_noagro", "pct_asal_noagro"), c("baja_en_tcp_noagro", "agro")))
  cat(sprintf("%-20s ~ %-18s ponderada %5.2f | Spearman %5.2f\n", par[1], par[2], wcor(par[1], par[2]), sp(par[1], par[2])))
# sin India (para saber cuánto depende la relación ponderada de ese país)
d_ind <- d; d <- d %>% filter(iso3c != "IND")
cat(sprintf("Sin India -> celda~%%asal_noagro ponderada %.2f | celda~agro ponderada %.2f\n", wcor("celda", "pct_asal_noagro"), wcor("celda", "agro")))
d <- d_ind
cat("\n== Países con mayor valor de la celda de interés ==\n")
print(as.data.frame(d %>% arrange(desc(celda)) %>% transmute(iso3c, celda = round(celda, 2), agro = round(agro, 1),
      pct_asal_noagro = round(pct_asal_noagro, 1), region, cluster = substr(cluster_pimsa, 1, 2)) %>% head(12)))

# ----------------------------------------------------------------------
# Figuras
# ----------------------------------------------------------------------
SURFACE <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID_COL <- "#e1e0d9"
S1 <- "#2a78d6"; S2 <- "#1baf7a"; S6 <- "#e34948"
theme_set(theme_minimal(base_size = 9) + theme(
  plot.caption = element_text(color = MUTED, size = 7.5),
  panel.background = element_rect(fill = SURFACE, color = NA), plot.background = element_rect(fill = SURFACE, color = NA),
  panel.grid.major = element_line(color = GRID_COL, linewidth = 0.3), panel.grid.minor = element_blank(),
  axis.text = element_text(color = MUTED), axis.title = element_text(color = INK2), plot.title = element_text(color = INK, size = 10),
  strip.text = element_text(color = INK2, face = "bold"), strip.background = element_rect(fill = SURFACE, color = GRID_COL),
  legend.position = "bottom"))

long <- bind_rows(
  d %>% filter(!is.na(cluster_pimsa)) %>% mutate(dimension = "Cluster PIMSA", grupo = cluster_pimsa),
  d %>% filter(ing <= 4) %>% mutate(dimension = "Grupo de ingreso", grupo = income_group_2),
  d %>% mutate(dimension = "Región", grupo = region)) %>%
  mutate(dimension = factor(dimension, c("Cluster PIMSA", "Grupo de ingreso", "Región")))
n_g <- long %>% count(dimension, grupo)
long <- long %>% left_join(n_g, by = c("dimension", "grupo")) %>%
  mutate(grupo_n = sub("^(C[0-9])\\. .*", "\\1", grupo), grupo_n = sub("^0([1-4]) ", "\\1 ", grupo_n),
         grupo_n = sprintf("%s (n=%d)", grupo_n, n))
ord <- long %>% distinct(dimension, grupo_n, grupo) %>% arrange(dimension, desc(grupo))
long <- long %>% mutate(grupo_n = factor(grupo_n, levels = unique(ord$grupo_n)))
stats <- long %>% group_by(dimension, grupo_n) %>%
  summarise(med = median(celda), mp = weighted.mean(celda, w), .groups = "drop")

f1 <- ggplot(long, aes(x = celda, y = grupo_n)) +
  geom_point(aes(size = sqrt(w)), position = position_jitter(height = 0.18, width = 0, seed = 1),
             color = INK2, alpha = .3, stroke = 0) +
  geom_point(data = stats, aes(x = med, shape = "Mediana", color = "Mediana"), size = 3.6) +
  geom_point(data = stats, aes(x = mp, shape = "Media ponderada por empleo (014)", color = "Media ponderada por empleo (014)"), size = 3.6) +
  geom_text(data = long %>% filter(iso3c %in% c("IND", "KEN", "SEN", "SOM")),
            aes(label = iso3c, hjust = ifelse(iso3c == "SEN", 1.15, ifelse(iso3c == "SOM", -0.15, 0.5))),
            color = INK, size = 2.4, nudge_y = 0.34) +
  scale_shape_manual(NULL, values = c("Mediana" = 18, "Media ponderada por empleo (014)" = 18)) +
  scale_color_manual(NULL, values = c("Mediana" = "#440154", "Media ponderada por empleo (014)" = "#fde725")) +
  scale_size(range = c(0.6, 6), guide = "none") +
  facet_grid(dimension ~ ., scales = "free_y", space = "free_y") +
  labs(x = "TCP/TF baja calificación no agro, % del empleo", y = NULL,
       title = "Distribución entre países de la celda de interés por cluster, ingreso y región",
       caption = "Cada punto es un país; el tamaño crece con su peso en el empleo.")
ggsave(file.path(FIGS, "fig_019_distribucion_celda_grupos.png"), f1, width = 7.4, height = 8, dpi = 160, bg = SURFACE)

lab <- d %>% filter(iso3c %in% c("IND", "SEN", "KEN", "SOM", "ETH", "USA"))
pa <- bind_rows(d %>% transmute(iso3c, celda, w, x = agro, panel = "A. Peso de la agricultura en el empleo (%)"),
                d %>% transmute(iso3c, celda, w, x = pct_asal_noagro, panel = "B. Asalariados dentro del empleo no agrario (%)"))
la <- bind_rows(lab %>% transmute(iso3c, celda, x = agro, panel = "A. Peso de la agricultura en el empleo (%)"),
                lab %>% transmute(iso3c, celda, x = pct_asal_noagro, panel = "B. Asalariados dentro del empleo no agrario (%)"))
f2 <- ggplot(pa, aes(x = x, y = celda)) +
  geom_point(aes(size = sqrt(w)), color = INK2, alpha = .45, stroke = 0) +
  geom_smooth(aes(weight = w), method = "loess", formula = y ~ x, se = FALSE, color = S1, linewidth = .9) +
  geom_text(data = la, aes(label = iso3c), color = INK, size = 2.4, nudge_y = .45) +
  scale_size(range = c(0.6, 6), guide = "none") +
  facet_wrap(~ panel, scales = "free_x") +
  labs(x = NULL, y = "TCP/TF baja calif. no agro, % del empleo",
       title = "Celda de interés frente al peso del agro y a la absorción asalariada (loess ponderado)")
ggsave(file.path(FIGS, "fig_019_agro_y_absorcion.png"), f2, width = 8, height = 4, dpi = 160, bg = SURFACE)
cat("\nListo. Tablas: data/estimacion/tcp_distribucion_celda_por_grupo.csv, tcp_celda_por_tramos.csv; figuras: reports/figs/fig_019_*.png\n")
