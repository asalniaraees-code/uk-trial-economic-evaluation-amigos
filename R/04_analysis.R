# ==============================================================================
# 04_analysis.R
# Merge cost + QALY data, compute ICER, bootstrap uncertainty, plot CE plane/CEAC
# ==============================================================================

library(dplyr)
library(ggplot2)
library(boot)

qaly_data <- readRDS("data/derived/qaly_data.rds")
cost_data <- readRDS("data/derived/cost_data.rds")

dir.create("output/figures", showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------
# 1. Merge into one analysis-ready, patient-level dataset
# ------------------------------------------------------------------------
analysis_data <- qaly_data %>%
  select(patient_id, intervention_arm, qaly, utility_baseline) %>%
  inner_join(cost_data %>% select(patient_id, total_cost), by = "patient_id") %>%
  filter(!is.na(qaly), !is.na(total_cost))   # complete-case base case

message(nrow(analysis_data), " patients included in the base-case analysis (",
        nrow(qaly_data) - nrow(analysis_data), " excluded for missing cost/QALY data)")

# ------------------------------------------------------------------------
# 2. Base-case means and unadjusted incremental cost/QALY
# ------------------------------------------------------------------------
arm_summary <- analysis_data %>%
  group_by(intervention_arm) %>%
  summarise(
    n          = n(),
    mean_cost  = mean(total_cost),
    mean_qaly  = mean(qaly),
    .groups = "drop"
  )

write.csv(arm_summary, "output/tables/arm_summary.csv", row.names = FALSE)

usual_care   <- arm_summary %>% filter(intervention_arm == "Usual care")
intervention <- arm_summary %>% filter(intervention_arm == "Geriatrician intervention")

incr_cost <- intervention$mean_cost - usual_care$mean_cost
incr_qaly <- intervention$mean_qaly - usual_care$mean_qaly
icer      <- incr_cost / incr_qaly

icer_result <- tibble::tibble(
  incremental_cost = incr_cost,
  incremental_qaly = incr_qaly,
  icer             = icer
)
write.csv(icer_result, "output/tables/icer_unadjusted.csv", row.names = FALSE)

message("Unadjusted ICER: £", round(icer, 0), " per QALY (\u0394cost = £", round(incr_cost, 2),
        ", \u0394QALY = ", round(incr_qaly, 4), ")")

# ------------------------------------------------------------------------
# 3. Baseline-adjusted analysis
#    Regress cost and QALY on treatment arm, adjusting for baseline
#    utility (and any other imbalanced baseline covariates identified
#    in the Table 1 from 02_qaly.R). This is preferred over raw mean
#    differences for a trial-based economic evaluation.
# ------------------------------------------------------------------------
cost_model <- lm(total_cost ~ intervention_arm + utility_baseline, data = analysis_data)
qaly_model <- lm(qaly ~ intervention_arm + utility_baseline, data = analysis_data)

adjusted_incr_cost <- coef(cost_model)["intervention_armGeriatrician intervention"]
adjusted_incr_qaly <- coef(qaly_model)["intervention_armGeriatrician intervention"]
adjusted_icer <- adjusted_incr_cost / adjusted_incr_qaly

adjusted_result <- tibble::tibble(
  adjusted_incremental_cost = adjusted_incr_cost,
  adjusted_incremental_qaly = adjusted_incr_qaly,
  adjusted_icer             = adjusted_icer
)
write.csv(adjusted_result, "output/tables/icer_adjusted.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 4. Non-parametric bootstrap for uncertainty
#    Resample patients within each arm, recompute incremental cost/QALY
#    each time, to build the joint distribution for the CE plane and CEAC
# ------------------------------------------------------------------------
set.seed(123)   # for reproducibility - document this in the README

boot_incremental <- function(data, indices) {
  d <- data[indices, ]
  by_arm <- d %>%
    group_by(intervention_arm) %>%
    summarise(mean_cost = mean(total_cost), mean_qaly = mean(qaly), .groups = "drop")

  uc <- by_arm %>% filter(intervention_arm == "Usual care")
  gi <- by_arm %>% filter(intervention_arm == "Geriatrician intervention")

  c(delta_cost = gi$mean_cost - uc$mean_cost,
    delta_qaly = gi$mean_qaly - uc$mean_qaly)
}

# Stratified bootstrap: resample within each arm separately so arm sizes
# stay fixed across replicates
boot_results <- boot(
  data = analysis_data,
  statistic = boot_incremental,
  R = 2000,
  strata = analysis_data$intervention_arm
)

boot_df <- as.data.frame(boot_results$t)
names(boot_df) <- c("delta_cost", "delta_qaly")

write.csv(boot_df, "output/tables/bootstrap_replicates.csv", row.names = FALSE)

# ------------------------------------------------------------------------
# 5. Cost-effectiveness plane
# ------------------------------------------------------------------------
ce_plane <- ggplot(boot_df, aes(x = delta_qaly, y = delta_cost)) +
  geom_point(alpha = 0.3, colour = "steelblue") +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dashed") +
  geom_point(data = icer_result, aes(x = incremental_qaly, y = incremental_cost),
             colour = "red", size = 3) +
  labs(
    title = "Cost-effectiveness plane: geriatrician intervention vs usual care",
    x = "Incremental QALYs",
    y = "Incremental cost (£)"
  ) +
  theme_minimal()

ggsave("output/figures/cost_effectiveness_plane.png", ce_plane, width = 7, height = 5, dpi = 300)

# ------------------------------------------------------------------------
# 6. Cost-effectiveness acceptability curve (CEAC)
#    Probability that the intervention is cost-effective across a range
#    of willingness-to-pay thresholds (£0 to £50,000/QALY)
# ------------------------------------------------------------------------
thresholds <- seq(0, 50000, by = 1000)

ceac_df <- tibble::tibble(
  threshold = thresholds,
  prob_cost_effective = sapply(thresholds, function(k) {
    nmb <- k * boot_df$delta_qaly - boot_df$delta_cost   # net monetary benefit
    mean(nmb > 0)
  })
)

write.csv(ceac_df, "output/tables/ceac.csv", row.names = FALSE)

ceac_plot <- ggplot(ceac_df, aes(x = threshold, y = prob_cost_effective)) +
  geom_line(colour = "darkgreen", linewidth = 1) +
  labs(
    title = "Cost-effectiveness acceptability curve",
    x = "Willingness-to-pay threshold (£ per QALY)",
    y = "Probability intervention is cost-effective"
  ) +
  scale_y_continuous(limits = c(0, 1)) +
  theme_minimal()

ggsave("output/figures/ceac.png", ceac_plot, width = 7, height = 5, dpi = 300)

# ------------------------------------------------------------------------
# 7. Sensitivity analysis placeholder - example: exclude patients with
#    incomplete GP data (flagged in 03_costing.R)
# ------------------------------------------------------------------------
incomplete_gp <- read.csv("output/tables/incomplete_gp_data_patients.csv")

sens_data <- analysis_data %>%
  filter(!patient_id %in% incomplete_gp$patient_id)

sens_summary <- sens_data %>%
  group_by(intervention_arm) %>%
  summarise(mean_cost = mean(total_cost), mean_qaly = mean(qaly), .groups = "drop")

write.csv(sens_summary, "output/tables/sensitivity_exclude_incomplete_gp.csv", row.names = FALSE)

message("04_analysis.R complete. Base-case ICER, adjusted ICER, CE plane, and CEAC saved to output/")

cost_data %>% group_by(intervention_arm) %>%
  summarise(sd_cost = sd(total_cost), min_cost = min(total_cost), max_cost = max(total_cost))
