library(plotly)
library(tidyverse)


# Function 1: Dumbbell/Dot Plot (FIXED)
create_dumbbell_plot <- function(data) {
        
        # Prepare data with ordering
        all_data <- data %>%
                mutate(category = paste0(rama, " ", ocupacion, " ", calificacion),
                       diff = raking_porc - ipums_porc)
        
        categories <- unique(all_data$category)
        
        # Calculate global min/max for fixed scale
        global_min <- min(c(all_data$raking_porc, all_data$ipums_porc), na.rm = TRUE)
        global_max <- max(c(all_data$raking_porc, all_data$ipums_porc), na.rm = TRUE)
        
        # Create traces for all categories
        p <- plot_ly()
        
        for (cat in categories) {
                data_subset <- all_data %>%
                        filter(category == cat) %>%
                        arrange(diff) %>%  # Order by difference
                        mutate(row_id = row_number(),
                               iso3c_ordered = paste0(iso3c, "_", row_id)) %>%
                        mutate(iso3c_ordered = factor(iso3c_ordered, levels = iso3c_ordered))
                
                # Add segments
                p <- p %>%
                        add_segments(
                                data = data_subset,
                                x = ~raking_porc, xend = ~ipums_porc,
                                y = ~iso3c_ordered, yend = ~iso3c_ordered,
                                color = I("grey"),
                                showlegend = FALSE,
                                visible = (cat == categories[1]),
                                name = paste0("segment_", cat),
                                hoverinfo = "none"
                        )
                
                # Add Raking points
                p <- p %>%
                        add_markers(
                                data = data_subset,
                                x = ~raking_porc, y = ~iso3c_ordered,
                                name = "Raking",
                                marker = list(color = rgb(0.2,0.7,0.1,0.5), size = 8),
                                legendgroup = "Raking",
                                visible = (cat == categories[1]),
                                customdata = ~country,
                                hovertemplate = paste0('<b>%{customdata}</b> (%{text})<br>',
                                                       'Raking: %{x:.2f}%<br>',
                                                       '<extra></extra>'),
                                text = ~iso3c
                        )
                
                # Add IPUMS points
                p <- p %>%
                        add_markers(
                                data = data_subset,
                                x = ~ipums_porc, y = ~iso3c_ordered,
                                name = "IPUMS",
                                marker = list(color = rgb(0.7,0.2,0.1,0.5), size = 8),
                                legendgroup = "IPUMS",
                                visible = (cat == categories[1]),
                                customdata = ~country,
                                hovertemplate = paste0('<b>%{customdata}</b> (%{text})<br>',
                                                       'IPUMS: %{x:.2f}%<br>',
                                                       '<extra></extra>'),
                                text = ~iso3c
                        )
        }
        
        # Create category dropdown buttons
        category_buttons <- lapply(seq_along(categories), function(i) {
                visible <- rep(FALSE, length(categories) * 3)
                visible[((i-1)*3 + 1):(i*3)] <- TRUE
                
                list(
                        method = "update",  # Changed from "restyle" to "update"
                        args = list(
                                list(visible = visible),  # Update traces visibility
                                list(title = list(text = paste0("Category: ", categories[i])))  # Update title
                        ),
                        label = categories[i]
                )
        })
        
        # Create scale toggle buttons
        scale_buttons <- list(
                list(
                        method = "relayout",
                        args = list("xaxis.range", c(global_min, global_max)),
                        label = "Fixed Scale"
                ),
                list(
                        method = "relayout",
                        args = list("xaxis.range", NULL),
                        label = "Auto Scale"
                )
        )
        
        # Get the first category's data to set initial y-axis labels
        first_cat_data <- all_data %>%
                filter(category == categories[1]) %>%
                arrange(diff) %>%
                mutate(row_id = row_number(),
                       iso3c_ordered = paste0(iso3c, "_", row_id))
        
        # Add layout with both dropdowns
        p <- p %>%
                layout(
                        updatemenus = list(
                                list(
                                        type = "dropdown",
                                        direction = "down",
                                        xanchor = "left",
                                        yanchor = "top",
                                        x = 0.01,
                                        y = 1.15,
                                        buttons = category_buttons
                                ),
                                list(
                                        type = "buttons",
                                        direction = "right",
                                        xanchor = "right",
                                        yanchor = "top",
                                        x = 1,
                                        y = 1.15,
                                        buttons = scale_buttons
                                )
                        ),
                        xaxis = list(title = "%", range = c(global_min, global_max)),
                        yaxis = list(
                                title = "",
                                tickmode = "array",
                                tickvals = first_cat_data$iso3c_ordered,
                                ticktext = first_cat_data$iso3c
                        ),
                        title = list(text = paste0("Category: ", categories[1]))
                )
        
        return(p)
}

# Function 2: Scatter Plot (FIXED)
create_scatter_plot <- function(data) {
        
        # Prepare data
        all_data <- data %>%
                filter(!is.na(ipums_porc)) %>%
                mutate(category = paste0(rama, " ", ocupacion, " ", calificacion))
        
        categories <- unique(all_data$category)
        
        # Get unique clusters and assign viridis colors
        clusters <- unique(all_data$cluster_pimsa)
        n_clusters <- length(clusters)
        
        # Generate viridis colors
        viridis_colors <- viridisLite::viridis(n_clusters)
        names(viridis_colors) <- clusters
        
        # Calculate global min/max for fixed scale
        global_min_x <- min(all_data$raking_porc, na.rm = TRUE)
        global_max_x <- max(all_data$raking_porc, na.rm = TRUE)
        global_min_y <- min(all_data$ipums_porc, na.rm = TRUE)
        global_max_y <- max(all_data$ipums_porc, na.rm = TRUE)
        
        # Create traces for all categories
        p <- plot_ly()
        
        for (cat in categories) {
                data_subset <- all_data %>%
                        filter(category == cat)
                
                # Add points for each cluster within this category
                for (clust in clusters) {
                        cluster_data <- data_subset %>%
                                filter(cluster_pimsa == clust)
                        
                        if (nrow(cluster_data) > 0) {
                                p <- p %>%
                                        add_markers(
                                                data = cluster_data,
                                                x = ~raking_porc,
                                                y = ~ipums_porc,
                                                name = clust,
                                                legendgroup = clust,
                                                marker = list(color = viridis_colors[clust], size = 8),
                                                visible = (cat == categories[1]),
                                                customdata = ~country,
                                                text = ~iso3c,
                                                hovertemplate = paste0('<b>%{customdata}</b> (%{text})<br>',
                                                                       'Raking: %{x:.2f}%<br>',
                                                                       'IPUMS: %{y:.2f}%<br>',
                                                                       'Cluster: ', clust, '<br>',
                                                                       '<extra></extra>')
                                        )
                        }
                }
        }
        
        # Create category dropdown buttons
        # Count traces per category (number of clusters that appear in each category)
        traces_per_category <- sapply(categories, function(cat) {
                data_subset <- all_data %>% filter(category == cat)
                length(unique(data_subset$cluster_pimsa))
        })
        
        category_buttons <- lapply(seq_along(categories), function(i) {
                # Calculate which traces belong to this category
                if (i == 1) {
                        start_idx <- 1
                } else {
                        start_idx <- sum(traces_per_category[1:(i-1)]) + 1
                }
                end_idx <- start_idx + traces_per_category[i] - 1
                
                visible <- rep(FALSE, sum(traces_per_category))
                visible[start_idx:end_idx] <- TRUE
                
                list(
                        method = "update",  # Changed from "restyle" to "update"
                        args = list(
                                list(visible = visible),  # Update traces visibility
                                list(title = list(text = paste0("Category: ", categories[i])))  # Update title
                        ),
                        label = categories[i]
                )
        })
        
        # Create scale toggle buttons
        scale_buttons <- list(
                list(
                        method = "relayout",
                        args = list(
                                "xaxis.range" = c(global_min_x, global_max_x),
                                "yaxis.range" = c(global_min_y, global_max_y)
                        ),
                        label = "Fixed Scale"
                ),
                list(
                        method = "relayout",
                        args = list(
                                "xaxis.range" = NULL,
                                "yaxis.range" = NULL
                        ),
                        label = "Auto Scale"
                )
        )
        
        # Add layout with both controls
        p <- p %>%
                layout(
                        updatemenus = list(
                                list(
                                        type = "dropdown",
                                        direction = "down",
                                        xanchor = "left",
                                        yanchor = "top",
                                        x = 0.01,
                                        y = 1.15,
                                        buttons = category_buttons
                                ),
                                list(
                                        type = "buttons",
                                        direction = "right",
                                        xanchor = "right",
                                        yanchor = "top",
                                        x = 1,
                                        y = 1.15,
                                        buttons = scale_buttons
                                )
                        ),
                        xaxis = list(
                                title = "Raking (%)",
                                range = c(global_min_x, global_max_x)
                        ),
                        yaxis = list(
                                title = "IPUMS (%)",
                                range = c(global_min_y, global_max_y)
                        ),
                        title = list(text = paste0("Category: ", categories[1])),
                        showlegend = TRUE,
                        legend = list(title = list(text = "Cluster"))
                )
        
        return(p)
}