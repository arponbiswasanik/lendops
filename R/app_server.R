library(ggplot2)
library(scales)
library(tidyr)

app_server <- function(input, output, session) {
  
  # 1. Establish DuckDB connection on app load
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = "inst/testdata/lendops.duckdb")
  
  # 2. Clean up connection when app closes
  session$onSessionEnded(function() {
    DBI::dbDisconnect(con, shutdown = TRUE)
  })
  
  # --- Module 1: Origination Tracker ---
  
  funnel_data <- reactive({
    funnel_summary(con, branch = input$branch_filter, sector = input$sector_filter)
  })
  
  tat_data <- reactive({
    tat_summary(con, branch = input$branch_filter, sector = input$sector_filter)
  })
  
  # Render Sankey Diagram (Clean linear flow, no drop-offs)
  output$funnel_sankey <- networkD3::renderSankeyNetwork({
    df <- funnel_data()
    
    # Helper to safely get counts
    get_count <- function(stage_name) {
      val <- df$n[df$stage == stage_name]
      if (length(val) == 0) 0 else val
    }
    
    # Define the 6 main stages of the happy path
    nodes <- data.frame(name = c("Received", "Screening", "Credit Assessment", "Decision", "Documentation", "Disbursement"))
    
    # Define links: strictly linear (0->1, 1->2, etc.)
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
      fontSize = 12, nodeWidth = 20, nodePadding = 30 # Increased padding to fix overlap
    )
  })
  
  # Render TAT Plot (Clean light-blue version)
  output$tat_plot <- plotly::renderPlotly({
    df <- tat_data()
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    p <- ggplot(df, aes(x = branch, y = avg_tat_hours, fill = stage)) +
      geom_col(position = "dodge") +
      labs(x = NULL, y = "Avg TAT (Hours)") +
      theme_minimal() +
      theme(legend.position = "bottom") +
      scale_fill_brewer(palette = "Blues")
    
    plotly::ggplotly(p)
  })
  
  # --- Module 2: Portfolio Health ---
  
  vintage_data <- reactive({
    vintage_curve(con)
  })
  
  roll_rate_data <- reactive({
    roll_rate_matrix(con)
  })
  
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
  
  output$roll_rate_plot <- plotly::renderPlotly({
    df <- roll_rate_data()
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    dpd_labels <- c("0", "1-30", "31-60", "61-90", "90+")
    df$prev_dpd_label <- factor(dpd_labels[df$prev_dpd + 1], levels = dpd_labels)
    df$dpd_label <- factor(dpd_labels[df$dpd + 1], levels = dpd_labels)
    
    p <- ggplot(df, aes(x = prev_dpd_label, y = dpd_label, fill = transition_rate)) +
      geom_tile(color = "white", linewidth = 1) +
      geom_text(aes(label = scales::percent(transition_rate, accuracy = 0.1)), color = "black", size = 4) +
      labs(x = "Previous Month DPD", y = "Current Month DPD") +
      scale_fill_gradient(low = "white", high = "#6baed6", limits = c(0, 1)) +
      theme_minimal() +
      theme(legend.position = "none")
    
    plotly::ggplotly(p)
  })
  
  # --- Module 3: KPI Cockpit ---
  
  kpi_data <- reactive({
    kpi_summary(con, branch = input$branch_filter, sector = input$sector_filter)
  })
  
  output$kpi_total_apps <- renderText({
    format(kpi_data()$total_applications, big.mark = ",")
  })
  
  output$kpi_approval_rate <- renderText({
    paste0(round(kpi_data()$approval_rate * 100, 1), "%")
  })
  
  output$kpi_disbursed_amt <- renderText({
    paste0("BDT ", format(round(kpi_data()$total_disbursed_amt / 10000000, 1), nsmall = 1), " Cr")
  })
  
  output$kpi_ticket_size <- renderText({
    paste0("BDT ", format(round(kpi_data()$avg_ticket_size / 100000, 1), nsmall = 1), " Lakh")
  })
  
  disb_target_data <- reactive({
    disbursed <- dplyr::tbl(con, "applications") |>
      dplyr::filter(final_status == "Disbursed") |>
      dplyr::mutate(month = dbplyr::sql("DATE_TRUNC('month', app_month)")) |>
      dplyr::group_by(month) |>
      dplyr::summarise(actual_disbursement = sum(requested_amt, na.rm = TRUE), .groups = "drop")
    
    targets <- dplyr::tbl(con, "targets") |>
      dplyr::mutate(month = dbplyr::sql("DATE_TRUNC('month', target_month)")) |>
      dplyr::group_by(month) |>
      dplyr::summarise(target_disbursement = sum(target_disbursement_amt, na.rm = TRUE), .groups = "drop")
    
    dplyr::inner_join(disbursed, targets, by = "month") |>
      dplyr::collect()
  })
  
  output$disb_target_plot <- plotly::renderPlotly({
    df <- disb_target_data()
    if (nrow(df) == 0) return(plotly::plotly_empty())
    
    plot_df <- df |>
      tidyr::pivot_longer(cols = c(actual_disbursement, target_disbursement), 
                          names_to = "type", values_to = "amount") |>
      dplyr::mutate(amount_cr = amount / 10000000)
    
    p <- ggplot(plot_df, aes(x = month, y = amount_cr, color = type, group = type)) +
      geom_line(size = 1) +
      geom_point(size = 2) +
      labs(x = "Month", y = "Amount (BDT Crore)", color = "Legend") +
      scale_color_brewer(palette = "Set1") +
      theme_minimal() +
      theme(legend.position = "bottom")
    
    plotly::ggplotly(p)
  })
}