#!/usr/bin/env Rscript
# 020_ilustracion_ecdf_metodo_vs_datos.R
#
# Figura didáctica para §2.3 del informe: compara el gráfico real de distribución acumulada del
# error (self-test vs. pipeline completo, celda de interés, 46 países de IPUMS) con una
# SIMULACIÓN INVENTADA de cómo se vería si el problema fuera el método (errores grandes aun con
# datos perfectos, y el pipeline completo casi igual al self-test). Los datos del panel derecho
# NO son datos del proyecto: son ilustrativos.
#
# Uso (raíz del repo como working directory):
#   LC_ALL=C.UTF-8 Rscript src/020_ilustracion_ecdf_metodo_vs_datos.R

suppressMessages({library(dplyr);library(readr);library(ggplot2)}); options(readr.show_col_types=FALSE)
# Los 46 países del self-test. La verdad `ipums_true` vale 0 donde IPUMS no tiene casos en la celda (Francia);
# usar comp_raking_ipums_full (que descarta esa celda) dejaría 45 países y cambiaría las medianas.
st <- read_csv("data/test_ipf/selftest_ipf_ipums_v3.csv") %>% filter(calificacion=="1.Baja",ocupacion=="3.TCP_fliares",rama=="2.No_agro") %>% transmute(iso3c, metodo=abs(err), verdad=ipums_true)
est <- read_csv("data/estimacion/20260824_estimacion_tcp_final_v2.csv") %>% filter(calificacion=="1.Baja",ocupacion=="3.TCP_fliares",rama=="2.No_agro") %>% select(iso3c, raking=freq)
real <- inner_join(st,est,by="iso3c") %>% mutate(completo=abs(raking-verdad)) %>% select(iso3c, metodo, completo)
stopifnot(nrow(real)==nrow(st))
set.seed(7); n <- nrow(real)
# Simulación: el método falla incluso con datos perfectos (errores típicos ~3 pp), y los datos agregan poco
sim_metodo   <- rlnorm(n, log(3), 0.55)
sim_completo <- sim_metodo + abs(rnorm(n, 0, 0.4))
sim <- tibble(iso3c=paste0("S",1:n), metodo=sim_metodo, completo=sim_completo)
d <- bind_rows(real %>% mutate(panel="DATOS REALES: el problema son los datos"),
               sim  %>% mutate(panel="SIMULACIÓN (inventada): el problema sería el método")) %>%
  tidyr::pivot_longer(c(metodo,completo),names_to="curva",values_to="err") %>%
  mutate(curva=factor(curva,c("completo","metodo"),c("Pipeline completo OIT-IPF vs. IPUMS","Sólo supuesto IPF (self-test IPUMS)")),
         panel=factor(panel,unique(panel)))
SURFACE<-"#fcfcfb"; INK<-"#0b0b0b"; INK2<-"#52514e"; MUTED<-"#898781"; GRID<-"#e1e0d9"
p <- ggplot(d,aes(err,color=curva)) + stat_ecdf(geom="step",linewidth=1.3,pad=TRUE) +
  scale_color_manual(NULL,values=c("#1baf7a","#2a78d6")) +
  coord_cartesian(xlim=c(0,9)) + facet_wrap(~panel) +
  labs(x="|error| en la celda de interés (puntos porcentuales)",y="Proporción acumulada de países",
       title="Cómo se vería el gráfico si el problema fuera el método (derecha) vs. el real (izquierda)") +
  theme_minimal(base_size=9)+theme(panel.background=element_rect(fill=SURFACE,color=NA),plot.background=element_rect(fill=SURFACE,color=NA),
   panel.grid.minor=element_blank(),panel.grid.major=element_line(color=GRID,linewidth=.3),axis.text=element_text(color=MUTED),axis.title=element_text(color=INK2),
   plot.title=element_text(color=INK,size=10),strip.text=element_text(color=INK,face="bold"),legend.position="bottom")
ggsave("./reports/figs/fig_020_ecdf_metodo_vs_datos.png",p,width=9,height=4.2,dpi=150,bg=SURFACE)
cat(sprintf("real:  mediana método %.2f | mediana completo %.2f | máx método %.2f\n",median(real$metodo),median(real$completo),max(real$metodo)))
cat(sprintf("simul: mediana método %.2f | mediana completo %.2f | máx método %.2f\n",median(sim$metodo),median(sim$completo),max(sim$metodo)))
