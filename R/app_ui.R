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
          width = 250,
          bslib::card_header("Filters"),
          selectInput("branch_filter", "Branch", 
                      choices = c("All", "Gulshan", "Dhanmondi", "Motijheel", "Chattogram", "Sylhet", "Khulna", "Rajshahi", "Mirpur"), 
                      selected = "All"),
          selectInput("sector_filter", "Sector", 
                      choices = c("All", "Manufacturing", "Trading", "Services", "Agro", "Textile", "Construction"), 
                      selected = "All")
        ),
        bslib::card(
          bslib::card_header("Application Flow (Sankey)"),
          bslib::card_body(networkD3::sankeyNetworkOutput("funnel_sankey", height = "350px"))
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
    )
  )
}