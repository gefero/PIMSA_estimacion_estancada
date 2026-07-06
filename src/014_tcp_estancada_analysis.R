library(tidyverse)

#tcps_means <- read_csv('./data/estimacion_estancada/tabla_tcps_final_means.csv') %>%
#        drop_na(-c(region:cluster_pimsa)) %>%
#        mutate(tcp_fliares_no_agro_resto = prop_tcp_fliares_no_agro - prop_tcp_fliares_no_agro_calif_baja)

tcps_sums <- read_csv('./data/estimacion_estancada/tabla_tcps_final_sums.csv') %>%
        drop_na(-c(region:cluster_pimsa)) %>%
        mutate(tcp_fliares_no_agro_resto = prop_tcp_fliares_no_agro - prop_tcp_fliares_no_agro_calif_baja)






library(GGally)
library(gt)

tcps_sums %>%
        group_by(cluster_pimsa) %>%
        summarise(
                across(prop_tcp_fliares_totales:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na() %>%
        gt() %>%
        fmt_number(columns = where(is.numeric), decimals = 2) %>%
        cols_label(
                cluster_pimsa = "Cluster PIMSA",
                prop_tcp_fliares_totales = "Prop. TCP fliares totales",
                prop_tcp_fliares_calif_baja = "Prop. TCP fliares calif. baja",
                prop_tcp_fliares_no_agro = "Prop. TCP fliares no agro",
                prop_no_agro_calif_baja = "Prop. no agro calif. baja",
                prop_tcp_fliares_no_agro_calif_baja = "Prop. TCP fliares no agro calif. baja",
                tcp_fliares_no_agro_resto = "Prop. resto TCP fliares no agro calif. resto"
        )


library(spatstat.geom)



tcps_sums %>%
        group_by(income_group_2) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na() %>%
        gt() %>%
        fmt_number(columns = where(is.numeric), decimals = 2) %>%
        cols_label(
                income_group_2 = "Grupo ingreso",
                prop_tcp_fliares_calif_baja = "Prop. TCP fliares calif. baja",
                prop_tcp_fliares_no_agro = "Prop. TCP fliares no agro",
                prop_no_agro_calif_baja = "Prop. no agro calif. baja",
                prop_tcp_fliares_no_agro_calif_baja = "Prop. TCP fliares no agro calif. baja",
                tcp_fliares_no_agro_resto = "Prop. resto TCP fliares no agro calif. resto"
        )



tcps_sums %>%
        group_by(region) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:tcp_fliares_no_agro_resto,
                       ~weighted.mean(.x, prop_ocup_totales))
        ) %>%
        ungroup() %>%
        drop_na() %>%
        gt() %>%
        fmt_number(columns = where(is.numeric), decimals = 2) %>%
        cols_label(
                region = "Región",
                prop_tcp_fliares_calif_baja = "Prop. TCP fliares calif. baja",
                prop_tcp_fliares_no_agro = "Prop. TCP fliares no agro",
                prop_no_agro_calif_baja = "Prop. no agro calif. baja",
                prop_tcp_fliares_no_agro_calif_baja = "Prop. TCP fliares no agro calif. baja",
                tcp_fliares_no_agro_resto = "Prop. resto TCP fliares no agro calif. resto"
        )


library(ggplot2)
tcps_sums %>%
        drop_na(cluster_pimsa) %>%
        ggparcoord(
                columns = 18:21, 
                groupColumn = 7, 
                #scale="uniminmax",
                #order = "anyClass",
                showPoints = TRUE,
                #title = "Parallel Coordinate Plot for the Iris Data",
                alphaLines = 0.3
                ) +
        scale_color_viridis_d() +
        theme_minimal() +
        theme(legend.position = "none") 
        




tcps_sums %>%
        group_by(cluster_pimsa) %>%
        summarise(
                across(prop_tcp_fliares_calif_baja:prop_tcp_fliares_no_agro_calif_baja,
                       list(mean_w=~weighted.mean(.x, prop_ocup_totales),
                            mean=mean))
                )%>%
                        pivot_longer(
                                cols = starts_with("prop"),
                                names_to = "indicador",
                                values_to = "value")

                