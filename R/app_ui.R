app_ui <- function() {
  bslib::page_navbar(
    title = "lendops",
    id = "nav",
    theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
    
    # Custom CSS to fix navbar hover/visibility issues
    header = tags$head(tags$style(HTML("
      .navbar-nav .nav-link {
        color: rgba(255, 255, 255, 0.85) !important;
      }
      .navbar-nav .nav-link.active {
        color: #ffffff !important;
        font-weight: bold;
      }
      .navbar-nav .nav-link:hover {
        color: #ffffff !important;
      }
    "))),
    
    # --- Tab 1: Origination Tracker ---
    bslib::nav_panel(
      title = "Origination Tracker",
      bslib::layout_sidebar(
        sidebar = bslib::sidebar(
          width = 220,
          bslib::card_header("Filters"),
          selectInput("branch_filter", "Branch", 
                      choices = c("All", "Gulshan", "Dhanmondi", "Motijheel", "Chattogram", "Sylhet", "Khulna", "Rajshahi", "Mirpur"), 
                      selected = "All"),
          selectInput("sector_filter", "Sector", 
                      choices = c("All", "Manufacturing", "Trading", "Services", "Agro", "Textile", "Construction"), 
                      selected = "All")
        ),
        # Charts (stacked)
        bslib::card(
          bslib::card_header("Application Flow (Sankey)"),
          bslib::card_body(networkD3::sankeyNetworkOutput("funnel_sankey", height = "450px"))
        ),
        bslib::card(
          bslib::card_header("Turnaround Time (TAT) by Branch"),
          bslib::card_body(plotly::plotlyOutput("tat_plot", height = "400px"))
        )
      )
    ),
    
    # --- Tab 2: Portfolio Health ---
    bslib::nav_panel(
      title = "Portfolio Health",
      bslib::layout_columns(
        col_widths = c(6, 6),
        bslib::card(
          bslib::card_header("Vintage Delinquency Curves"),
          bslib::card_body(plotly::plotlyOutput("vintage_plot", height = "400px"))
        ),
        bslib::card(
          bslib::card_header("Roll-Rate Migration Matrix"),
          bslib::card_body(plotly::plotlyOutput("roll_rate_plot", height = "400px"))
        )
      )
    ),
    
    # --- Tab 3: KPI Cockpit ---
    bslib::nav_panel(
      title = "KPI Cockpit",
      # Value Boxes Row
      bslib::layout_columns(
        col_widths = c(3, 3, 3, 3),
        bslib::value_box(
          title = "Total Applications",
          value = textOutput("kpi_total_apps"),
          showcase = shiny::icon("file-invoice")
        ),
        bslib::value_box(
          title = "Approval Rate",
          value = textOutput("kpi_approval_rate"),
          showcase = shiny::icon("check-circle")
        ),
        bslib::value_box(
          title = "Disbursed Amount",
          value = textOutput("kpi_disbursed_amt"),
          showcase = shiny::icon("coins")
        ),
        bslib::value_box(
          title = "Avg Ticket Size",
          value = textOutput("kpi_ticket_size"),
          showcase = shiny::icon("ticket")
        )
      ),
      # Trend Chart
      bslib::card(
        bslib::card_header("Disbursement vs Target Trend"),
        bslib::card_body(plotly::plotlyOutput("disb_target_plot", height = "400px"))
      )
    )
  )
}