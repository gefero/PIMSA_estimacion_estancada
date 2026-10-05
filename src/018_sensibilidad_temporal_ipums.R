#!/usr/bin/env Rscript
# 018_sensibilidad_temporal_ipums.R
#
# Parte C de la descomposición del error IPUMS-IPF (ver 017): ¿cuánto podría pesar el desfase
# temporal? La estimación vigente promedia los años disponibles de ILOSTAT (2009-2019) y se
# compara con un censo IPUMS de un año desconocido. Acá se rehace la estimación OIT UN AÑO POR
# VEZ (con la misma agregación suma-antes-que-promedio de 011, y los mismos pasos que 012:
# se descarta 9.SD, cada tabla se normaliza a 100 y se corre el IPF con semilla uniforme) y se
# mide, por país, cuánto varía la estimación y el error contra IPUMS según el año elegido.
#
# No requiere conocer el año del censo IPUMS: acota cuánto *podría* pesar el tiempo.
#
# Uso (raíz del repo como working directory):
#   LC_ALL=C.UTF-8 Rscript src/018_sensibilidad_temporal_ipums.R [--sufijo _v3]

suppressMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(ggplot2)
  library(tibble)
})
options(readr.show_col_types = FALSE)

OUT  <- "./data/test_ipf"
RAW  <- "./data/raw_data"
FIGS <- "./reports/figs"

args <- commandArgs(trailingOnly = TRUE)
SUFIJO <- if (length(i <- which(args == "--sufijo"))) args[i + 1] else "_v3"

CAL <- c("1.Baja", "2.Media", "3.Alta")
OCU <- c("1.Asalariado_patr", "3.TCP_fliares")
RAM <- c("1.Agro", "2.No_agro")
D2 <- list(c(1, 2), c(2, 3), c(1, 3))

comp <- read_csv(file.path(OUT, paste0("comp_raking_ipums_full", SUFIJO, ".csv")))
paises <- unique(comp$iso3c)

to_array <- function(d, col) {
  J <- array(0, dim = c(3, 2, 2), dimnames = list(CAL, OCU, RAM))
  for (i in seq_len(nrow(d))) J[d$calificacion[i], d$ocupacion[i], d$rama[i]] <- d[[col]][i]
  J
}

ipf_nd <- function(seed, dims, targets, iters = 1000, tol = 1e-9) {
  x <- seed
  for (it in seq_len(iters)) {
    for (k in seq_along(dims)) {
      m <- apply(x, dims[[k]], sum)
      x <- sweep(x, dims[[k]], ifelse(m > 0, targets[[k]] / ifelse(m == 0, 1, m), 0), `*`)
    }
    gap <- max(map2_dbl(dims, targets, ~ max(abs(apply(x, .x, sum) - .y))))
    if (gap < tol) break
  }
  attr(x, "gap") <- gap
  x
}

# ----------------------------------------------------------------------
# Tablas bivariadas por país-año (suma de categorías finas dentro de cada año)
# ----------------------------------------------------------------------
lee <- function(f, k1, k2) {
  read_csv(file.path(RAW, f)) %>%
    filter(ref_area %in% paises, .data[[k1]] != "9.SD", .data[[k2]] != "9.SD") %>%
    group_by(iso3c = ref_area, time, k1 = .data[[k1]], k2 = .data[[k2]]) %>%
    summarise(v = sum(obs_value, na.rm = TRUE), .groups = "drop")
}
t_cc <- lee("catocup_calif.csv", "catocup", "calif")   # ocu x cal
t_cr <- lee("catocup_rama.csv",  "catocup", "rama2")   # ocu x ram
t_kr <- lee("calif_rama.csv",    "calif",   "rama2")   # cal x ram

mat <- function(t, filas, cols) {
  m <- matrix(0, length(filas), length(cols), dimnames = list(filas, cols))
  for (i in seq_len(nrow(t))) if (t$k1[i] %in% filas && t$k2[i] %in% cols) m[t$k1[i], t$k2[i]] <- t$v[i]
  100 * m / sum(m)
}

anios_ok <- function(iso) {
  Reduce(intersect, list(unique(t_cc$time[t_cc$iso3c == iso]), unique(t_cr$time[t_cr$iso3c == iso]),
                         unique(t_kr$time[t_kr$iso3c == iso])))
}

est_anio <- function(iso, y) {
  a <- t_cc %>% filter(iso3c == iso, time == y); b <- t_cr %>% filter(iso3c == iso, time == y)
  c <- t_kr %>% filter(iso3c == iso, time == y)
  m_cal_ocu <- t(mat(a, OCU, CAL))   # cal x ocu
  m_ocu_ram <- mat(b, OCU, RAM)
  m_cal_ram <- mat(c, CAL, RAM)
  est <- ipf_nd(array(1, c(3, 2, 2), dimnames = list(CAL, OCU, RAM)), D2, list(m_cal_ocu, m_ocu_ram, m_cal_ram))
  list(est = est, gap = attr(est, "gap"))
}

# ----------------------------------------------------------------------
# Por país y año
# ----------------------------------------------------------------------
filas <- map_dfr(paises, function(iso) {
  d <- comp %>% filter(iso3c == iso)
  U <- to_array(d, "ipums_porc")
  prom <- to_array(d, "raking_porc")
  map_dfr(sort(anios_ok(iso)), function(y) {
    r <- est_anio(iso, y)
    tibble(iso3c = iso, anio = y,
           celda = r$est["1.Baja", "3.TCP_fliares", "2.No_agro"],
           mae12 = mean(abs(r$est - U)), gap = r$gap,
           ipums = U["1.Baja", "3.TCP_fliares", "2.No_agro"],
           celda_prom = prom["1.Baja", "3.TCP_fliares", "2.No_agro"],
           mae12_prom = mean(abs(prom - U)))
  })
})
write_csv(filas, file.path(OUT, paste0("descomp_error_temporal_anios", SUFIJO, ".csv")))


# Un país-año es "consistente" si las tres tablas ILOSTAT son casi compatibles entre sí
# (distancia máx. del IPF a los márgenes < GAP_MAX pp). Las tablas de un mismo país-año no
# comparten exactamente los márgenes univariados (cobertura, categorías sin datos); cuando la
# inconsistencia es grande (SEN, TZA, RWA), la trivariada deja de ser interpretable.
GAP_MAX <- 1

resume_paises <- function(f) {
  f %>% mutate(err = celda - ipums) %>%
    group_by(iso3c) %>%
    summarise(n_anios = n(), anio_min = min(anio), anio_max = max(anio),
              ipums = first(ipums), celda_prom = first(celda_prom),
              err_prom = first(celda_prom) - first(ipums),
              err_min = min(err), err_max = max(err),
              rango_celda = max(celda) - min(celda), sd_celda = sd(celda),
              mae12_prom = first(mae12_prom), mae12_min = min(mae12), mae12_max = max(mae12),
              mejor_anio = anio[which.min(abs(err))], gap_max = max(gap),
              .groups = "drop") %>%
    mutate(cruza_cero = err_min <= 0 & err_max >= 0)   # algún año reproduce el valor IPUMS
}

reporta <- function(f, titulo) {
  pais <- resume_paises(f); multi <- pais %>% filter(n_anios >= 2)
  cat(sprintf("\n=== %s ===\n", titulo))
  cat(sprintf("Países-año: %d | países: %d | con >= 2 años comparables: %d\n",
              nrow(f), n_distinct(f$iso3c), nrow(multi)))
  cat(sprintf("Rango de la celda clave entre años: mediana %.2f pp | media %.2f | p90 %.2f | máx %.2f (%s)\n",
              median(multi$rango_celda), mean(multi$rango_celda), quantile(multi$rango_celda, .9),
              max(multi$rango_celda), multi$iso3c[which.max(multi$rango_celda)]))
  cat(sprintf("|Error| de la celda clave con el promedio: mediana %.2f pp (media %.2f)\n",
              median(abs(multi$err_prom)), mean(abs(multi$err_prom))))
  cat(sprintf("Algún año reproduce el valor IPUMS (el error cambia de signo entre años): %d de %d países\n",
              sum(multi$cruza_cero), nrow(multi)))
  cat(sprintf("Rango interanual / |error promedio|: mediana %.2f\n",
              median(multi$rango_celda / pmax(abs(multi$err_prom), 1e-6))))
  cat(sprintf("Spearman(|error promedio|, rango interanual) = %.2f (n = %d)\n",
              cor(abs(multi$err_prom), multi$rango_celda, method = "spearman"), nrow(multi)))
  pais
}

cat(sprintf("Países-año con gap > %g pp (inconsistencia entre tablas): %d de %d | países afectados: %s\n",
            GAP_MAX, sum(filas$gap > GAP_MAX), nrow(filas),
            paste(sort(unique(filas$iso3c[filas$gap > GAP_MAX])), collapse = ", ")))

pais_todo <- reporta(filas, "Todos los países-año")
pais <- reporta(filas %>% filter(gap <= GAP_MAX), sprintf("Solo país-año consistentes (gap <= %g pp)", GAP_MAX))
write_csv(pais, file.path(OUT, paste0("descomp_error_temporal_paises", SUFIJO, ".csv")))
multi <- pais %>% filter(n_anios >= 2)

top <- multi %>% arrange(desc(abs(err_prom))) %>%
  transmute(iso3c, n_anios, anios = paste(anio_min, anio_max, sep = "-"), err_prom = round(err_prom, 2),
            rango_celda = round(rango_celda, 2), err_min = round(err_min, 2), err_max = round(err_max, 2), cruza_cero) %>%
  head(12)
cat("\nLos 12 países con mayor |error| (promedio), solo consistentes:\n"); print(as.data.frame(top))

# Verificación: el promedio de los años (en niveles) debería parecerse al estimador vigente
chk <- filas %>% filter(gap <= GAP_MAX) %>% group_by(iso3c) %>% summarise(m = mean(celda), p = first(celda_prom), .groups = "drop")
cat(sprintf("Check: promedio simple de celdas por año vs. estimador vigente: dif. media abs = %.2f pp, máx = %.2f pp\n",
            mean(abs(chk$m - chk$p)), max(abs(chk$m - chk$p))))

# ----------------------------------------------------------------------
# Figura
# ----------------------------------------------------------------------
SURFACE <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID_COL <- "#e1e0d9"
S1 <- "#2a78d6"; S2 <- "#1baf7a"
theme_set(theme_minimal(base_size = 9) + theme(
  panel.background = element_rect(fill = SURFACE, color = NA), plot.background = element_rect(fill = SURFACE, color = NA),
  panel.grid.major = element_line(color = GRID_COL, linewidth = 0.3), panel.grid.minor = element_blank(),
  axis.text = element_text(color = MUTED), axis.title = element_text(color = INK2), plot.title = element_text(color = INK, size = 10)))

pf <- multi %>% mutate(iso3c = reorder(iso3c, ipums))
f <- ggplot(pf, aes(y = iso3c)) +
  geom_linerange(aes(xmin = ipums + err_min, xmax = ipums + err_max), color = S1, linewidth = 1.2, alpha = .6) +
  geom_point(aes(x = celda_prom), color = S1, size = 1.4) +
  geom_point(aes(x = ipums), color = S2, size = 1.8, shape = 18) +
  labs(x = "TCP/TF baja calif. no agro, % del empleo", y = NULL,
       title = "C. Estimación OIT-IPF año por año (barra azul; punto = promedio) vs. IPUMS (rombo verde)")
ggsave(file.path(FIGS, "fig_018_sensibilidad_temporal.png"), f, width = 7, height = 7.5, dpi = 160, bg = SURFACE)
cat("\nListo.\n")
