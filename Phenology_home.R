## NEMO - Phenology 
## 1 Import data from Access 
## 2 Make data frame using SQL (# Alternative 1)
## 3 Estimate  hatching dates +/- uncertainty
## 4 

# Install/load packages
install.packages("odbc") # contains drivers to connect to a database
install.packages("DBI") # contains functions for interacting with the database

library(odbc)
library(DBI)
library(tidyverse)
library(dplyr)
library(lubridate)

# Alternative to load packages
# Define required packages
required_packages <- c("odbc", "DBI", "tidyverse", "dplyr", "lubridate")

# Identify packages that are not yet installed
packages_to_install <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]

# Install missing packages
if (length(packages_to_install) > 0) {
  install.packages(packages_to_install)
}

# Load all required packages
lapply(required_packages, library, character.only = TRUE)


################################################################################
## 1 Import data from Access
################################################################################

# Directs to the place the database is stored
#dbname <- "N:/Midlertidig/Lea/NEMO/Spitsbergen_2024.mdb"


dbname <- "C:/Users/lea.lipphardt/Documents/NEMOx/Spitsbergen_2024.mdb"

# Connect to the Access database using ODBC
con <- dbConnect(odbc::odbc(), 
                 .connection_string = paste0("Driver={Microsoft Access Driver (*.mdb, *.accdb)};DBQ=", dbname))

## List tables in the database
#dbListTables(con)
#dbListFields(con, "NestContent")

################################################################################
## 2 make data frame using SQL # Alternative 1
################################################################################

query <- "
SELECT s.spcENG, n.Locality, n.Area, n.NestNumber, v.VisitDate, nc.NestContentText, v.NestClutch
FROM (((Visits AS v
INNER JOIN NestContent AS nc ON v.NestStatus = nc.NestContentID)
INNER JOIN Nest AS n ON n.NestUniqueID = v.NestUniqueID)
INNER JOIN Species AS s ON n.Species = s.EUnr)
"
df_selected <- dbGetQuery(con, query)

# View df_selected
head(df_selected)
str(df_selected)

## Close the connection
dbDisconnect(con) # disconnect after your work is done to free resources

################################################################################
## 3 Estimate  dates +/- uncertanty

# Filter for manual check
# Make a table with species, BreedingSeason, locality and the following information: 
# Get lastE and firstC
# Estimate hatcing date
# Estimate uncertainty

################################################################################
# Control (no need to run this section)
nrow(df_selected)

# Subset
#df_selected <- results[1:1000, ]

# Count the number of occurrences of each unique character in NestClutch
table(df_selected$NestClutch)

# Convert df_selected into a tibble and summarize with dplyr
df_selected %>%
  as_tibble() %>%
  count(NestClutch)

################################################################################
# Convert VisitDate to Date format if not already
df_selected$VisitDate <- as.Date(df_selected$VisitDate)

# Extract the BreedingSeason for each VisitDate
df_selected$BreedingSeason <- as.numeric(format(df_selected$VisitDate, "%Y"))

################################################################################
df_selected_BreedingSeason <- df_selected
# Subset the data for a specific BreedingSeason, specie, location
df_selected_BreedingSeason <- subset(df_selected, BreedingSeason == "2024")
#df_selected_specie <- subset(df_selected_BreedingSeason, spcENG == "Black-legged kittiwake")
#df_selected_location <- subset(df_selected_specie, Locality == "Ossian Sarsfjellet")

################################################################################
# SVARTHAMAREN
################################################################################
# The Breeding season will be YYYY for NestNumbers from Svalbard and YYYY/YYYY for Svarthamaren


# For Svarthamaren run the bellow to assign a specific breeding period
# Define the breeding season start and end dates relative to each BreedingSeason
df_selected$BreedingSeason <- ifelse(
  format(df_selected$VisitDate, "%m-%d") >= "11-01", 
  # If the VisitDate is in November or December, use current BreedingSeason/current BreedingSeason + 1
  paste0(df_selected$BreedingSeason, "/", df_selected$BreedingSeason + 1),
  ifelse(
    format(df_selected$VisitDate, "%m-%d") <= "02-29", 
    # If the VisitDate is in January or February, use previous BreedingSeason/current BreedingSeason
    paste0(df_selected$BreedingSeason - 1, "/", df_selected$BreedingSeason),
    NA # Otherwise, not in the breeding season
  )
)

################################################################################

filter_clutch_values <- function(df) {
  # Define regex patterns for different categories
  clutch_values_e <- "^([1-9][Ee]|[1-9][Ee],[1-9][Ee])$"
  clutch_values_c <- "^([1-9][Cc]|[1-9][Cc],[1-9][Cc])$"
  
  # Define valid clutch values for empty entries
  empty_clutch_values <- c("")
  
  # Initialize the Note column with empty strings
  df$Note <- ""
  
  # Iterate over unique NestNumbers and BreedingSeasons
  for (nest in unique(df$NestNumber)) {
    for (BreedingSeason in unique(df$BreedingSeason)) {
      # Subset the data for the current NestNumber and BreedingSeason
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, ]
      
      # Remove rows with NA values in NestClutch
      subset_df <- subset_df[!is.na(subset_df$NestClutch), ]
      
      # Check conditions using regex and append notes
      if (all(grepl(clutch_values_e, subset_df$NestClutch))) {
        df$Note[df$NestNumber == nest & df$BreedingSeason == BreedingSeason] <- "Only E-entries"
      } else if (all(grepl(clutch_values_c, subset_df$NestClutch))) {
        df$Note[df$NestNumber == nest & df$BreedingSeason == BreedingSeason] <- "Only C-entries"
      } else if (all(subset_df$NestClutch %in% empty_clutch_values)) {
        df$Note[df$NestNumber == nest & df$BreedingSeason == BreedingSeason] <- "Only empty-entries"
      }
    }
  }
  
  return(df)
}

# Apply the function to the dataset
df_selected_BreedingSeason <- filter_clutch_values(df_selected_BreedingSeason)

# View the result
head(df_selected_BreedingSeason)

################################################################################
# False_C and False_E
################################################################################

# Define regex patterns for clutch values
clutch_value_e <- "^([1-9][Ee]|[1-9][Ee],[1-9][Ee])$"  # Egg entries
clutch_value_c <- "^([1-9][Cc]|[1-9][Cc],[1-9][Cc])$"  # Chick entries

# Apply the logic to flag False_E for '1E' entries following a '1C' entry
df_selected_BreedingSeason <- df_selected_BreedingSeason %>%
  group_by(BreedingSeason, NestNumber) %>%
  arrange(VisitDate, .by_group = TRUE) %>%
  mutate(
    Note = case_when(
      grepl(clutch_value_e, NestClutch) & lag(grepl(clutch_value_c, NestClutch), default = FALSE) ~ "False_E",
      TRUE ~ Note # Retain existing notes for other cases
    )
  )


# Apply the logic to flag False_C for '1C' entries followed by two '1E' entries
df_selected_BreedingSeason <- df_selected_BreedingSeason %>%
  group_by(BreedingSeason, NestNumber) %>%
  arrange(VisitDate, .by_group = TRUE) %>%
  mutate(
    Note = case_when(
      grepl(clutch_value_c, NestClutch) & 
        lead(grepl(clutch_value_e, NestClutch), n = 1, default = FALSE) &
        lead(grepl(clutch_value_e, NestClutch), n = 2, default = FALSE) ~ "False_C",
      TRUE ~ Note # Retain existing notes for other cases
    )
  )


view(df_selected_BreedingSeason)

################################################################################
# Last_E 
# First_C

#  date 
# +/- uncertainty /  date accuracy 
################################################################################

# Find first visit with egg
find_first_E <- function(df) {
  clutch_values_e <- "^([1-9][Ee]|[1-9][Ee],[1-9][Ee])$"
  
  df$First_E <- as.Date(NA)
  
  for (nest in unique(df$NestNumber)) {
    for (BreedingSeason in unique(df$BreedingSeason)) {
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, ]
      subset_df$VisitDate <- as.Date(subset_df$VisitDate)
      
      matching_clutches <- subset_df[grepl(clutch_values_e, subset_df$NestClutch), ]
      
      if (nrow(matching_clutches) > 0) {
        first_entry <- matching_clutches[which.min(matching_clutches$VisitDate), ]
        df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, "First_E"] <- first_entry$VisitDate
      }
    }
  }
  
  return(df)
}

# Find last visit with egg
find_last_E <- function(df) {
  clutch_values_e <- "^([1-9][Ee]|[1-9][Ee],[1-9][Ee])$"
  
  df$Last_E <- as.Date(NA)
  
  for (nest in unique(df$NestNumber)) {
    for (BreedingSeason in unique(df$BreedingSeason)) {
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, ]
      subset_df$VisitDate <- as.Date(subset_df$VisitDate)
      
      matching_clutches <- subset_df[grepl(clutch_values_e, subset_df$NestClutch), ]
      
      if (nrow(matching_clutches) > 0) {
        last_entry <- matching_clutches[which.max(matching_clutches$VisitDate), ]
        df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, "Last_E"] <- last_entry$VisitDate
      }
    }
  }
  
  return(df)
}

# Find first visit with chick
find_first_C <- function(df) {
  clutch_values_combined <- "^([1-9][EeCc]|[1-9][EeCc],[1-9][EeCc])$"
  
  df$First_C <- as.Date(NA)
  
  for (nest in unique(df$NestNumber)) {
    for (BreedingSeason in unique(df$BreedingSeason)) {
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, ]
      subset_df$VisitDate <- as.Date(subset_df$VisitDate)
      
      matching_clutches <- subset_df[grepl(clutch_values_combined, subset_df$NestClutch), ]
      
      if (nrow(matching_clutches) > 0) {
        first_entry <- matching_clutches[which.min(matching_clutches$VisitDate), ]
        df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, "First_C"] <- first_entry$VisitDate
      }
    }
  }
  
  return(df)
}

# Find last visit with chick
find_last_C <- function(df) {
  clutch_values_combined <- "^([1-9][EeCc]|[1-9][EeCc],[1-9][EeCc])$"
  
  df$Last_C <- as.Date(NA)
  
  for (nest in unique(df$NestNumber)) {
    for (BreedingSeason in unique(df$BreedingSeason)) {
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, ]
      subset_df$VisitDate <- as.Date(subset_df$VisitDate)
      
      matching_clutches <- subset_df[grepl(clutch_values_combined, subset_df$NestClutch), ]
      
      if (nrow(matching_clutches) > 0) {
        last_entry <- matching_clutches[which.max(matching_clutches$VisitDate), ]
        df[df$NestNumber == nest & df$BreedingSeason == BreedingSeason, "Last_C"] <- last_entry$VisitDate
      }
    }
  }
  
  return(df)
}

find_last_visit <- function(df) {
  # Create new columns initialized with NA
  df$LastOfVisitDate <- as.Date(NA)
  df$LastStatus_All <- NA
  
  # Iterate over unique NestNumbers and Years
  for (nest in unique(df$NestNumber)) {
    for (breedingseason in unique(df$BreedingSeason)) {
      # Subset the data for the current NestNumber and Year
      subset_df <- df[df$NestNumber == nest & df$BreedingSeason == breedingseason, ]
      
      # Find the last visit based on VisitDate
      if (nrow(subset_df) > 0) {
        last_entry <- subset_df[which.max(subset_df$VisitDate), ]
        
        # Assign the Last_Visit and LastStatus_All values to all rows for this NestNumber and Year
        df[df$NestNumber == nest & df$BreedingSeason == breedingseason, "LastOfVisitDate"] <- last_entry$VisitDate
        df[df$NestNumber == nest & df$BreedingSeason == breedingseason, "LastStatus_All"] <- last_entry$NestContentText
      }
    }
  }
  
  return(df)
}


phenology <- df_selected_BreedingSeason %>%
  find_first_E() %>%
  find_last_E() %>%
  find_first_C() %>%
  find_last_C() %>%
  find_last_visit()

################################################################################
# Initialize new columns for hatching date, its accuracy, and hatching success
phenology <- phenology %>%
  mutate(
    # Calculate Hatching_date as the mean of Last_E and First_C
    Hatching_date = if_else(
      !is.na(Last_E) & !is.na(First_C),
      as.Date((as.numeric(Last_E) + as.numeric(First_C)) / 2, origin = "1970-01-01"),
      NA_Date_
    ),
    
    # Calculate Hatching_date_accuracy as half the difference in days
    Hatching_date_accuracy = if_else(
      !is.na(Last_E) & !is.na(First_C),
      (as.numeric(First_C - Last_E) / 2),
      NA_real_
    ),
    
    # Set June 1st of the given BreedingSeason as Julian Date 1
    JulianHatchingDate = if_else(
      !is.na(Hatching_date),
      {
        # Extract the BreedingSeason from the Hatching_date
        BreedingSeason_start <- as.Date(paste0(format(Hatching_date, "%Y"), "-06-01"))
        as.numeric(Hatching_date - BreedingSeason_start + 1) # Julian Date calculation
      },
      NA_real_
    ),
    
    # Assign HatchingSuccess as 1 if Hatching_date is not NA, otherwise NA
    HatchingSuccess = if_else(
      !is.na(Hatching_date),
      1,
      NA_real_
    )
  )

# After transformations, clean the data to keep only one row per NestNumber per BreedingSeason.
phenology_clean <- phenology %>%
  group_by(NestNumber, BreedingSeason) %>%
  slice(1) %>%  # Keep the first entry for each NestNumber and BreedingSeason
  ungroup()

################################################################################
# Get the number of days a chick/chicks are present in the Nest 

NbChickPresence <- function(df) {
  # Ensure First_C, Last_C, Hatching_date, and LastOfVisitDate are Date objects
  df <- df %>%
    rowwise() %>%
    mutate(
      First_C = as.Date(First_C),
      Last_C = as.Date(Last_C),
      Hatching_date = as.Date(Hatching_date),
      LastOfVisitDate = as.Date(LastOfVisitDate)
    )
  
  # Group by NestNumber and BreedingSeason and calculate required metrics
  df <- df %>%
    group_by(NestNumber, BreedingSeason) %>%
    mutate(
      NbChickPresence = ifelse(!is.na(First_C) & !is.na(Last_C), as.numeric(Last_C - First_C + 1), NA),
      NbDays_ChickPresence_FromHD = ifelse(!is.na(Hatching_date) & !is.na(Last_C), as.numeric(Last_C - Hatching_date + 1), NA),
      Diff_LastVisitWithChick_LastVisit = ifelse(!is.na(Last_C) & !is.na(LastOfVisitDate), as.numeric(LastOfVisitDate - Last_C + 1), NA)
    ) %>%
    ungroup() # Ungroup to finalize the operation
  
  return(df)
}

# Apply the function
phenology <- NbChickPresence(phenology_clean)

################################################################################
# 
phenology <- phenology %>%
  rowwise() %>%
  mutate(
    Note = if_else(Hatching_date_accuracy > 5, "Hatching_date_accuracy > 5", Note),
    Note = if_else(NbDays_ChickPresence_FromHD < 15, "Entries for NbDays_ChickPresence_FromHD < 15", Note),
    ChickSurvival = if_else(Hatching_date_accuracy < 5 & any(NbDays_ChickPresence_FromHD > 15), 1, 0),
    BreedingSuccess = if_else(
      spcENG == "Glaucous gull" & ChickSurvival == 1, 1,  # Exception for Glaucous gull
      if_else(HatchingSuccess == 1 & ChickSurvival == 1, 1, 0)  # Regular condition
    )
  )

# Select the columns of interest
phenology <- phenology %>%
  select(spcENG, Locality, Area, NestNumber, BreedingSeason, Note, Last_E, First_C, Last_C, NbChickPresence, LastOfVisitDate, LastStatus_All, Hatching_date, JulianHatchingDate, Hatching_date_accuracy, NbDays_ChickPresence_FromHD, Diff_LastVisitWithChick_LastVisit, HatchingSuccess, ChickSurvival, BreedingSuccess)

view(phenology)

################################################################################

################################################################################

# False E
egg_clutch_values <- c("1E", "2E", "3E", "1e", "2e", "3e", "1e,1E", "2e,2E", "3e,3E")
chick_clutch_values <- c("1C", "2C", "3C", "1c", "2c", "3c", "1c,1C", "2c,2C", "3c,3C")

df <- df_selected_BreedingSeason %>%
  group_by(NestNumber, BreedingSeason) %>%
  mutate(
    flag = if_else(
      (NestClutch %in% egg_clutch_values) & 
        (lag(NestClutch) %in% chick_clutch_values) & 
        (lag(NestClutch, 2) %in% chick_clutch_values) &
        (lag(VisitDate) < VisitDate) &
        (lag(VisitDate, 2) < VisitDate), 
      FALSE,
      TRUE
    )
  ) %>%
  filter(flag) %>%
  ungroup()
view(df)

