library(tidyverse)
library(countrycode)
source('./src/199_plotly_plots.R')


ipums <- read_csv('./data/ipums_ifp_v2_tcp_by_calif.csv')
ipums <- ipums %>%
        mutate(iso3c = countrycode(COUNTRY_lab, 
                                   origin = 'country.name', 
                                   destination = 'iso3c') 
)


ipums <- ipums %>%
        mutate(cat_ocup = case_when(
                cat_ocup %in% c("Own account worker", "Unpaid worker") ~ "3.TCP_fliares",
                TRUE ~ "1.Asalariado_patr"),
               rama_agg = if_else(rama_agg=="Agro", "1.Agro", "2.No_agro"),
               skill_level = case_when(
                       skill_level == "Level 1" ~ "1.Baja",
                       skill_level == "Level 2" ~ "2.Media",
                       skill_level == "Level 3-4" ~ "3.Alta",
               )
        )

ipums <- ipums %>%
        group_by(iso3c) %>%
        mutate(porc_raw = 100*n_raw/sum(n_raw),
               porc_wei = 100*n_wei/sum(n_wei)
        ) %>%
        ungroup()


ipums %>%
        group_by(COUNTRY_lab, rama_agg, skill_level)

countries <- read_csv("./data/tabla_tcps_final_sums.csv") %>%
        distinct(iso3c, .keep_all = TRUE) %>%
        select(iso3c, country, region, income_group, income_group_2,
               cluster_pimsa, peq_estado, excl_tamaño, ocde)

raking <- read_csv('./data/20251118_estimacion_tcp_final.csv')

raking <- raking %>%
        # armonización defensiva: la estimación vieja trae "3-Alta"
        mutate(calificacion = if_else(calificacion == "3-Alta",
                                      "3.Alta", calificacion)) %>%
        rename(raking_porc = freq)

countries_ipums <- ipums %>% select(iso3c) %>% unique() %>% pull()

raking_filt <- raking %>%
        filter(iso3c %in% countries_ipums)


ipums <- ipums %>% 
        select(iso3c, skill_level, cat_ocup, rama_agg, porc_wei) %>%
        rename(calificacion = skill_level,
               ocupacion=cat_ocup,
               rama = rama_agg,
               ipums_porc = porc_wei)

comp_raking_ipums <- raking_filt %>%
        left_join(ipums)

comp_raking_ipums <- comp_raking_ipums %>%
        mutate(diff = raking_porc - ipums_porc) %>%
        left_join(countries)


####
####

tcps_fliares_noagro <- comp_raking_ipums %>%
        filter(ocupacion == "3.TCP_fliares"
               & rama == "2.No_agro" 
               & calificacion == "1.Baja")

tcps_fliares_noagro <- tcps_fliares_noagro %>%
        mutate(rank_ipums = rank(ipums_porc),
               rank_raking = rank(raking_porc))


cor(tcps_fliares_noagro$ipums_porc, tcps_fliares_noagro$raking_porc,
    method="spearman", use="complete.obs")

tcps_fliares_noagro %>%
        ggplot() +
                geom_point(aes(x=rank_ipums, y=rank_raking))
#################
##################

comp_raking_ipums %>%
        filter(!is.na(ipums_porc)) %>%
        ggplot(aes(x=raking_porc, y=ipums_porc, color=cluster_pimsa)) + 
                geom_point() + 
                facet_wrap(~rama + ocupacion + calificacion) +
                scale_color_viridis_d() +
                theme_minimal()

comp_raking_ipums %>%
        mutate(category = paste0(rama, ocupacion, calificacion, sep=" ")) %>%
        ggplot() +
        geom_segment(aes(x=raking_porc, xend=ipums_porc, y=iso3c, yend=iso3c), color="grey") +
        geom_point(aes(x=raking_porc, y=iso3c, color="Raking"), size=2) +
        geom_point(aes(x=ipums_porc, y=iso3c, color="IPUMS"), size=2) +
        scale_color_manual(
                name = "Source",
                values = c("Raking" = rgb(0.2,0.7,0.1,0.5), 
                           "IPUMS" = rgb(0.7,0.2,0.1,0.5))
        ) +
        theme_minimal() +
        facet_wrap(~category) +
        theme(
                legend.position = "right"
        ) +
        xlab("%") +
        ylab("")


################

comp_raking_ipums %>%
        filter(ocupacion == "3.TCP_fliares"
               & rama == "2.No_agro" 
               & calificacion == "1.Baja") %>%
        ggplot() + 
                geom_histogram(aes(x=diff))

comp_raking_ipums



# Usage examples:
dumbbell_plot <- create_dumbbell_plot(comp_raking_ipums)
dumbbell_plot

scatter_plot <- create_scatter_plot(comp_raking_ipums)
scatter_plot
