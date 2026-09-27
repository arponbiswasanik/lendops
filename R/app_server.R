library(ggplot2)
library(scales)

app_server <- function(input, output, session) {
  
  # 1. Establish DuckDB connection on app load
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")
  
  # 2. Clean up connection when app closes
  session$onSessionEnded(function() {
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
  
  # --- Module 1: Origination Tracker ---
  
  # Fetch Origination Data (passing filters!)
  funnel_data <- reactive({
    funnel_summary(con, branch = input$branch_filter, sector = input$sector_filter)
  })
  
  tat_data <- reactive({
    tat_summary(con, branch = input$branch_filter, sector = input$sector_filter)
  })
  
  # Render Sankey Diagram
  output$funnel_sankey <- networkD3::renderSankeyNetwork({
    df <- funnel_data()
    
    nodes <- data.frame(name = c("Received", "Screening", "Credit Assessment", "Decision", "Documentation", "Disbursement", "Declined", "Withdrawn"))
    
    # Helper to safely get counts (returns 0 if stage missing due to filters)
    get_count <- function(stage_name) {
      val <- df$n[df$stage == stage_name]
      if (length(val) == 0) 0 else val
    }
    
    links <- data.frame(
      source = c(0, 1, 2, 3, 4),
      target = c(1, 2, 3, 4, 5),
      value = c(
        get_count("Screening"),
        get_count("Credit Assessment"),
        get_count("Decision"),
        get_count("Documentation"),
        get_count("Disbursement")
      )
    )
    
    # Remove 0-value links to keep Sankey clean
    links <- links[links$value > 0, ]
    
    networkD3::sankeyNetwork(
      Links = links, Nodes = nodes,
      Source = "source", Target = "target",
      Value = "value", NodeID = "name",
      fontSize = 12, nodeWidth = 20, nodePadding = 15
    )
  })
  
  # Render TAT Plot
  output$tat_plot <- plotly::renderPlotly({
    df <- tat_data()
    
    # If filtered data is empty, render empty plot to avoid errors
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    p <- ggplot(df, aes(x = branch, y = avg_tat_hours, fill = stage)) +
      geom_col(position = "dodge") +
      labs(x = NULL, y = "Avg TAT (Hours)") +
      theme_minimal() +
      theme(legend.position = "bottom") +
      scale_fill_brewer(palette = "Blues") # Light gradient palette
    
    plotly::ggplotly(p)
  })
  
  # --- Module 2: Portfolio Health ---
  
  # Fetch Portfolio Data
  vintage_data <- reactive({
    vintage_curve(con)
  })
  
  roll_rate_data <- reactive({
    roll_rate_matrix(con)
  })
  
  # Render Vintage Plot
  output$vintage_plot <- plotly::renderPlotly({
    df <- vintage_data()
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    p <- ggplot(df, aes(x = mob, y = delinq_rate, color = as.factor(app_month))) +
      geom_line(size = 1) +
      geom_point(size = 2) +
      labs(x = "Months on Book (MOB)", y = "Delinquency Rate", color = "Cohort Month") +
      scale_y_continuous(labels = scales::percent_format()) +
      scale_color_brewer(palette = "Paired") +
      theme_minimal() +
      theme(legend.position = "bottom")
    
    plotly::ggplotly(p)
  })
  
  # Render Roll-Rate Matrix Heatmap
  output$roll_rate_plot <- plotly::renderPlotly({
    df <- roll_rate_data()
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    # Create readable labels for DPD buckets
    dpd_labels <- c("0", "1-30", "31-60", "61-90", "90+")
    df$prev_dpd_label <- factor(dpd_labels[df$prev_dpd + 1], levels = dpd_labels)
    df$dpd_label <- factor(dpd_labels[df$dpd + 1], levels = dpd_labels)
    
    p <- ggplot(df, aes(x = prev_dpd_label, y = dpd_label, fill = transition_rate)) +
      geom_tile(color = "white", linewidth = 1) + # Added white borders between tiles
      geom_text(aes(label = scales::percent(transition_rate, accuracy = 0.1)), color = "black", size = 4) +
      labs(x = "Previous Month DPD", y = "Current Month DPD") +
      # Light blue gradient so black text is always visible
      scale_fill_gradient(low = "white", high = "#6baed6", limits = c(0, 1)) +
      theme_minimal() +
      theme(legend.position = "none")
    
    plotly::ggplotly(p)
  })
}