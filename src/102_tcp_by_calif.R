#library(tidyverse)
library(magrittr)
data <- readr::read_rds('./data/ipumsi_00008_selected_vars.rds')
gc()
# 
# data <- data %>%
#         dplyr::mutate(CLASSWK = labelled::to_character(CLASSWK),
#                CLASSWKD = labelled::to_character(CLASSWKD))
# gc()
# 
# data <- data %>%
#         dplyr::mutate(rama_agg = dplyr::case_when(
#                 INDGEN == 10 ~ "Agro",
#                 INDGEN %in% c(0, 998, 999) ~ "Sin dato",
#                 TRUE ~ "No agro"
#         ))
# 
# gc()
# 
# data %>% 
#         dplyr::select(COUNTRY_lab, YEAR, HHWT, PERWT, cat_ocup, rama_agg, skill_level) %>%
#         readr::write_rds('./data/ipumsi_00006_selected_vars.rds')

test <- data %>%
        dplyr::filter(rama_agg != "Sin dato") %>%
        dplyr::filter(skill_level != "Sin dato de skill") %>%
        dplyr::filter(cat_ocup != "No data") %>%
        dplyr::group_by(COUNTRY_lab, rama_agg, skill_level, cat_ocup) %>%
        dplyr::summarise(n_raw = dplyr::n(),
                         n_wei = sum(PERWT)
        ) %>%
        dplyr:: ungroup()

gc()

test %>% readr::write_csv('./data/outputs/v2_tcp_by_calif.csv')
