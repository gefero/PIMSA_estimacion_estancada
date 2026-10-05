#!/usr/bin/env Rscript
# 021_ilustracion_cuatro_escenarios.R
#
# Figura didáctica para §2.3 del informe: los cuatro escenarios posibles al comparar la curva de
# error del método solo (self-test) con la del pipeline completo, según cada una sea "buena"
# (errores chicos, pegada al cero) o "mala". TODOS LOS DATOS SON SIMULADOS (46 países
# inventados por escenario, semilla fija): sirven para mostrar la forma de las curvas, no son
# resultados del proyecto.
#
# Uso (raíz del repo como working directory):
#   LC_ALL=C.UTF-8 Rscript src/021_ilustracion_cuatro_escenarios.R

suppressMessages({library(dplyr); library(tidyr); library(ggplot2)})

set.seed(11)
n <- 46

# 1) Método bueno, datos buenos: ambos errores chicos
m1 <- rlnorm(n, log(0.15), 0.6);  c1 <- m1 + abs(rnorm(n, 0, 0.08))
# 2) Método bueno, datos malos: el método acierta, las fuentes difieren mucho
m2 <- rlnorm(n, log(0.15), 0.6);  c2 <- m2 + rlnorm(n, log(2.8), 0.5)
# 3) Método malo, datos que casi no agregan: el error ya está en el método
m3 <- rlnorm(n, log(3), 0.5);     c3 <- m3 + abs(rnorm(n, 0, 0.3))
# 4) Método malo, datos "buenos": los errores de método y de datos se compensan (error con signo)
e4 <- rnorm(n, 0, 3);             m4 <- abs(e4);  c4 <- abs(e4 + (-e4 + rnorm(n, 0, 0.3)))

casos <- c("1. Método bueno, datos buenos", "2. Método bueno, datos malos",
           "3. Método malo, datos que casi no agregan", "4. Método malo, errores que se compensan (raro)")
d <- bind_rows(
  tibble(caso = casos[1], metodo = m1, completo = c1), tibble(caso = casos[2], metodo = m2, completo = c2),
  tibble(caso = casos[3], metodo = m3, completo = c3), tibble(caso = casos[4], metodo = m4, completo = c4)) %>%
  mutate(caso = factor(caso, casos)) %>%
  pivot_longer(c(completo, metodo), names_to = "curva", values_to = "err") %>%
  mutate(curva = factor(curva, c("completo", "metodo"),
                        c("Pipeline completo OIT-IPF vs. IPUMS", "Sólo supuesto IPF (self-test IPUMS)")))

cat("Medianas simuladas (método | pipeline completo):\n")
print(d %>% group_by(caso, curva) %>% summarise(mediana = round(median(err), 2), p90 = round(quantile(err, .9), 2), .groups = "drop") %>%
        pivot_wider(names_from = curva, values_from = c(mediana, p90)) %>% as.data.frame())

SURFACE <- "#fcfcfb"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"; GRID <- "#e1e0d9"
p <- ggplot(d, aes(err, color = curva)) + stat_ecdf(geom = "step", linewidth = 1.2, pad = TRUE) +
  scale_color_manual(NULL, values = c("#1baf7a", "#2a78d6")) +
  coord_cartesian(xlim = c(0, 10)) + facet_wrap(~ caso, ncol = 2) +
  labs(x = "|error| en la celda de interés (puntos porcentuales)", y = "Proporción acumulada de países",
       title = "Cuatro escenarios posibles (SIMULACIÓN: datos inventados, sólo ilustrativos)") +
  theme_minimal(base_size = 9) + theme(
    panel.background = element_rect(fill = SURFACE, color = NA), plot.background = element_rect(fill = SURFACE, color = NA),
    panel.grid.minor = element_blank(), panel.grid.major = element_line(color = GRID, linewidth = .3),
    axis.text = element_text(color = MUTED), axis.title = element_text(color = INK2),
    plot.title = element_text(color = INK, size = 10), strip.text = element_text(color = INK, face = "bold"),
    legend.position = "bottom")
dir.create("./reports/figs", recursive = TRUE, showWarnings = FALSE)
ggsave("./reports/figs/fig_021_cuatro_escenarios.png", p, width = 8.4, height = 6.2, dpi = 150, bg = SURFACE)
cat("Listo: reports/figs/fig_021_cuatro_escenarios.png\n")
