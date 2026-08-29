## Results

**Baseline (n = 417):** the two arms were reasonably balanced on age (82.7 vs 82.9) and
comorbidity (Charlson 1.56 vs 1.55), with a modest baseline utility imbalance (0.499 vs 0.525)
that motivated a baseline-adjusted analysis alongside the unadjusted one.

**Cost and QALYs (complete cases, n = 254):**

| Arm | n | Mean cost | Mean QALY (90 days) |
|---|---|---|---|
| Usual care | 127 | £3,755.57 | 0.1149 |
| Geriatrician intervention | 127 | £5,149.00 | 0.1192 |

**Incremental cost-effectiveness:**

| Analysis | Incremental cost | Incremental QALY | ICER |
|---|---|---|---|
| Unadjusted | £1,393.43 | 0.0042 | £328,856/QALY |
| Adjusted (baseline utility) | £1,403.96 | 0.0024 | £581,326/QALY |

The intervention costs more with a small, uncertain QALY gain; both ICERs are far above
conventional UK thresholds (£20,000-£30,000/QALY). The cost-effectiveness acceptability
curve stays below ~6% probability of cost-effectiveness across £0-£50,000/QALY.

![Cost-effectiveness plane](output/figures/cost_effectiveness_plane.png)

## Limitations

- Complete-case analysis retained only 254/417 patients (61%) for cost/QALY estimation;
  multiple imputation would be the appropriate next step rather than dropping missing follow-up.
- QALYs for patients who died assume a linear utility decline to zero at date of death.
- Costs use the NHS National Schedule of Reference Costs 2011-12 (matching the trial's HRG4-era
  coding); 2 of 155 HRG codes (~2.7% of inpatient episodes) were unmatched and costed as £0.
- Intervention delivery time uses a single fixed hourly wage rate rather than per-patient variation.
- This is an independent, self-directed replication for methods practice, not a validated
  reproduction of the original trial's published economic evaluation.