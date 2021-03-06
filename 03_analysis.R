# Copyright 2016 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.

# Spatial packages
library(rgeos)
library(raster)
library(bcmaps)

# data manipulation packages
library(dplyr) # summarizing data frames
library(tidyr) # for 'complete' function
library(readr)

## Load some miscellaneous functions we need
source("fun.R")

m_to_ha <- function(x) x * 1e-4

## Load the cleanup up data from 02_clean.R, saving the names so we don't re-save them later
cleaned_prot_areas_objs <- load("tmp/prot_areas_clean.rda")
cleaned_ecoreg_objs <- load("tmp/ecoregions_clean.rda")
cleaned_bec_objs <- load("tmp/bec_clean.rda")

reg_int_bec_summary <- read.csv("data/reg_interests_bec_summary.csv", stringsAsFactors = FALSE)
reg_int_ecoreg_summary <- read.csv("data/reg_interests_ecoreg_summary_year.csv", stringsAsFactors = FALSE)
bc_reg_int_summary <- read_csv("data/bc_reg_int_summary.csv", col_types = "cdcci")

# Terrestrial Ecoregion analysis -----------------------------------------------

## Intersect ecoregions with protected areas
prot_areas_eco_t <- raster::intersect(ecoregions_t, prot_areas_agg)
prot_areas_eco_t <- rgeos::createSPComment(prot_areas_eco_t) # Ensure polygon holes are properly identified

## Calculate size of protected areas in each ecoregion
prot_areas_eco_t$prot_area <- rgeos::gArea(prot_areas_eco_t, byid = TRUE)

## Summarize amount of area protected in each region each year
prot_areas_eco_t_summary_by_year <- prot_areas_eco_t@data %>%
  filter(prot_date > 0) %>%
  complete(nesting(CRGNNM, CRGNCD, area), prot_date, fill = list(prot_area = 0)) %>%
  group_by(ecoregion = CRGNNM, ecoregion_code = CRGNCD, prot_date) %>%
  summarise(ecoregion_area = min(area),
            tot_protected = sum(prot_area)) %>%
  ungroup() %>%
  left_join(select(reg_int_ecoreg_summary, ecoregion_code, prot_date, tot_protected_overlaps_removed),
            by = c("ecoregion_code", "prot_date")) %>%
  mutate(tot_protected_overlaps_removed = ifelse(is.na(tot_protected_overlaps_removed),
                                                 0, tot_protected_overlaps_removed),
         tot_protected = (tot_protected + tot_protected_overlaps_removed),
         percent_protected = tot_protected / ecoregion_area * 100) %>%
  select(-tot_protected_overlaps_removed)


## Provincial summary of protected areas by year
prot_areas_bc_t_summary_by_year <- prot_areas_eco_t_summary_by_year %>%
  group_by(prot_date) %>%
  summarise(ecoregion = "British Columbia",
            ecoregion_code = "BC",
            ecoregion_area = sum(ecoregion_area),
            tot_protected = sum(tot_protected),
            percent_protected = tot_protected / ecoregion_area * 100)

## Calculate cumulative amound and percent protected over time, then
## combine provincial and ecoregional trend summaries
cum_summary_t_eco <- prot_areas_eco_t_summary_by_year %>%
  group_by(ecoregion, ecoregion_code) %>%
  arrange(prot_date) %>%
  mutate(cum_area_protected = cumsum(tot_protected),
         cum_percent_protected = cumsum(percent_protected),
         type = "All conservation lands",
         prot_date_full = paste0(prot_date, "-01-01")) %>%
  filter(!is.na(cum_area_protected)) %>%
  ungroup() %>%
  mutate(ecoregion = tools::toTitleCase(tolower(ecoregion)))

cum_summary_t_bc <- prot_areas_bc_t_summary_by_year %>%
  arrange(prot_date) %>%
  mutate(cum_area_protected = cumsum(tot_protected),
         cum_percent_protected = cumsum(percent_protected),
         type = "All conservation lands",
         prot_date_full = paste0(prot_date, "-01-01")) %>%
  filter(!is.na(cum_area_protected)) %>%
  ungroup() %>%
  mutate(ecoregion = tools::toTitleCase(tolower(ecoregion)))

cum_summary_t <- bind_rows(cum_summary_t_eco, cum_summary_t_bc)

# Marine Ecoregion analysis ----------------------------------------------------

## Intersect ecoregions with protected areas
prot_areas_eco_m <- raster::intersect(ecoregions_m, prot_areas_agg)
prot_areas_eco_m <- rgeos::createSPComment(prot_areas_eco_m) # Ensure polygon holes are properly identified

## Calculate size of protected areas in each ecoregion
prot_areas_eco_m$prot_area <- rgeos::gArea(prot_areas_eco_m, byid = TRUE)

## Summarize amount of area protected in each region each year, adding zeros for
## the ecoregions that have no protection
missing_m_ecoregions <- ecoregions_m@data %>%
  select(CRGNNM, CRGNCD, area) %>%
  filter(CRGNCD %in% c("TPC", "SBC")) %>%
  mutate(prot_date = max(prot_areas_eco_m$prot_date), prot_area = 0)

prot_areas_eco_m_summary_by_year <- prot_areas_eco_m@data %>%
  filter(prot_date > 0) %>%
  bind_rows(missing_m_ecoregions) %>%
  complete(nesting(CRGNNM, CRGNCD, area), prot_date, fill = list(prot_area = 0)) %>%
  group_by(ecoregion = CRGNNM, ecoregion_code = CRGNCD, prot_date) %>%
  summarise(ecoregion_area = min(area),
            tot_protected = sum(prot_area),
            percent_protected = tot_protected / ecoregion_area * 100)

## Provincial summary of marine protected area by year
prot_areas_bc_m_summary_by_year <- prot_areas_eco_m_summary_by_year %>%
  group_by(prot_date) %>%
  summarise(ecoregion = "British Columbia",
            ecoregion_code = "BC",
            ecoregion_area = sum(ecoregions_m$area),
            tot_protected = sum(tot_protected),
            percent_protected = tot_protected / ecoregion_area * 100)

## Calculate cumulative amound and percent protected over time, then
## combine provincial and ecoregional trend summaries
cum_summary_m_eco <- prot_areas_eco_m_summary_by_year %>%
  group_by(ecoregion, ecoregion_code) %>%
  arrange(prot_date) %>%
  mutate(cum_area_protected = cumsum(tot_protected),
         cum_percent_protected = cumsum(percent_protected),
         type = "All conservation lands",
         prot_date_full = paste0(prot_date, "-01-01")) %>%
  filter(!is.na(cum_area_protected)) %>%
  ungroup() %>%
  mutate(ecoregion = tools::toTitleCase(tolower(ecoregion)))

cum_summary_m_bc <- prot_areas_bc_m_summary_by_year %>%
  arrange(prot_date) %>%
  mutate(cum_area_protected = cumsum(tot_protected),
         cum_percent_protected = cumsum(percent_protected),
         type = "All conservation lands",
         prot_date_full = paste0(prot_date, "-01-01")) %>%
  filter(!is.na(cum_area_protected)) %>%
  ungroup() %>%
  mutate(ecoregion = tools::toTitleCase(tolower(ecoregion)))

cum_summary_m <- bind_rows(cum_summary_m_eco, cum_summary_m_bc)

# Terrrestrial BEC -------------------------------------------------------------
## Get a simple percent protected of each Biogeoclimatic Zone

# Get total size of terrestrial area of each zone
bec_t_summary <- bec_t@data %>%
  group_by(ZONE_NAME) %>%
  summarize(total_area = sum(area))

# Intersect terrestrial CARTS and BEC and get area
prot_areas_bec <- raster::intersect(bec_t, prot_areas_agg)
prot_areas_bec$prot_area <- rgeos::gArea(prot_areas_bec, byid = TRUE)

## Summarize amount of area protected in each zone each year
prot_areas_bec_summary <- prot_areas_bec@data %>%
  group_by(ZONE, ZONE_NAME) %>%
  summarize(prot_area = sum(prot_area)) %>%
  left_join(select(reg_int_bec_summary, ZONE_NAME, prot_area_overlaps_removed), by = "ZONE_NAME") %>%
  left_join(bec_t_summary, by = "ZONE_NAME") %>%
  mutate(prot_area_overlaps_removed = ifelse(is.na(prot_area_overlaps_removed),
                                             0, prot_area_overlaps_removed),
         prot_area = prot_area + prot_area_overlaps_removed,
         prot_area_ha = m_to_ha(prot_area),
         percent_protected = round(prot_area / total_area * 100, 2)) %>%
  select(-prot_area_overlaps_removed, -prot_area, -total_area) %>%
  mutate(ZONE_NAME = gsub("--", "—", ZONE_NAME))


# Individual land designations by BEC -------------------------------------

## Get zone area in hectares
bec_t_summary$total_zone_area_ha <- bec_t_summary$total_area * 1e-4

## Aggregate layers by designation (bc_admin_lands_agg already done)
bc_carts_des <- raster::aggregate(bc_carts, by = "TYPE_E")
fee_simple_des <- raster::aggregate(fee_simple_ngo_lands, by = "SecType1")

## Intersect each with BEC and calculate area
fee_simple_bec <- raster::intersect(bec_t, fee_simple_des)
fee_simple_bec$prot_area <- rgeos::gArea(fee_simple_bec, byid = TRUE)

bc_admin_lands_bec <- raster::intersect(bec_t, bc_admin_lands_agg)
bc_admin_lands_bec$prot_area <- rgeos::gArea(bc_admin_lands_bec, byid = TRUE)

bc_carts_bec <- raster::intersect(bec_t, bc_carts_des)
bc_carts_bec$prot_area <- rgeos::gArea(bc_carts_bec, byid = TRUE)

## Convert the registerable interests summary into same format so can be combined
## with other designation summaries
reg_int_bec_summary <- reg_int_bec_summary %>%
  left_join(bec_t_summary, by = "ZONE_NAME") %>%
  mutate(category = "Private Conservation Lands",
         designation = "Registerable Interests",
         prot_area_ha = round(prot_area * 1e-4, 3),
         percent_protected = round((prot_area_ha / total_zone_area_ha * 100), 4)) %>%
  dplyr::select(-prot_area_overlaps_removed, -prot_area)

# Summarize fee simple
fee_simple_bec_summary <- fee_simple_bec@data %>%
  group_by(ZONE, ZONE_NAME) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(bec_t_summary, by = "ZONE_NAME") %>%
  mutate(category = "Private Conservation Lands",
         designation = "Fee Simple",
         percent_protected = round((prot_area_ha / total_zone_area_ha * 100), 4))

# Summarize admin areas
admin_lands_bec_summary <- bc_admin_lands_bec@data %>%
  group_by(ZONE, ZONE_NAME, designation = TENURE_TYPE) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(bec_t_summary, by = "ZONE_NAME") %>%
  mutate(category = "BC Administered Lands",
         percent_protected = round((prot_area_ha / total_zone_area_ha * 100), 4))

# Summarize carts data
bc_carts_designations_categories <- bc_carts@data %>%
  mutate(category = ifelse(OWNER_E == "Government of British Columbia",
                           "Provincial Protected Lands & Waters",
                           "Federal Protected Lands & Waters")) %>%
  group_by(category, designation = TYPE_E) %>%
  summarise(n = n())

bc_carts_bec_summary <- bc_carts_bec@data %>%
  left_join(bc_carts_designations_categories[, -3], by = c("TYPE_E" = "designation")) %>%
  group_by(category, designation = TYPE_E, ZONE, ZONE_NAME) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(bec_t_summary, by = "ZONE_NAME") %>%
  mutate(percent_protected = round((prot_area_ha / total_zone_area_ha * 100), 4))


## Combine them all
designations_bec <- bind_rows(reg_int_bec_summary, fee_simple_bec_summary,
                              admin_lands_bec_summary, bc_carts_bec_summary) %>%
  select(-total_area)

# Individual Designations with Ecoregions ---------------------------------

## Calculate area of ecoregions
ecoregions$area <- rgeos::gArea(ecoregions, byid = TRUE)
ecoregion_summary <- ecoregions@data %>%
  group_by(CRGNCD) %>%
  summarize(total_ecoregion_area_ha = sum(area) * 1e-4)

## Intersect each with Ecoregions and calculate area
fee_simple_eco <- raster::intersect(ecoregions, fee_simple_des)
fee_simple_eco$prot_area <- rgeos::gArea(fee_simple_eco, byid = TRUE)

bc_admin_lands_eco <- raster::intersect(ecoregions, bc_admin_lands_agg)
bc_admin_lands_eco$prot_area <- rgeos::gArea(bc_admin_lands_eco, byid = TRUE)

bc_carts_eco <- raster::intersect(ecoregions, bc_carts_des)
bc_carts_eco$prot_area <- rgeos::gArea(bc_carts_eco, byid = TRUE)

## Convert the registerable interests summary into same format so can be combined
## with other designation summaries
reg_int_eco_summary <- reg_int_ecoreg_summary %>%
  group_by(ecoregion, ecoregion_code) %>%
  summarize(tot_protected = sum(tot_protected)) %>%
  left_join(ecoregion_summary, by = c("ecoregion_code" = "CRGNCD")) %>%
  mutate(category = "Private Conservation Lands",
         designation = "Registerable Interests",
         prot_area_ha = round(tot_protected * 1e-4, 3),
         percent_protected = round((prot_area_ha / total_ecoregion_area_ha * 100), 4)) %>%
  dplyr::select(-tot_protected)

# Summarize fee simple
fee_simple_eco_summary <- fee_simple_eco@data %>%
  group_by(CRGNNM, CRGNCD) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(ecoregion_summary, by = "CRGNCD") %>%
  mutate(category = "Private Conservation Lands",
         designation = "Fee Simple",
         percent_protected = round((prot_area_ha / total_ecoregion_area_ha * 100), 4))

# Summarize admin areas
admin_lands_eco_summary <- bc_admin_lands_eco@data %>%
  group_by(CRGNNM, CRGNCD, designation = TENURE_TYPE) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(ecoregion_summary, by = "CRGNCD") %>%
  mutate(category = "BC Administered Lands",
         percent_protected = round((prot_area_ha / total_ecoregion_area_ha * 100), 4))

# Summarize carts data
bc_carts_eco_summary <- bc_carts_eco@data %>%
  left_join(bc_carts_designations_categories[, -3], by = c("TYPE_E" = "designation")) %>%
  group_by(category, CRGNNM, CRGNCD, designation = TYPE_E) %>%
  summarize(prot_area_ha = round(sum(prot_area) * 1e-4, 3)) %>%
  left_join(ecoregion_summary, by = "CRGNCD") %>%
  mutate(percent_protected = round((prot_area_ha / total_ecoregion_area_ha * 100), 4))


## Combine them all, & combine columns with same information but different names
designations_eco <- bind_rows(reg_int_eco_summary, fee_simple_eco_summary,
                              admin_lands_eco_summary, bc_carts_eco_summary) %>%
  mutate(ecoregion = ifelse(is.na(ecoregion), CRGNNM, ecoregion),
         ecoregion_code = ifelse(is.na(ecoregion_code), CRGNCD, ecoregion_code)) %>%
  select(-CRGNNM, -CRGNCD)


# Provincial Designation Summary ------------------------------------------

bc_carts$area <- rgeos::gArea(bc_carts, byid = TRUE)

bc_area_ha <- gArea(bc_bound_hres) * 1e-4
bc_m_area_ha <- 453602787832 * 1e-4

bc_carts_summary <- bc_carts@data %>%
  left_join(bc_carts_designations_categories[, -3], by = c("TYPE_E" = "designation")) %>%
  group_by(BIOME, category, designation = TYPE_E) %>%
  summarise(total_area_ha = sum(area) * 1e-4,
            n = n()) %>%
  ungroup() %>%
  mutate(percent_of_bc = ifelse(BIOME == "T", total_area_ha / (bc_area_ha) * 100,
                                total_area_ha / bc_m_area_ha * 100),
         percent_of_bc = round(percent_of_bc, 4))

bc_admin_lands_summary <- bc_admin_lands_unioned@data %>%
  mutate(BIOME = "T") %>%
  group_by(BIOME, category = designation_type, designation) %>%
  summarise(total_area_ha = sum(prot_area) * 1e-4,
            percent_of_bc = total_area_ha / (bc_area_ha) * 100) %>%
  left_join(bc_admin_lands@data %>%
              group_by(TENURE_TYPE) %>%
              summarize(n = n()),
            by = c("designation" = "TENURE_TYPE"))

bc_fee_simple_summary <- fee_simple_ngo_lands_unioned@data %>%
  summarize(BIOME = "T",
            category = "Private Conservation Lands",
            designation = "Fee Simple",
            total_area_ha = sum(prot_area) * 1e-4,
            percent_of_bc = total_area_ha / (bc_area_ha) * 100,
            n = length(fee_simple_ngo_lands))

bc_reg_int_summary <- mutate(bc_reg_int_summary,
                             percent_of_bc = total_area_ha / bc_area_ha,
                             category = "Private Conservation Lands")

bc_designations_summary <- bind_rows(bc_carts_summary, bc_admin_lands_summary,
                                     bc_fee_simple_summary, bc_reg_int_summary)

## Prep summary for interactive web viz by removing the zeros (they are handled in the viz)
cum_summary_t_viz <- cum_summary_t[cum_summary_t$tot_protected > 0, ]

## Get a current summary of ecoregion protection
current_eco_summary <- function(cum_eco_summary, biome) {
  cum_eco_summary %>%
    filter(prot_date == max(prot_date)) %>%
    select(ecoregion, ecoregion_code, ecoregion_area, cum_area_protected,
           cum_percent_protected) %>%
    mutate_each(funs(m_to_ha), ecoregion_area, cum_area_protected) %>%
    rename(ecoregion_area_ha = ecoregion_area, prot_area_ha = cum_area_protected,
           percent_protected = cum_percent_protected) %>%
    mutate_(biome = ~biome) %>%
    mutate(percent_protected = round(percent_protected, 2))
}

prot_areas_eco_t_summary <- current_eco_summary(cum_summary_t_eco, "Terrestrial")
prot_areas_eco_m_summary <- current_eco_summary(cum_summary_m_eco, "Marine")

## Save things that weren't loaded at the beginning
to_save <- setdiff(ls(), c(cleaned_bec_objs, cleaned_ecoreg_objs, cleaned_prot_areas_objs))
save(list = to_save, file = "tmp/analyzed.rda")

## Output csv files
options(scipen = 5)

bind_rows(prot_areas_eco_t_summary, prot_areas_eco_m_summary) %>%
  write_csv("out/ecoregions_protected_land_water_summary.csv")
write_csv(prot_areas_bec_summary,
          path = "out/bec_zone_protected_land_water_summary.csv")

write_csv(cum_summary_t_viz, path = "out/ecoregion_cons_lands_trends.csv")
write_csv(designations_bec, "out/bec_zone_protected_land_water_designations_summary.csv")
write_csv(designations_eco, "out/ecoregion_protected_land_water_designations_summary.csv")
write_csv(bc_designations_summary, path = "out/bc_protected_land_water_designations_summary.csv")

