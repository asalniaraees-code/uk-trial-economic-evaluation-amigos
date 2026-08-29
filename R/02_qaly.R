# ==============================================================================
# 02_qaly.R
# Score EQ-5D-3L utilities (UK tariff) and calculate QALYs
# ==============================================================================

library(dplyr)
library(eq5d)     # install.packages("eq5d") if not already installed

clinical <- readRDS("data/derived/clinical_clean.rds")

# ------------------------------------------------------------------------
# 1. Score baseline (pi_) and follow-up (po_) EQ-5D-3L utilities
#    using the UK time-trade-off value set (Dolan 1997)
#    eq5d::eq5d() expects a data frame/matrix of the 5 dimension scores
#    in the order: mobility, self-care, usual activities, pain, anxiety
# ------------------------------------------------------------------------
score_eq5d_uk <- function(mob, sc, act, pain, anx) {
  dims <- data.frame(MO = mob, SC = sc, UA = act, PD = pain, AD = anx)
  
  # eq5d::eq5d() errors out on the *entire* input if even one row has a
  # missing dimension (it doesn't return NA per row) - so score only the
  # complete rows and leave the rest as NA rather than letting one bad
  # row kill the whole vector.
  complete <- complete.cases(dims)
  out <- rep(NA_real_, nrow(dims))
  
  if (any(complete)) {
    out[complete] <- eq5d(scores = dims[complete, , drop = FALSE],
                          type = "TTO", version = "3L", country = "UK")
  }
  
  out
}

clinical <- clinical %>%
  mutate(
    utility_baseline = score_eq5d_uk(pi_eq5d_mob, pi_eq5d_sc, pi_eq5d_act,
                                     pi_eq5d_pain, pi_eq5d_anx),
    utility_followup = score_eq5d_uk(po_eq5d_mob, po_eq5d_sc, po_eq5d_act,
                                     po_eq5d_pain, po_eq5d_anx)
  )

# ------------------------------------------------------------------------
# 2. Define each patient's time in the study, in years
#    - If the patient died: use days_to_death
#    - If alive: use the trial's fixed follow-up length (set this to the
#      actual protocol follow-up in days, e.g. 90 or 180 - CONFIRM this
#      against the AMIGOS protocol before running the base case)
# ------------------------------------------------------------------------
TRIAL_FOLLOWUP_DAYS <- 90   # confirmed: 90-day follow-up per Tanajewski et al. 2015, PLOS ONE
clinical <- clinical %>%
  mutate(
    time_in_study_days = case_when(
      dead_at_follow_up == "Dead" ~ days_to_death,
      TRUE                        ~ TRIAL_FOLLOWUP_DAYS
    ),
    time_in_study_years = time_in_study_days / 365.25
  )

# ------------------------------------------------------------------------
# 3. QALY calculation via the area-under-the-curve (trapezoidal) method
#    - Patients who died: utility assumed to fall linearly from baseline
#      utility to 0 at date of death (standard simplifying assumption -
#      state clearly in the write-up and test as a sensitivity analysis)
#    - Patients alive at follow-up: trapezoid between baseline and
#      follow-up utility over the full follow-up period
#    - Patients with missing follow-up utility and known to be alive:
#      QALY set to NA (complete-case base case) - flagged for review
# ------------------------------------------------------------------------
clinical <- clinical %>%
  mutate(
    qaly = case_when(
      dead_at_follow_up == "Dead" ~
        0.5 * utility_baseline * time_in_study_years,
      dead_at_follow_up == "Alive" & !is.na(utility_followup) ~
        0.5 * (utility_baseline + utility_followup) * time_in_study_years,
      TRUE ~ NA_real_
    )
  )

# ------------------------------------------------------------------------
# 4. Flag patients excluded from the QALY base case for transparency
# ------------------------------------------------------------------------
qaly_missing <- clinical %>%
  filter(is.na(qaly)) %>%
  select(patient_id, intervention_arm, dead_at_follow_up, utility_baseline, utility_followup)

write.csv(qaly_missing, "output/tables/qaly_excluded_patients.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 5. Baseline characteristics table by arm ("Table 1")
# ------------------------------------------------------------------------
baseline_table <- clinical %>%
  group_by(intervention_arm) %>%
  summarise(
    n                 = n(),
    mean_age          = mean(age, na.rm = TRUE),
    pct_female        = mean(sex == "Female", na.rm = TRUE) * 100,
    mean_charlson     = mean(charlson_score, na.rm = TRUE),
    mean_utility_base = mean(utility_baseline, na.rm = TRUE),
    .groups = "drop"
  )

write.csv(baseline_table, "output/tables/baseline_table.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 6. Save QALY dataset for costing/analysis scripts
# ------------------------------------------------------------------------
qaly_data <- clinical %>%
  select(patient_id, intervention_arm, age, sex, charlson_score,
         utility_baseline, utility_followup, time_in_study_years,
         dead_at_follow_up, qaly)

saveRDS(qaly_data, "data/derived/qaly_data.rds")

message("02_qaly.R complete: QALY dataset saved to data/derived/qaly_data.rds")
message(nrow(qaly_missing), " patient(s) excluded from QALY base case - see output/tables/qaly_excluded_patients.csv")
