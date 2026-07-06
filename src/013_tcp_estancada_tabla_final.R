library(tidyverse)

# Ruta de la estimación IPF a usar (actualizar al re-correr 012)
ESTIMACION_PATH <- './data/estimacion_estancada/20251118_estimacion_tcp_final.csv'

estanc <-read_csv(ESTIMACION_PATH)

catocup_rama <- read_csv('./data/estimacion_estancada/catocup_rama.csv') 
catocup_rama <- catocup_rama %>%
        #filter(ref_area %in% intersect) %>%
        filter(catocup != "9.SD" & rama2 != "9.SD")

ocup_totales <- catocup_rama %>%
        group_by(ref_area, ref_area.label, time) %>%
        summarise(n = sum(obs_value, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label) %>%
        summarise(n = mean(n, na.rm=TRUE)) %>%
        ungroup()
        
        
catocup_agg <- catocup_rama %>%
        group_by(ref_area, ref_area.label, time, catocup) %>%
        summarise(sum = sum(obs_value, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label, catocup) %>%
        summarise(n = mean(sum, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label) %>%
        mutate(prop = 100*n/sum(n)) %>%
        ungroup()


catocup_rama_agg <- catocup_rama %>%
        group_by(ref_area, ref_area.label, time, rama2, catocup) %>%
        summarise(sum= sum(obs_value, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label, rama2, catocup) %>%
        summarise(n = mean(sum, na.rm=TRUE)) %>%
        group_by(ref_area, ref_area.label) %>%
        mutate(prop = 100*n/sum(n)) %>%
        ungroup()



catocup_calif<- read_csv('./data/estimacion_estancada/catocup_calif.csv') %>%
#        filter(ref_area %in% intersect) %>%
        filter(catocup != "9.SD" & calif != "9.SD")
        
catocup_calif_agg <- catocup_calif %>%
        group_by(ref_area, ref_area.label, time, catocup, calif) %>%
        summarise(sum = sum(obs_value, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label,catocup, calif) %>%
        summarise(n = mean(sum, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label) %>%
        mutate(prop = 100*n/sum(n)) %>%
        ungroup()



calif_rama <- read_csv('./data/estimacion_estancada/calif_rama.csv') %>%
      #  filter(ref_area %in% intersect) %>%
        filter(rama2 != "9.SD" & calif != "9.SD")

 
calif_rama_agg <- calif_rama %>%
        group_by(ref_area, ref_area.label, time, calif, rama2) %>%
        summarise(sum = sum(obs_value, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label, calif, rama2) %>%
        summarise(n = mean(sum, na.rm=TRUE)) %>%
        ungroup() %>%
        group_by(ref_area, ref_area.label) %>%
        #mutate(n = replace_na(n, 0)) %>%
        mutate(prop = 100*n/sum(n)) %>%
        ungroup()


tcp_fliares_calif_baja <- catocup_calif_agg %>%
        filter(catocup == "3.TCP_fliares" & calif == "1.Baja") %>%
        mutate(indicador = "tcp_fliares_calif_baja") %>%
        select(ref_area, ref_area.label, indicador, n, prop)

tcp_fliares_no_agro <- catocup_rama_agg %>%
        filter(catocup == "3.TCP_fliares" & rama2 == "2.No_agro") %>%
        mutate(indicador = "tcp_fliares_no_agro") %>%
        select(ref_area, ref_area.label, indicador, n, prop)

no_agro_calif_baja <- calif_rama_agg %>%
        filter(calif == "1.Baja" & rama2 == "2.No_agro") %>%
        mutate(indicador = "no_agro_calif_baja") %>%
        select(ref_area, ref_area.label, indicador, n, prop)

tcp_fliares_no_agro_calif_baja <- estanc %>%
        filter(calificacion=="1.Baja" & rama=="2.No_agro" & ocupacion == "3.TCP_fliares") %>%
        mutate(indicador = "tcp_fliares_no_agro_calif_baja",
               ref_area.label = countrycode::countrycode(iso3c, 
                                                         origin = 'iso3c', 
                                                         destination = 'country.name',
                                                         custom_match = TRUE),
               n = NA) %>%
        rename(ref_area = iso3c,
               prop = freq) %>%
        select(ref_area, ref_area.label, indicador,n, prop)


ocup_totales <- ocup_totales %>%
        mutate(indicador = "ocup_totales",
               prop = 100*n/sum(n)) %>%
        select(ref_area, ref_area.label, indicador,n, prop)
        
catocup_agg <- catocup_agg %>%
        filter(catocup == "3.TCP_fliares") %>%
        mutate(indicador = "tcp_fliares_totales") %>%
        select(ref_area, ref_area.label, indicador,n, prop)


tabla_final <- ocup_totales %>%
        bind_rows(
                catocup_agg
        ) %>%
        bind_rows(
                tcp_fliares_calif_baja
        ) %>%
        bind_rows(
                tcp_fliares_no_agro
        ) %>%
        bind_rows(
                no_agro_calif_baja
        ) %>%
        bind_rows(
                tcp_fliares_no_agro_calif_baja
        )
        
tabla_final <- tabla_final %>%
        pivot_wider(
                names_from = indicador,
                values_from = c(n, prop)
        ) %>%
        select(
                -n_tcp_fliares_no_agro_calif_baja
        )


#tcps <- read_csv('./data/estimacion_estancada/tabla_tcps_final.csv')
country_classif <- read_csv('./data/ouputs/country_classification.csv') %>%
        # el archivo trae iso3c repetidos (grafías distintas del nombre de
        # país); sin dedupe el join duplica países en la tabla final
        distinct(iso3c, .keep_all = TRUE)

tabla_final <- tabla_final %>%
        rename(iso3c=ref_area) %>%
        left_join(country_classif, by = "iso3c") %>%
        select(iso3c, ref_area.label, country:ocde, everything())


# tabla_final  <- estanc %>%
#         filter(calificacion=="1.Baja" & rama=="2.No_agro" & ocupacion == "3.TCP_fliares") %>%
#         select(iso3c, freq) %>%
#         rename(ref_area = iso3c,
#                tcp_fliares_no_agro_calif_baja = freq) %>%
#         left_join(
#                 catocup_agg %>%
#                         filter(catocup == "3.TCP_fliares") %>%
#                         rename(
#                                n_tcp_fliares = n,
#                                prop_tcp_fliares = prop) %>%
#                         select(-c(catocup, ref_area.label))
#         ) %>%
#         left_join(
#                 catocup_rama_agg %>%
#                         filter(rama2 == "2.No_agro" & catocup == "3.TCP_fliares") %>%
#                         rename(prop_tcp_fliares_no_agro = prop,
#                                n_tcp_fliares_no_agro = n) %>%
#                         select(-rama2, -catocup)
#                         ) %>%
#         left_join(
#                 calif_rama_agg %>%
#                         filter(rama2 == "2.No_agro" & calif == "1.Baja") %>%
#                 rename(prop_no_agro_calif_baja = prop,
#                        n_no_agro_calif_baja = n) %>%
#                         select(-rama2, -calif)
#         ) %>%
#         select(starts_with("ref"), everything())
# 

tabla_final %>%
        write_csv('./data/estimacion_estancada/tabla_tcps_final_sums.csv')
