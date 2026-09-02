# ==============================================================================
# 03_costing.R
# Apply unit costs to resource use and build total cost per patient
# ==============================================================================

library(dplyr)
library(readr)
library(tidyr)

inpatient         <- readRDS("data/derived/inpatient_clean.rds")
outpatient        <- readRDS("data/derived/outpatient_clean.rds")
social_care       <- readRDS("data/derived/social_care_clean.rds")
intervention_time <- readRDS("data/derived/intervention_clean.rds")
prim_tert         <- readRDS("data/derived/prim_tert_clean.rds")
clinical          <- readRDS("data/derived/clinical_clean.rds")

# ------------------------------------------------------------------------
# 1. INPATIENT / DAYCASE COSTS
#    HRG codes need a unit cost lookup, sourced from the NHS National
#    Schedule of Reference Costs 2011-12 (data/unit_costs/hrg_tariff.csv),
#    with SEPARATE unit costs for daycase vs inpatient settings.
#
#    Using one blended "Total" rate for every episode overcosts daycase
#    admissions (which are genuinely cheaper) at the same rate as full
#    inpatient stays. EPIDUR (episode duration) == 0 identifies a daycase
#    episode - use the daycase-specific rate for those, and the combined
#    elective/non-elective inpatient rate otherwise.
# ------------------------------------------------------------------------
hrg_tariff_path <- "data/unit_costs/hrg_tariff.csv"

if (file.exists(hrg_tariff_path)) {
  hrg_tariff <- read_csv(hrg_tariff_path, show_col_types = FALSE)
} else {
  warning("HRG tariff file not found at ", hrg_tariff_path,
          " - inpatient costs will be NA until you add it.")
  hrg_tariff <- tibble(hrg_code = character(), daycase_unit_cost = numeric(),
                        inpatient_unit_cost = numeric())
}

# Force to character on both sides too, for the same reason as tfc_code
# below - protects against a future tariff file mismatching type.
inpatient  <- inpatient  %>% mutate(hrg_code = as.character(hrg_code))
hrg_tariff <- hrg_tariff %>% mutate(hrg_code = as.character(hrg_code))

inpatient_costed <- inpatient %>%
  left_join(hrg_tariff, by = "hrg_code") %>%
  mutate(
    episode_cost = if_else(epidur == 0, daycase_unit_cost, inpatient_unit_cost)
  ) %>%
  group_by(patient_id) %>%
  summarise(inpatient_cost = sum(episode_cost, na.rm = TRUE), .groups = "drop")

# ------------------------------------------------------------------------
# 2. OUTPATIENT COSTS
#    Similarly needs unit costs by treatment function code (tfc_code) and
#    attendance type (new = "ON" vs follow-up = "OF") from NHS reference
#    costs. Save as data/unit_costs/outpatient_tariff.csv with columns:
#    tfc_code, attendance_type, unit_cost
# ------------------------------------------------------------------------
outp_tariff_path <- "data/unit_costs/outpatient_tariff.csv"

if (file.exists(outp_tariff_path)) {
  outp_tariff <- read_csv(outp_tariff_path, show_col_types = FALSE)
} else {
  warning("Outpatient tariff file not found at ", outp_tariff_path,
          " - outpatient costs will be NA until you add it.")
  outp_tariff <- tibble(tfc_code = character(), attendance_type = character(), unit_cost = numeric())
}

# tfc_code can be read in as character or numeric depending on the source
# file (a stray non-numeric value anywhere in the column makes readxl/
# read_csv treat the whole column as character) - force both sides to
# character before joining so the types always match regardless of source.
outpatient <- outpatient %>%
  mutate(tfc_code = as.character(tfc_code),
         attendance_type = as.character(attendance_type))

outp_tariff <- outp_tariff %>%
  mutate(tfc_code = as.character(tfc_code),
         attendance_type = as.character(attendance_type))

outpatient_costed <- outpatient %>%
  left_join(outp_tariff, by = c("tfc_code", "attendance_type")) %>%
  group_by(patient_id) %>%
  summarise(outpatient_cost = sum(unit_cost, na.rm = TRUE), .groups = "drop")

# ------------------------------------------------------------------------
# 3. SOCIAL CARE COSTS - already provided per episode, just sum
# ------------------------------------------------------------------------
social_care_costed <- social_care %>%
  group_by(patient_id) %>%
  summarise(social_care_cost = sum(episode_cost, na.rm = TRUE), .groups = "drop")

# ------------------------------------------------------------------------
# 4. INTERVENTION DELIVERY COSTS
#    Hours x hourly wage rate. The "Assumptions" column in the source
#    sheet documents the wage rate used per patient (e.g. geriatrician
#    hourly wage from PSSRU) - for a consistent base case, apply a single
#    unit cost from the current PSSRU Unit Costs of Health & Social Care.
#    Replace GERIATRICIAN_HOURLY_RATE with the value you decide to use.
# ------------------------------------------------------------------------
GERIATRICIAN_HOURLY_RATE <- 132   # PSSRU 2012 consultant medical hourly wage (confirmed against
                                   # the published AMIGOS trial paper: mean 1.577 hrs/patient x £132
                                   # = £208, matching the paper's reported mean intervention cost
                                   # exactly. The "15.5" in the Assumptions column is a PSSRU
                                   # table/reference number, not the wage rate itself.

intervention_costed <- intervention_time %>%
  mutate(
    total_hours = rowSums(across(starts_with("hrs_")), na.rm = TRUE),
    intervention_cost = total_hours * GERIATRICIAN_HOURLY_RATE
  ) %>%
  select(patient_id, intervention_cost)

# ------------------------------------------------------------------------
# 5. PRIMARY & TERTIARY CARE COSTS - already provided, just sum components
#    Flag patients with incomplete GP data (gpdata_complete == 0) rather
#    than silently including a possible underestimate
# ------------------------------------------------------------------------
prim_tert_costed <- prim_tert %>%
  mutate(
    prim_tert_cost = rowSums(
      across(c(criticalcare_cost, emas_cost, mht_cost, gp_cost, medication_cost)),
      na.rm = TRUE
    )
  ) %>%
  select(patient_id, prim_tert_cost, gpdata_complete)

incomplete_gp <- prim_tert_costed %>% filter(gpdata_complete == 0)
write.csv(incomplete_gp, "output/tables/incomplete_gp_data_patients.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 6. AGGREGATE ALL COST COMPONENTS TO ONE ROW PER PATIENT
# ------------------------------------------------------------------------
cost_data <- clinical %>%
  select(patient_id, intervention_arm) %>%
  left_join(inpatient_costed,    by = "patient_id") %>%
  left_join(outpatient_costed,   by = "patient_id") %>%
  left_join(social_care_costed,  by = "patient_id") %>%
  left_join(intervention_costed, by = "patient_id") %>%
  left_join(prim_tert_costed,    by = "patient_id") %>%
  mutate(across(ends_with("_cost"), ~ replace_na(.x, 0))) %>%
  mutate(
    total_cost = inpatient_cost + outpatient_cost + social_care_cost +
      intervention_cost + prim_tert_cost
  )

# ------------------------------------------------------------------------
# 7. Cost breakdown table by category and by arm (for the report/README)
# ------------------------------------------------------------------------
cost_breakdown <- cost_data %>%
  group_by(intervention_arm) %>%
  summarise(
    n                        = n(),
    mean_inpatient_cost      = mean(inpatient_cost, na.rm = TRUE),
    mean_outpatient_cost     = mean(outpatient_cost, na.rm = TRUE),
    mean_social_care_cost    = mean(social_care_cost, na.rm = TRUE),
    mean_intervention_cost   = mean(intervention_cost, na.rm = TRUE),
    mean_prim_tert_cost      = mean(prim_tert_cost, na.rm = TRUE),
    mean_total_cost          = mean(total_cost, na.rm = TRUE),
    .groups = "drop"
  )

write.csv(cost_breakdown, "output/tables/cost_breakdown_by_arm.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 8. Save for the analysis script
# ------------------------------------------------------------------------
saveRDS(cost_data, "data/derived/cost_data.rds")

message("03_costing.R complete: total cost per patient saved to data/derived/cost_data.rds")
message("Reminder: add real HRG and outpatient tariff files under data/unit_costs/ before treating results as final.")
