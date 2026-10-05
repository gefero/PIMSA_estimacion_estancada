#!/usr/bin/env Rscript
# 017_descomposicion_error_ipums.R
#
# Abre el "error de fuente" entre la estimación IPF (insumos OIT) y IPUMS.
# El self-test de 015 separa error de método vs. error de fuente; acá se abre este último
# reemplazando piezas de los insumos OIT por las de IPUMS y midiendo cuánto se mueve el error.
#
#   A. Intercambio de piezas: cada tabla bivariada se descompone en COMPOSICIÓN (los tres
#      márgenes univariados, comunes a las tres tablas) y ASOCIACIÓN (la estructura interna de
#      cada tabla, ajustada a la composición elegida). Se corre el IPF con las 2^4 combinaciones
#      (composición OIT/IPUMS x asociación de cada una de las 3 tablas OIT/IPUMS) y se reparte
#      la reducción del error entre las 4 piezas con valores de Shapley. Mezclar tablas
#      bivariadas enteras de fuentes distintas NO sirve: sus márgenes univariados compartidos
#      se contradicen y el IPF no converge.
#   B. Escalera composición vs. asociación: se parte de la trivariada OIT y se la ajusta
#      progresivamente a IPUMS (márgenes univariados -> bivariados), para ver en qué escalón
#      desaparece el error.
#
# Insumo: data/test_ipf/comp_raking_ipums_full_v3.csv (salida de 015: trivariada OIT-IPF
# `raking_porc` e IPUMS `ipums_porc`, por país y celda). Los márgenes OIT se obtienen
# sumando `raking_porc`, que es equivalente a los márgenes de entrada del IPF en 012
# (verificado más abajo).
#
# Uso (raíz del repo como working directory):
#   LC_ALL=C.UTF-8 Rscript src/017_descomposicion_error_ipums.R [--sufijo _v3]

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
FIGS <- "./reports/figs"
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

args <- commandArgs(trailingOnly = TRUE)
SUFIJO <- if (length(i <- which(args == "--sufijo"))) args[i + 1] else "_v3"

CAL <- c("1.Baja", "2.Media", "3.Alta")
OCU <- c("1.Asalariado_patr", "3.TCP_fliares")
RAM <- c("1.Agro", "2.No_agro")
CLAVE <- c(1, 2, 2)   # índices (Baja, TCP/TF, No agro) en el array [cal, ocu, ram]

comp <- read_csv(file.path(OUT, paste0("comp_raking_ipums_full", SUFIJO, ".csv")))

# ----------------------------------------------------------------------
# Utilidades
# ----------------------------------------------------------------------
to_array <- function(d, col) {
  J <- array(0, dim = c(3, 2, 2), dimnames = list(CAL, OCU, RAM))
  for (i in seq_len(nrow(d))) J[d$calificacion[i], d$ocupacion[i], d$rama[i]] <- d[[col]][i]
  J
}

# IPF genérico: `seed` (array 3x2x2), `dims` lista de vectores de dimensiones a ajustar,
# `targets` lista de márgenes objetivo (mismo orden que `dims`).
# Devuelve el array ajustado y la distancia máxima final a los márgenes (convergencia).
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

D2 <- list(c(1, 2), c(2, 3), c(1, 3))   # márgenes bivariados: cal×ocu, ocu×ram, cal×ram
D1 <- list(1, 2, 3)                     # márgenes univariados
marg <- function(J, dims) map(dims, ~ apply(J, .x, sum))
unif <- function(J) array(sum(J) / length(J), dim = dim(J), dimnames = dimnames(J))

celda <- function(J) J[CLAVE[1], CLAVE[2], CLAVE[3]]
mae   <- function(J, T) mean(abs(J - T))

# ----------------------------------------------------------------------
# A + B por país
# ----------------------------------------------------------------------
# Ajusta una tabla 2D a márgenes de fila y columna dados (IPF de 2 dimensiones).
rake2 <- function(tab, rowT, colT, iters = 1000, tol = 1e-10) {
  x <- tab
  for (it in seq_len(iters)) {
    r <- rowSums(x); x <- x * ifelse(r > 0, rowT / ifelse(r == 0, 1, r), 0)
    cc <- colSums(x); x <- sweep(x, 2, ifelse(cc > 0, colT / ifelse(cc == 0, 1, cc), 0), `*`)
    if (max(abs(rowSums(x) - rowT)) < tol) break
  }
  x
}

# 16 combinaciones: comp (TRUE = márgenes univariados de IPUMS) y asoc1..3 (TRUE = estructura
# interna de la tabla bivariada j tomada de IPUMS)
combos <- expand.grid(comp = c(FALSE, TRUE), asoc_cal_ocu = c(FALSE, TRUE),
                      asoc_ocu_ram = c(FALSE, TRUE), asoc_cal_ram = c(FALSE, TRUE))
PIEZAS <- c("Composición (márgenes univariados)", "Asociación Situación × Calificación",
            "Asociación Situación × Rama", "Asociación Calificación × Rama")

run_pais <- function(d) {
  iso <- unique(d$iso3c)
  O <- to_array(d, "raking_porc")   # trivariada OIT-IPF
  U <- to_array(d, "ipums_porc")    # verdad IPUMS
  mO <- marg(O, D2); mU <- marg(U, D2)
  uO <- marg(O, D1); uU <- marg(U, D1)

  # --- A: 16 combinaciones ---
  va <- pmap_dfr(combos, function(comp, asoc_cal_ocu, asoc_ocu_ram, asoc_cal_ram) {
    sel <- c(asoc_cal_ocu, asoc_ocu_ram, asoc_cal_ram)
    uni <- if (comp) uU else uO
    tg <- map(1:3, function(j) {
      fuente <- if (sel[j]) mU[[j]] else mO[[j]]
      dj <- D2[[j]]
      rake2(fuente, uni[[dj[1]]], uni[[dj[2]]])
    })
    est <- ipf_nd(unif(U), D2, tg)
    tibble(iso3c = iso, comp, asoc_cal_ocu, asoc_ocu_ram, asoc_cal_ram,
           celda = celda(est), mae12 = mae(est, U), gap = attr(est, "gap"))
  })

  # --- B: escalera OIT -> IPUMS ---
  e1 <- ipf_nd(O, D1, uU)                          # composición: univariados de IPUMS
  e2 <- ipf_nd(O, D2, mU)                          # + bivariados de IPUMS, semilla OIT
  e3 <- ipf_nd(unif(U), D2, mU)                    # + semilla uniforme (= self-test)
  vb <- tibble(iso3c = iso,
               escalon = c("0.OIT-IPF", "1.Univariados IPUMS", "2.Bivariados IPUMS (semilla OIT)",
                           "3.Bivariados IPUMS (semilla uniforme = self-test)"),
               celda = c(celda(O), celda(e1), celda(e2), celda(e3)),
               mae12 = c(mae(O, U), mae(e1, U), mae(e2, U), mae(e3, U)),
               verdad = celda(U))
  list(a = va, b = vb)
}

res <- map(split(comp, comp$iso3c), run_pais)
A <- map_dfr(res, "a")
B <- map_dfr(res, "b")

# ----------------------------------------------------------------------
# Verificaciones
# ----------------------------------------------------------------------
cat("== Verificaciones ==\n")
cat(sprintf("A: convergencia, gap máx = %.2e (%d de %d combinaciones con gap > 1e-4)\n", max(A$gap), sum(A$gap > 1e-4), nrow(A)))
oit_ok <- A %>% filter(!comp, !asoc_cal_ocu, !asoc_ocu_ram, !asoc_cal_ram)
chk <- comp %>% filter(calificacion == CAL[CLAVE[1]], ocupacion == OCU[CLAVE[2]], rama == RAM[CLAVE[3]]) %>%
  select(iso3c, raking_porc, ipums_porc) %>% inner_join(oit_ok, by = "iso3c")
cat(sprintf("A todo-OIT vs. raking_porc (celda clave): dif. máx = %.4f pp\n", max(abs(chk$celda - chk$raking_porc))))
st <- read_csv(file.path(OUT, paste0("selftest_ipf_ipums", SUFIJO, ".csv"))) %>%
  filter(calificacion == CAL[CLAVE[1]], ocupacion == OCU[CLAVE[2]], rama == RAM[CLAVE[3]]) %>%
  select(iso3c, ipf_self) %>% inner_join(A %>% filter(comp, asoc_cal_ocu, asoc_ocu_ram, asoc_cal_ram), by = "iso3c")
cat(sprintf("A todo-IPUMS vs. selftest (celda clave): dif. máx = %.2e pp\n", max(abs(st$celda - st$ipf_self))))

# ----------------------------------------------------------------------
# A: Shapley sobre la celda clave (con signo) y sobre el MAE de las 12 celdas
# ----------------------------------------------------------------------
# v(S) = valor (celda o MAE) cuando el conjunto S de piezas viene de IPUMS.
# Contribución de la pieza j = promedio sobre órdenes de [v(S) - v(S ∪ j)] (reducción).
perm4 <- function(v = 1:4) {
  if (length(v) <= 1) return(list(v))
  do.call(c, lapply(seq_along(v), function(i) lapply(perm4(v[-i]), function(p) c(v[i], p))))
}
PERMS <- perm4()
key_s <- function(r) paste0(as.integer(r$comp), as.integer(r$asoc_cal_ocu), as.integer(r$asoc_ocu_ram), as.integer(r$asoc_cal_ram))
shap <- function(a, var) {
  v <- setNames(a[[var]], key_s(a))
  contrib <- rep(0, 4)
  for (p in PERMS) {
    s <- rep(0, 4)
    for (j in p) {
      s2 <- s; s2[j] <- 1
      contrib[j] <- contrib[j] + (v[[paste(s, collapse = "")]] - v[[paste(s2, collapse = "")]]) / length(PERMS)
      s <- s2
    }
  }
  tibble(pieza = PIEZAS, contrib = contrib)
}

# Países con alguna combinación que no converge (soporte incompatible: celdas en cero de una
# fuente que la otra composición no puede llenar) se excluyen: el Shapley exige las 16 válidas.
TOL_GAP <- 1e-4
excl <- A %>% group_by(iso3c) %>% summarise(n_mal = sum(gap > TOL_GAP), .groups = "drop") %>% filter(n_mal > 0)
cat(sprintf("\nExcluidos del Shapley por no convergencia (%d países, %d de %d combinaciones): %s\n",
            nrow(excl), sum(excl$n_mal), nrow(A), paste(excl$iso3c, collapse = ", ")))
A_ok <- A %>% filter(!iso3c %in% excl$iso3c)

sh <- map_dfr(split(A_ok, A_ok$iso3c), function(a) {
  verdad <- B$verdad[B$iso3c == a$iso3c[1]][1]
  tot <- a$celda[key_s(a) == "0000"] - verdad
  bind_rows(
    shap(a, "celda") %>% mutate(medida = "celda clave (pp, con signo)"),
    shap(a, "mae12") %>% mutate(medida = "MAE 12 celdas (pp)")
  ) %>% mutate(iso3c = a$iso3c[1], error_total_celda = tot)
})
write_csv(sh, file.path(OUT, paste0("descomp_error_margenes", SUFIJO, ".csv")))
write_csv(A, file.path(OUT, paste0("descomp_error_margenes_combos", SUFIJO, ".csv")))

# Chequeo: las contribuciones suman v(∅) - v(todo)
sumchk <- sh %>% group_by(iso3c, medida) %>% summarise(s = sum(contrib), .groups = "drop") %>%
  left_join(A_ok %>% group_by(iso3c) %>% summarise(
    celda = celda[key_s(pick(everything())) == "0000"] - celda[key_s(pick(everything())) == "1111"],
    mae12 = mae12[key_s(pick(everything())) == "0000"] - mae12[key_s(pick(everything())) == "1111"]), by = "iso3c") %>%
  mutate(esperado = if_else(startsWith(medida, "celda clave"), celda, mae12))
cat(sprintf("Shapley: suma de contribuciones vs. v(OIT)-v(IPUMS), dif. máx = %.2e\n", max(abs(sumchk$s - sumchk$esperado))))

cat("\n== A. Shapley: reducción del error al reemplazar cada pieza OIT por la de IPUMS ==\n")
print(sh %>% group_by(medida, pieza) %>%
        summarise(media = mean(contrib), mediana = median(contrib), media_abs = mean(abs(contrib)), .groups = "drop") %>%
        as.data.frame(), digits = 3)
pieza_dom <- sh %>% filter(medida == "MAE 12 celdas (pp)") %>%
  group_by(iso3c) %>% slice_max(contrib, n = 1, with_ties = FALSE) %>% ungroup() %>% count(pieza)
cat("\nPieza que más reduce el MAE, # países:\n"); print(as.data.frame(pieza_dom))

# ----------------------------------------------------------------------
# B: escalera
# ----------------------------------------------------------------------
write_csv(B, file.path(OUT, paste0("descomp_error_escalera", SUFIJO, ".csv")))
esc <- B %>% mutate(err_celda = celda - verdad) %>%
  group_by(escalon) %>%
  summarise(MAE_celda = mean(abs(err_celda)), sesgo_celda = mean(err_celda),
            MAE_12 = mean(mae12), .groups = "drop")
cat("\n== B. Escalera OIT -> IPUMS (promedio sobre países) ==\n")
print(as.data.frame(esc), digits = 3)

# ----------------------------------------------------------------------
# Figuras
# ----------------------------------------------------------------------
SURFACE <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID_COL <- "#e1e0d9"; S1 <- "#2a78d6"
theme_set(theme_minimal(base_size = 9) + theme(
  panel.background = element_rect(fill = SURFACE, color = NA), plot.background = element_rect(fill = SURFACE, color = NA),
  panel.grid.major = element_line(color = GRID_COL, linewidth = 0.3), panel.grid.minor = element_blank(),
  axis.text = element_text(color = MUTED), axis.title = element_text(color = INK2), plot.title = element_text(color = INK, size = 10)))

f1 <- sh %>% filter(medida == "MAE 12 celdas (pp)") %>%
  ggplot(aes(x = pieza, y = contrib)) +
  geom_hline(yintercept = 0, color = "#c3c2b7") +
  geom_boxplot(fill = NA, color = S1, outlier.size = 1) +
  scale_x_discrete(labels = function(x) sub(" ", "\n", x)) +
  labs(x = NULL, y = "Reducción del MAE (pp) al usar la pieza IPUMS",
       title = "A. ¿Qué pieza de los insumos OIT aporta más al error? (Shapley, por país)")
ggsave(file.path(FIGS, "fig_017_shapley_margenes.png"), f1, width = 6.6, height = 4, dpi = 160, bg = SURFACE)

f2 <- B %>% ggplot(aes(x = escalon, y = mae12)) +
  geom_boxplot(fill = NA, color = S1, outlier.size = 1) +
  scale_x_discrete(labels = function(x) sub(" \\(", "\n(", x)) +
  labs(x = NULL, y = "MAE 12 celdas (pp)",
       title = "B. Escalera de ajuste a IPUMS: ¿en qué escalón desaparece el error?")
ggsave(file.path(FIGS, "fig_017_escalera.png"), f2, width = 7.5, height = 4, dpi = 160, bg = SURFACE)

cat("\nListo.\n")
