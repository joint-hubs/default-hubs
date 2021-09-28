jtRaw <- function(file = input$raw_file){
  #' Function to read the data from the file / only shiny
  #'
  #' @param file list with stores datapath element containing the path to the file
  #'
  #'
  #' @return Returns table with original data structure

  ext <- tools::file_ext(file$datapath)
  req(file)
  validate(need(ext == "csv", "Please upload a csv file"))

  table <- read.csv(file$datapath,
                   stringsAsFactors = FALSE) %>%
    janitor::clean_names()

  return(table)
}

jtGetLotto <- function(path = "http://www.mbnet.com.pl/dl.txt"){
  #' Function to read the data from the file / only shiny
  #' 
  #' @param file web page storing results
  #'
  #' @return Returns table with winning numbers with dates
  
  data <- read.table(path,
                         sep = " ", stringsAsFactors = FALSE) %>% 
    setNames(c("id", "date", "numbers")) %>% 
    mutate(date = as.Date(paste(
      substr(date, 7, str_length(date)),
      substr(date, 4, 5),
      substr(date, 1, 2),
      sep = "-"))) %>% 
    separate(numbers, paste0("number", 1:6),
             sep = ",")
  
  message("Data collected from: ", path)
  
  data <- data %>% 
    mutate_at(vars(-date), as.numeric) %>% 
    mutate(sum = round(number1 + number2 + number3 + number4 + 
                         number5 + number6),
           sum_of_squares =  round(number1^2 + number2^2 + number3^2 +
                                     number4^2 + number5^2 + number6^2)) %>% 
    mutate(distance_index = round(sum_of_squares / sum, 2)) 
  
  helper <- list()
  helper$prob_tables <- data %>% 
    select(number1, 
           number2,
           number3,
           number4,
           number5,
           number6) %>% 
    pivot_longer(everything()) %>% 
    count(value) %>% 
    rename(Number = value,
           `Times selected` = n) %>% 
    mutate(Probabilty = round(`Times selected`/sum(`Times selected`)*100,4))
  
  return(list(
    data = data,
    helper = helper
  ))
}

jtClean <- function(table, date, sales, product, min_date, max_date){
  #' Function to recognize and set data structure
  #' 
  #' @param table whole data
  #' @param date string with the original name of the column containing dates
  #' @param sales string with the original name of the column containing sales
  #' @param product string with the original name of the column containing product names
  #' 
  #' @return Returns table with proper data structure
  
  if(!product){
    table <- table %>% 
      rename(Data = parse_character(date),
             Sprzedaz = parse_character(sales)) %>% 
      mutate(Data = anydate(Data)) %>% 
      filter(Data >= anydate(min_date),
             Data <= anydate(max_date))
  }else{
    table <- table %>% 
      rename(Data = parse_character(date),
             Sprzedaz = parse_character(sales),
             `Nazwa produktu` = parse_character(product)) %>% 
      mutate(Data = anydate(Data)) %>% 
      filter(Data >= anydate(min_date),
             Data <= anydate(max_date))
  }

  return(table)
}

jtGetDesiredLotto <- function(table){
  data <- list()
  data$clean_filtered <- table %>% 
    filter(distance_index >= quantile(distance_index, .2) & distance_index <= quantile(distance_index, .8)) %>% 
    filter(sum_of_squares >= quantile(sum_of_squares, .2) & sum_of_squares <= quantile(sum_of_squares, .8)) %>% 
    filter(sum >= quantile(sum, .2) & sum <= quantile(sum, .8))

  data$random_pos1 <- quantile(data$clean_filtered$number1, .8)
  data$random_pos2 <- quantile(data$clean_filtered$number2, .8)
  data$random_pos3 <- quantile(data$clean_filtered$number3, .8)
  data$random_pos4 <- quantile(data$clean_filtered$number4, .2)
  data$random_pos5 <- quantile(data$clean_filtered$number5, .2)
  data$random_pos6 <- quantile(data$clean_filtered$number6, .2)
  
  data$clean_filtered_ids <- data$clean_filtered %>% 
    filter(number1 <= data$random_pos1,
           number2 <= data$random_pos2,
           number3 <= data$random_pos3,
           number4 >= data$random_pos4,
           number5 >= data$random_pos5,
           number6 >= data$random_pos6) %>% 
    pull(id)
  
  return(data$clean_filtered_ids)
}

  

jtEnhancets <- function(table,
                        value_name = "xyz"){
  
  table <- table %>% 
    rename(value_name = parse_character(value_name)) %>% 
    mutate(lower1 = lag(value_name, n = 5) - lag(value_name, n = 1),
           lower2 = lag(value_name, n = 13) - lag(value_name, n = 5),
           higher1 = lag(value_name, n = 1) - lag(value_name, n = 5),
           higher2 = lag(value_name, n = 5) - lag(value_name, n = 13),
           h1 = lag(value_name) + higher1,
           l1 = lag(value_name) + lower1,
           h2 = lag(value_name) + higher2,
           l2 = lag(value_name) + lower2,
           explanator_h1l2 = round(sqrt(h1*l2), 4),
           explanator_h1h2 = round(sqrt(h1*h2), 4),
           explanator_h1l1 = round(sqrt(h1*l1), 4),
           explanator_h1h1 = round(sqrt(h1*h1), 4),
           explanator_l1l2 = round(sqrt(l1*l2), 4),
           explanator_l1h2 = round(sqrt(l1*h2), 4),
           explanator_l1l1 = round(sqrt(l1*l1), 4)) %>% 
    ungroup() %>% 
    select(-lower1, -lower2, -higher1, -higher2,
           -h1, -l1, -h2, -l2)
  
  for (i in 2:6) {
    col_name <- paste0("avg_", str_sub(paste0(0, i),-2,-1))
    table <- table %>%
      mutate(!!col_name := dplyr::lag(RcppRoll::roll_meanr(sales, i), 1))
  }
  
  return(table)
} 

jtEnhanceLotto <- function(table){
  
  model <- list()
  model$raw <- table %>% 
    select(-id) 
  
  model$raw[nrow(model$raw)+1,] <- NA
  model$raw <- model$raw %>% 
    mutate(date = ifelse(!is.na(date), 
                         date,
                         as.Date("2021-02-11")),
           date = anytime::anydate(date))
  
  model$data_full <- model$raw %>% 
    tk_augment_timeseries_signature(.date_var = date) %>% 
    select(-half, -hour, -minute, -second, -hour12, -am.pm, -week2, -mday, -week.iso,
           -wday.xts, -qday, -yday, -index.num, -year.iso, -month.xts,
           -wday.lbl, -month.lbl, -date, -diff) 
  
  model$data <- model$data_full %>% 
    filter(complete.cases(.))
  
  return(model)
}


jtSeasons <- function(table){
  table <- table %>% 
    group_by(year) %>% 
    mutate(year_mean = mean(sales, na.rm = TRUE)) %>% 
    ungroup() %>% 
    group_by(month.lbl) %>% 
    summarise(monthly_sales_mean = round(mean(sales, na.rm = TRUE), 2),
              years = n(),
             total_value = sum(sales, na.rm = TRUE),
              standard_deviation = round(mean((sales / year_mean - 1), na.rm = TRUE)*100, 2),
              .groups = "drop") %>% 
    rename(month = month.lbl)
  return(table)
}


jtXGBoost.lotto <- function(model, dependent_var){
  
  lotto <- read.csv("lotto.csv")
  set.seed(sample(10000, 1))
  xgbData <- list()
  xgbData$full_data <- model
  xgbData$train_base <- model %>%
    filter(complete.cases(.)) %>% 
    select(-id)
  
  xgbData$trainMatrix <-
    Matrix::sparse.model.matrix(
      as.formula(paste(parse_character(dependent_var), "~ .")),
      data = xgbData$train_base,
      sparse = FALSE,
      sci = FALSE
    )
  
  xgbData$label <- xgbData$train_base %>% 
    select(parse_character(dependent_var)) %>% 
    pull()
  
  xgbData$trainDMatrix <- xgboost::xgb.DMatrix(data = xgbData$trainMatrix,
                                               label = xgbData$label)
  
  # prepare model
  xgbData$params <- list(booster = "dart",
                         objective = "reg:linear",
                         eta = 0.05,
                         gamma = 0.2,
                         sampling_method = "gradient_based",
                         tree_method = "exact",
                         max_delta_step = 7,
                         max_depth = 7)
  
  
  xgbData$xgb.tab <- xgboost::xgb.cv(data = xgbData$trainDMatrix,
                                     param = xgbData$params,
                                     maximize = FALSE,
                                     evaluation = "rmse",
                                     nrounds = 13,
                                     nthreads = 3,
                                     nfold = 5,
                                     early_stopping_round = 2)
  xgbData$num_iterations <- xgbData$xgb.tab$best_iteration
  
  # train model
  xgbData$model <- xgboost::xgb.train(data = xgbData$trainDMatrix,
                                      maximize = FALSE,
                                      evaluation = 'rmse',
                                      nrounds = xgbData$num_iterations)
  
  # forecast
  xgbData$forecasts <- data.frame()
  
  for (i in which(is.na(xgbData$full_data$sum))){
    
    test_xgb <- xgbData$full_data[i, ] 
    test_lotto <- lotto[sample(1:nrow(lotto), 1),]
    
    test_xgb <- test_xgb %>%
      select(-id) %>% 
      mutate_at(vars(parse_character(dependent_var)), function(x) 0) %>% 
      mutate(sum = test_lotto$sum,
             sum_of_squares = test_lotto$sum_of_squares,
             distance_index = test_lotto$distance_index)
    
    testMatrix <- Matrix::sparse.model.matrix(as.formula(paste(parse_character(dependent_var), "~ .")),
                                              data = test_xgb,
                                              sparse = FALSE,
                                              sci = FALSE
    )
    
    prediction <- predict(xgbData$model, testMatrix)
    
    test_xgb <- test_xgb %>%
      mutate_at(vars(parse_character(dependent_var)), function(x) round(prediction))
    
    xgbData$forecasts <- rbind(xgbData$forecasts, test_xgb)
  }
  
  return(xgbData)
}


predictLotto <- function(data){

  
  model1 <- data %>% 
    select(-number2, -number3, -number4, 
           -number5, -number6)
  result1 <- jtXGBoost.lotto(model1, "number1")$forecasts

  message(paste("Number 1 predicted", result1$number1))
  
  model2 <- data %>% 
    select(-number3, -number4, 
           -number5, -number6) %>% 
    mutate(number1 = ifelse(is.na(number1),
                            result1$number1,
                            number1))
  result2 <- jtXGBoost.lotto(model2, "number2")$forecasts
  message(paste("Number 2 predicted", result2$number2))
  
  model3 <- data %>% 
    select(-number4, 
           -number5, -number6) %>% 
    mutate(number1 = ifelse(is.na(number1),
                            result1$number1,
                            number1),
           number2 = ifelse(is.na(number2),
                            result2$number2,
                            number2))
  result3 <- jtXGBoost.lotto(model3, "number3")$forecasts
  message(paste("Number 3 predicted", result3$number3))
  
  model4 <- data %>% 
    select(-number5, -number6) %>% 
    mutate(number1 = ifelse(is.na(number1),
                            result1$number1,
                            number1),
           number2 = ifelse(is.na(number2),
                            result2$number2,
                            number2),
           number3 = ifelse(is.na(number3),
                            result3$number3,
                            number3))
  result4 <- jtXGBoost.lotto(model4, "number4")$forecasts
  message(paste("Number 4 predicted", result4$number4))
  
  model5 <- data %>% 
    select(-number6) %>% 
    mutate(number1 = ifelse(is.na(number1),
                            result1$number1,
                            number1),
           number2 = ifelse(is.na(number2),
                            result2$number2,
                            number2),
           number3 = ifelse(is.na(number3),
                            result3$number3,
                            number3),
           number4 = ifelse(is.na(number4),
                            result4$number4,
                            number4))
  result5 <- jtXGBoost.lotto(model5, "number5")$forecasts
  message(paste("Number 5 predicted", result5$number5))
  
  model6 <- data %>%  
    mutate(number1 = ifelse(is.na(number1),
                            result1$number1,
                            number1),
           number2 = ifelse(is.na(number2),
                            result2$number2,
                            number2),
           number3 = ifelse(is.na(number3),
                            result3$number3,
                            number3),
           number4 = ifelse(is.na(number4),
                            result4$number4,
                            number4),
           number5 = ifelse(is.na(number5),
                            result5$number5,
                            number5))
  result6 <- jtXGBoost.lotto(model6, "number6")$forecasts %>% 
    mutate(number6 = ifelse(number6 > 49, 49, number6))
  message(paste("Number 6 predicted", result6$number6))
  
  return(result6)
  
}


jtTheme <- function(base_size = 13,
                    base_family = "", 
                    base_line_size = base_size/20, 
                    base_rect_size = base_size/20) {
  theme_light(
    base_size = base_size, 
    base_family = base_family, 
    base_line_size = base_line_size, 
    base_rect_size = base_rect_size) +
    theme(panel.background = element_rect(fill = "#14113D", 
                                          colour = "#14113D"), 
          plot.background = element_rect(fill = "#14113D", 
                                         colour = "#14113D"),
          panel.border = element_rect(fill = NA, colour = NA), 
          panel.grid = element_line(colour = "#D9D9D9"), 
          panel.grid.minor = element_line(size = rel(0.5)), 
          strip.background = element_rect(fill = "#D9D9D9", 
                                          colour = "#D9D9D9"), 
          title = element_text(color = "329E99",
                               family = "Titillium Web"),
          legend.key = element_rect(fill = "#14113D", colour = NA),
          axis.title.x = element_text(color = "#329E99", 
                                      size = base_size, 
                                      family = base_family, 
                                      face = "bold"),
          axis.title.y = element_text(color = "#329E99", 
                                      size = base_size, 
                                      family = base_family, 
                                      face = "bold"),
          axis.text.x = element_text(color = "#329E99", 
                                     size = base_size, 
                                     family = base_family, 
                                     face = "bold"),
          axis.text.y = element_text(color = "#329E99", 
                                     size = base_size, 
                                     family = base_family, 
                                     face = "bold"),
          legend.background = element_rect(fill = "#14113D",
                                           color = "#071561"),
          legend.text = element_text(color = "#329E99"),
          complete = TRUE
    )
}

jtCleanTweetText <- function(text){

  # Set the text to lowercase
  text <- tolower(text)
  # Remove mentions, urls, emojis, numbers, punctuations, etc.
  text <- gsub("@\\w+", "", text)
  text <- gsub("https?://.+", "", text)
  text <- gsub("\\d+\\w*\\d*", "", text)
  text <- gsub("#\\w+", "", text)
  text <- gsub("[^\x01-\x7F]", "", text)
  text <- gsub("[[:punct:]]", " ", text)
  # Remove spaces and newlines
  text <- gsub("\n", " ", text)
  text <- gsub("^\\s+", "", text)
  text <- gsub("\\s+$", "", text)
  text <- gsub("[ |\t]+", " ", text)
  text <- str_remove_all(text, "rt ")
  
  return(text)
}

