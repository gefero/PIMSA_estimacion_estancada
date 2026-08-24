library(dplyr)
library(tidyr)
library(readr)
library(ggplot2)
library(GGally)
library(knitr)

tcps_sums <- read_csv('./data/estimacion/tabla_tcps_final_sums.csv') %>%
        drop_na(-c(region:cluster_pimsa)) %>%
        mutate(tcp_fliares_no_agro_resto = prop_tcp_fliares_no_agro - prop_tcp_fliares_no_agro_calif_baja)

OUT <- './data/estimacion'
FIGS <- './reports/figs'
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGS, recursive = TRUE, showWarnings = FALSE)

etiquetas <- c(
        cluster_pimsa = "Cluster PIMSA",
        income_group_2 = "Grupo ingreso",
        region = "Región",
        prop_tcp_fliares_totales = "Prop. TCP fliares totales",
        prop_tcp_fliares_calif_baja = "Prop. TCP fliares calif. baja",
        prop_tcp_fliares_no_agro = "Prop. TCP fliares no agro",
        prop_no_agro_calif_baja = "Prop. no agro calif. baja",
        prop_tcp_fliares_no_agro_calif_baja = "Prop. TCP fliares no agro calif. baja",
        tcp_fliares_no_agro_resto = "Prop. resto TCP fliares no agro calif. resto"
)

por_cluster <- tcps_sums %>%
        group_by(cluster_pimsa) %>%
        summarise(
                across(prop_tcp_fliares_totales:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na()

cat("\n== Indicadores TCP/TF por cluster PIMSA ==\n")
print(kable(por_cluster, digits = 2, col.names = etiquetas[names(por_cluster)]))
write_csv(por_cluster, file.path(OUT, "tcp_indicadores_por_cluster.csv"))

por_ingreso <- tcps_sums %>%
        group_by(income_group_2) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na()

cat("\n== Indicadores TCP/TF por grupo de ingreso ==\n")
print(kable(por_ingreso, digits = 2, col.names = etiquetas[names(por_ingreso)]))
write_csv(por_ingreso, file.path(OUT, "tcp_indicadores_por_ingreso.csv"))

por_region <- tcps_sums %>%
        group_by(region) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na()

cat("\n== Indicadores TCP/TF por región ==\n")
print(kable(por_region, digits = 2, col.names = etiquetas[names(por_region)]))
write_csv(por_region, file.path(OUT, "tcp_indicadores_por_region.csv"))

fig_parcoord <- tcps_sums %>%
        drop_na(cluster_pimsa) %>%
        ggparcoord(
                columns = 18:21,
                groupColumn = 7,
                showPoints = TRUE,
                alphaLines = 0.3
                ) +
        scale_color_viridis_d() +
        theme_minimal() +
        theme(legend.position = "none")
ggsave(file.path(FIGS, "fig_014_parcoord_clusters.png"), fig_parcoord,
       width = 9, height = 5.5, dpi = 160, bg = "white")

medias_por_cluster <- tcps_sums %>%
        group_by(cluster_pimsa) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:prop_tcp_fliares_no_agro_calif_baja,
                       list(mean_w = ~weighted.mean(.x, prop_ocup_totales),
                            mean = mean))
                ) %>%
        pivot_longer(
                cols = starts_with("prop"),
                names_to = "indicador",
                values_to = "value")

cat("\n== Medias (ponderada vs. simple) por cluster, formato largo ==\n")
print(medias_por_cluster, n = Inf)
write_csv(medias_por_cluster, file.path(OUT, "tcp_medias_por_cluster_long.csv"))

cat("\nListo. Tablas en data/estimacion/tcp_*.csv, figura en reports/figs/fig_014_parcoord_clusters.png\n")
