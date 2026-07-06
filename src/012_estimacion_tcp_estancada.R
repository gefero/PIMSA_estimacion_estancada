library(tidyverse)
library(mipfp)

intersect <- read_csv('./data/estimacion_estancada/country_intersect.csv') %>% pull()

catocup_rama_agg <- read_csv('./data/estimacion_estancada/catocup_rama_agg.csv') %>%
        filter(ref_area %in% intersect) %>%
        filter(catocup != "9.SD") %>%
        select(-`9.SD`)

calif_rama_agg <- read_csv('./data/estimacion_estancada/calif_rama_agg.csv') %>%
        filter(ref_area %in% intersect) %>%
        filter(calif != "9.SD") %>%
        select(-`9.SD`)


catocup_calif_agg <- read_csv('./data/estimacion_estancada/catocup_calif_agg.csv')%>%
        filter(ref_area %in% intersect) %>%
        filter(catocup != "9.SD") %>%
        select(-`9.SD`)



format_table <- function(df_raw, a,
                         cols_to_drop=c("ref_area", "ref_area.label", "catocup")){
        # La 3ra columna es la clave de fila (catocup o calif); se ordena para
        # que las dimensiones queden alineadas entre las tres tablas del IPF.
        table <- df_raw %>%
                filter(ref_area == a) %>%
                arrange(across(3))

        names <- table[, 3] %>% pull()
        
        table <- table %>%
                select(-all_of(cols_to_drop)) %>%
                mutate(across(everything(), ~replace_na(.x, 0))) %>%
                as.matrix()
        
        table <- table / sum(table)*100
        
        row.names(table) <- names
        
        return(table)
        
}

tabla_final <- tibble(
        iso3c = character(),
        calificacion = character(),
        ocupacion = character(),
        rama = character(),
        freq = numeric()
)

run_tcp_estimates <- function(){
        for (a in intersect){
                tabla1_mat <- t(format_table(catocup_calif_agg %>% filter(ref_area==a), a))
                tabla2_mat <- format_table(catocup_rama_agg %>% filter(ref_area==a), a)
                tabla3_mat <- format_table(calif_rama_agg %>% filter(ref_area==a), 
                                           a, 
                                           cols_to_drop = c("ref_area", "ref_area.label","calif"))
                
                # tabla1_mat <- tabla1_mat / sum(tabla1_mat)
                # tabla2_mat <- tabla2_mat / sum(tabla2_mat)
                # tabla3_mat <- tabla3_mat / sum(tabla3_mat)
                # 
                seed <- array(1, dim = c(
                        nrow(tabla1_mat), # calificación
                        ncol(tabla1_mat), # ocupación
                        ncol(tabla2_mat) # rama
                ))
                
                # Definir targets y dimensiones correspondientes
                # Definir targets y dimensiones asociadas
                target.list <- list(tabla1_mat, tabla2_mat, tabla3_mat)
                target.dim <- list(
                        c(1, 2), # calificación × ocupación
                        c(2, 3), # ocupación × rama
                        c(1, 3) # calificación × rama
                )
                
                # Ejecutar IPF
                res <- Ipfp(seed = seed, 
                            target.list = target.dim, 
                            target.data = target.list,
                            iter = 5000)
                
                # Resultado: tabla trivariada estimada
                tabla_trivariada <- res$x.hat
                
                ## Reescalar al total real (por ejemplo, usando tabla2 en miles)
                #total_miles <- sum(as.matrix(tabla2))
                #tabla_final <- tabla_prob * total_miles
                
                # Asignar nombres de dimensiones
                dimnames(tabla_trivariada) <- list(
                        calificacion = rownames(tabla1_mat),
                        ocupacion = colnames(tabla1_mat),
                        rama = colnames(tabla2_mat)
                )
                
                # Mostrar parte de la tabla estimada
                print(round(tabla_trivariada, 2))
                
                # Exportar tabla en formato largo
                tabla_larga <- as.data.frame(as.table(tabla_trivariada))
                tabla_larga <- tabla_larga %>%
                        rename(freq = Freq) %>%
                        mutate(iso3c = a) %>%
                        select(iso3c, everything())
                
                tabla_final <- tabla_final %>% bind_rows(tabla_larga)
        }
        return(tabla_final)
}

tictoc::tic()
tabla_final <- run_tcp_estimates()
tictoc::toc()


tabla_final %>% write_csv(paste0('./data/estimacion_estancada/',
                                 format(Sys.Date(), format="%Y%m%d"),
                                 '_estimacion_tcp_final_v2.csv')
)
