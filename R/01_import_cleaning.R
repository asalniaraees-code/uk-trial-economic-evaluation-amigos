# ==============================================================================
# 01_import_cleaning.R
# Import all AMIGOS sheets, harmonise patient IDs, recode missing values
# ==============================================================================

library(readxl)
library(dplyr)
library(stringr)
library(tidyr)

data_path <- "D:/CV/wavrick Research fellow 2/Interview/AMIGOS_UK_Economic_Evaluation/AMIGOS+economic+evaluation+dataset.xlsx"

# ------------------------------------------------------------------------
# helper: strip a leading letter and coerce to integer
#   clinical / social_care / primary&tertiary use "A10" style IDs
#   inpatient / outpatient / intervention use plain numeric IDs
#   both refer to the same patients, so this makes them joinable
# ------------------------------------------------------------------------
strip_id <- function(x) as.integer(str_extract(as.character(x), "[0-9]+"))

# ------------------------------------------------------------------------
# 1. CLINICAL DATA  (baseline characteristics, EQ-5D, Barthel, mortality)
# ------------------------------------------------------------------------
clinical <- read_excel(data_path, sheet = "clinical data") %>%
  select(1:65) %>%                                   # drop the two trailing note columns
  rename(
    patient_id           = `patiend ID`,
    age                  = age,
    sex                  = sex,
    place                = place,
    placecode            = `placecode (1=Leicester)`,
    charlson_score       = `charlson comorbidity score`,
    pi_residence         = `pi_residence (residence status at baseline)`,
    pi_eq5d_mob          = `pi_eq5d_mob (mobility)`,
    pi_eq5d_sc           = `pi_eq5d_sc (self care)`,
    pi_eq5d_act          = `pi_eq5d_act (usual activities)`,
    pi_eq5d_pain         = pi_eq5d_pain,
    pi_eq5d_anx          = `pi_eq5d_anx (anxiety/depression)`,
    po_residence         = po_residence,
    dead_at_follow_up    = `Dead at follow up (=1)`,
    days_to_death        = `Days in study until death`,
    intervention_arm     = Intervention
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 2. INPATIENT / DAYCASE  (needed for HRG-based costing in script 03)
# ------------------------------------------------------------------------
inpatient <- read_excel(data_path, sheet = "inpatient and daycase") %>%
  rename(
    patient_id  = `patient ID`,
    placecode   = `Place code (1=Leicester)`,
    spell_no    = `Spell No (admission number)`,
    episode_no  = `Episode No (number of episode in admission)`,
    admimeth    = `ADMIMETH (admission method NHS code); http://www.datadictionary.nhs.uk/`,
    epidur      = `EPIDUR (episode duration)`,
    hrg_code    = `HRG code`
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 3. OUTPATIENT  (needed for attendance-based costing in script 03)
# ------------------------------------------------------------------------
outpatient <- read_excel(data_path, sheet = "outpatient") %>%
  select(1:4) %>%
  rename(
    patient_id       = `patient ID`,
    attendance_type  = `TYPE (new visit = ON; follow up visit = OF)`,
    tfc_code         = TREATMENT_FUNCTION_CODE,
    placecode        = `Placecode (1=Leicester)`
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 4. SOCIAL CARE  (already costed)
# ------------------------------------------------------------------------
social_care <- read_excel(data_path, sheet = "social care") %>%
  rename(
    patient_id       = `patient ID`,
    care_type        = type,
    service          = service,
    episode_duration = `episode duration in days`,
    episode_cost     = `episode cost`
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 5. INTERVENTION DELIVERY TIME  (hours -> costed in script 03)
# ------------------------------------------------------------------------
intervention_time <- read_excel(data_path, sheet = "intervention") %>%
  rename(
    patient_id        = `patient ID`,
    hrs_assessment    = `Duration.of.initial.assessment.including.all.related.activities..hrs.`,
    hrs_home_visits   = `Duration.of.home.visits..including.travel..letters..hrs..`,
    hrs_phone_calls   = `Duration.of.follow.up.phone.calls..hrs.`,
    hrs_clinic_visits = `Time.spent.in.clinical.visits.hrs`,
    hrs_other         = `Duration.of.other.patient.related.activity..hrs..Use...for.no.other.PRA`,
    cost_assumptions  = Assumptions
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 6. PRIMARY & TERTIARY CARE  (already costed)
# ------------------------------------------------------------------------
prim_tert <- read_excel(data_path, sheet = "primary & tertiary (Nottingham)") %>%
  rename(
    patient_id       = `patient ID`,
    criticalcare_cost = `criticalcare cost`,
    emas_cost        = `emas (East Midlands Ambulance Service) cost`,
    mht_cost         = `mht (Mental Health Trust) cost`,
    gp_cost          = `gp (GP cost)`,
    medication_cost  = `medication cost`,
    gpdata_complete  = `gpdata (1=complete, 0=missing)`
  ) %>%
  mutate(patient_id = strip_id(patient_id))

# ------------------------------------------------------------------------
# 7. Recode "." as NA in the clinical sheet, then fix column types
#    ("." is used for post-outcome variables of patients who died/dropped out)
# ------------------------------------------------------------------------
clinical <- clinical %>%
  mutate(across(where(is.character), ~ na_if(.x, ".")))

eq5d_cols    <- names(clinical)[str_detect(names(clinical), "^p[io]_eq5d_")]
numeric_fix  <- c(eq5d_cols, "days_to_death")

clinical <- clinical %>%
  mutate(across(all_of(numeric_fix), as.numeric))

# ------------------------------------------------------------------------
# 8. Recode categorical variables
# ------------------------------------------------------------------------
clinical <- clinical %>%
  mutate(
    sex               = factor(sex, levels = c("M", "F"), labels = c("Male", "Female")),
    intervention_arm  = factor(intervention_arm, levels = c(0, 1),
                                labels = c("Usual care", "Geriatrician intervention")),
    dead_at_follow_up = factor(dead_at_follow_up, levels = c(0, 1),
                                labels = c("Alive", "Dead"))
  )

# ------------------------------------------------------------------------
# 9. Sanity checks: EQ-5D-3L dimensions must be 1, 2, or 3
# ------------------------------------------------------------------------
bad_eq5d <- clinical %>%
  filter(if_any(all_of(eq5d_cols), ~ !(.x %in% c(1, 2, 3)) & !is.na(.x)))

if (nrow(bad_eq5d) > 0) {
  warning(nrow(bad_eq5d), " patient(s) have EQ-5D values outside 1-3. Inspect `bad_eq5d`.")
}

# ------------------------------------------------------------------------
# 10. Missingness summary -> output/tables (visible in the public repo)
# ------------------------------------------------------------------------
dir.create("output/tables", showWarnings = FALSE, recursive = TRUE)

missingness_summary <- clinical %>%
  summarise(across(everything(), ~ mean(is.na(.x)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "pct_missing") %>%
  arrange(desc(pct_missing))

write.csv(missingness_summary, "output/tables/missingness_summary.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 11. Save cleaned objects for downstream scripts (kept out of Git via
#     .gitignore since they're derived from patient-level data)
# ------------------------------------------------------------------------
dir.create("data/derived", showWarnings = FALSE, recursive = TRUE)

saveRDS(clinical,          "data/derived/clinical_clean.rds")
saveRDS(inpatient,         "data/derived/inpatient_clean.rds")
saveRDS(outpatient,        "data/derived/outpatient_clean.rds")
saveRDS(social_care,       "data/derived/social_care_clean.rds")
saveRDS(intervention_time, "data/derived/intervention_clean.rds")
saveRDS(prim_tert,         "data/derived/prim_tert_clean.rds")

message("01_import_cleaning.R complete: 6 cleaned datasets saved to data/derived/")
