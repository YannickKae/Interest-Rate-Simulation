# Set locale to use dot as decimal separator
Sys.setlocale("LC_NUMERIC", "C")

# Install required packages if not already installed
if (!require(shiny)) install.packages("shiny")
if (!require(ggplot2)) install.packages("ggplot2")
if (!require(shinythemes)) install.packages("shinythemes")
if (!require(shinybusy)) install.packages("shinybusy")
if (!require(latex2exp)) install.packages("latex2exp")
if (!require(tidyr)) install.packages("tidyr")

library(shiny)
library(ggplot2)
library(shinythemes)
library(shinybusy)
library(latex2exp)
library(tidyr)

# Define UI
ui <- fluidPage(
  theme = shinytheme("cyborg"),  # Set dark theme
  add_busy_spinner(spin = "fading-circle"),  # Add loading spinner
  titlePanel("Interest Rate Simulation"),
  sidebarLayout(
    sidebarPanel(
      selectInput("equilibriumType", "Equilibrium Type:", choices = c("Constant", "Dynamic")),
      conditionalPanel(
        condition = "input.equilibriumType == 'Constant'",
        numericInput("r_bar", "Constant long-term Equilibrium:", value = 0.05, min = 0, step = 0.01)
      ),
      conditionalPanel(
        condition = "input.equilibriumType == 'Dynamic'",
        textInput("thetaFunction", "Dynamic long-term Equilibrium:", value = "0.1 * sin(t)")
      ),
      numericInput("alpha", "Speed of Mean Reversion:", value = 0.1, min = 0, step = 0.01),
      selectInput("volatilityType", "Volatility Term:", choices = c("CEV", "Dynamic")),
      conditionalPanel(
        condition = "input.volatilityType == 'CEV'",
        numericInput("sigma", "Volatility:", value = 0.02, min = 0, step = 0.01),
        numericInput("gamma", "Elasticity of Volatility:", value = 0.5, min = 0, step = 0.01)
      ),
      conditionalPanel(
        condition = "input.volatilityType == 'Dynamic'",
        textInput("sigmaFunction", "Dynamic Volatility Function:", value = "0.02 * sin(t)")
      ),
      numericInput("r0", "Initial Rate:", value = 0.03, min = 0, step = 0.01),
      numericInput("T", "Time Horizon:", value = 1, min = 0, step = 0.1),
      numericInput("steps", "Number of Discrete Steps:", value = 1000, min = 1, step = 1),
      numericInput("nPaths", "Number of Simulations:", value = 100, min = 1, step = 1),
      numericInput("confInterval", "Confidence Interval:", value = 0.95, min = 0, max = 1, step = 0.01),
      actionButton("simulate", "Simulate"),
      downloadButton("downloadData", "Download Simulated Paths"),
      tags$hr(),
      uiOutput("sdeDisplay")
    ),
    mainPanel(
      plotOutput("interestRatePlot"),
      plotOutput("summaryPlot"),
      verbatimTextOutput("errorOutput")
    )
  )
)

# Define server logic
server <- function(input, output, session) {
  observe({
    sdeText <- if (input$equilibriumType == "Constant") {
      if (input$volatilityType == "CEV") {
        '$$dr = -\\alpha (r - \\bar{r}) dt + \\sigma r^{\\gamma} dW(t)$$'
      } else {
        '$$dr = -\\alpha (r - \\bar{r}) dt + \\sigma(t) dW(t)$$'
      }
    } else {
      if (input$volatilityType == "CEV") {
        '$$dr = -\\alpha (r - \\theta(t)) dt + \\sigma r^{\\gamma} dW(t)$$'
      } else {
        '$$dr = -\\alpha (r - \\theta(t)) dt + \\sigma(t) dW(t)$$'
      }
    }
    
    sdeSubText <- if (input$equilibriumType == "Constant") {
      paste0('$$dr = -', input$alpha, ' (r - ', input$r_bar, ') dt + ', input$sigma, ' r^{', input$gamma, '} dW(t)$$')
    } else {
      thetaFunction <- gsub("t", "t", input$thetaFunction)
      if (input$volatilityType == "CEV") {
        paste0('$$dr = -', input$alpha, ' (r - (', thetaFunction, ')) dt + ', input$sigma, ' r^{', input$gamma, '} dW(t)$$')
      } else {
        sigmaFunction <- gsub("t", "t", input$sigmaFunction)
        paste0('$$dr = -', input$alpha, ' (r - (', thetaFunction, ')) dt + (', sigmaFunction, ') dW(t)$$')
      }
    }
    
    output$sdeDisplay <- renderUI({
      withMathJax(HTML(paste(sdeText, sdeSubText, sep = "<br>")))
    })
  })
  
  observeEvent(input$simulate, {
    show_modal_spinner(color = "white") # show the modal window
    output$errorOutput <- renderText({ "" })  # Clear previous errors
    tryCatch({
      alpha <- input$alpha
      sigma <- input$sigma
      gamma <- input$gamma
      r0 <- input$r0
      T <- input$T
      steps <- input$steps
      nPaths <- input$nPaths
      confInterval <- input$confInterval
      
      dt <- T / steps
      time <- seq(0, T, by = dt)
      
      if (input$equilibriumType == "Constant") {
        r_bar <- input$r_bar
        theta <- rep(r_bar, length(time))
      } else {
        thetaFunction <- input$thetaFunction
        theta <- eval(parse(text = paste0("function(t) {", thetaFunction, "}")))(time)
      }
      
      if (input$volatilityType == "Dynamic") {
        sigmaFunction <- input$sigmaFunction
        sigma <- eval(parse(text = paste0("function(t) {", sigmaFunction, "}")))(time)
      }
      
      all_paths <- matrix(0, nrow = length(time), ncol = nPaths)
      
      for (j in 1:nPaths) {
        r <- numeric(length = length(time))
        r[1] <- r0
        
        for (i in 2:length(time)) {
          dW <- rnorm(1, mean = 0, sd = sqrt(dt))
          if (input$volatilityType == "CEV") {
            if (gamma != 0 && gamma != floor(gamma) && gamma %% 2 != 1) {
              r_prev <- max(r[i-1], .Machine$double.eps)
              dr <- -alpha * (r[i-1] - theta[i-1]) * dt + input$sigma * r_prev^gamma * dW
              r[i] <- max(r[i-1] + dr, .Machine$double.eps)
            } else {
              r_prev <- r[i-1]
              dr <- -alpha * (r[i-1] - theta[i-1]) * dt + input$sigma * r_prev^gamma * dW
              r[i] <- r[i-1] + dr
            }
          } else {
            dr <- -alpha * (r[i-1] - theta[i-1]) * dt + sigma[i-1] * dW
            r[i] <- r[i-1] + dr
          }
        }
        
        all_paths[, j] <- r
      }
      
      all_paths_df <- data.frame(time = time, all_paths)
      colnames(all_paths_df) <- c("time", paste0("path_", 1:nPaths))
      
      output$interestRatePlot <- renderPlot({
        all_paths_long <- gather(all_paths_df, key = "path", value = "rate", -time)
        ggplot(all_paths_long, aes(x = time, y = rate, color = path)) +
          geom_line() +
          labs(title = "Simulated Rates", x = "Time", y = "Interest Rate") +
          scale_color_manual(values = colorRampPalette(c("darkred", "red", "lightcoral"))(nPaths)) +
          theme_minimal() +
          theme(legend.position = "none")  # Hide legend
      })
      
      # Calculate median and confidence intervals
      lower_quantile <- (1 - confInterval) / 2
      upper_quantile <- 1 - lower_quantile
      summary_stats <- data.frame(
        time = time,
        median = apply(all_paths, 1, median),
        p_lower = apply(all_paths, 1, quantile, probs = lower_quantile),
        p_upper = apply(all_paths, 1, quantile, probs = upper_quantile)
      )
      
      output$summaryPlot <- renderPlot({
        ggplot(summary_stats, aes(x = time)) +
          geom_line(aes(y = median, color = "Median")) +
          geom_ribbon(aes(ymin = p_lower, ymax = p_upper), alpha = 0.2, fill = "darkred") +
          labs(title = "Median and Confidence Interval", x = "Time", y = "Interest Rate") +
          theme_minimal() +
          theme(legend.position = "none")  # Hide legend
      })
      
      # Create the download handler
      output$downloadData <- downloadHandler(
        filename = function() {
          paste("simulated_paths", ".csv", sep = "")
        },
        content = function(file) {
          write.table(all_paths_df, file, row.names = FALSE, col.names = TRUE, sep = ",", dec = ".")
        }
      )
      
      remove_modal_spinner() # remove it when done
    }, error = function(e) {
      remove_modal_spinner() # remove spinner on error
      output$errorOutput <- renderText({
        paste("An error occurred during simulation. Please check your inputs and try again. If the problem persists, contact Twitter user @YannickKae (https://x.com/YannickKae). Error details:", e$message)
      })
    })
  })
}

# Run the application 
shinyApp(ui = ui, server = server)
        