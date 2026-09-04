# UK Trial-Based Economic Evaluation: AMIGOS

## Overview

This project conducts a trial-based economic evaluation using publicly available
patient-level data from the AMIGOS randomised controlled trial, which compared a
geriatrician-led case management intervention against usual care for older people
discharged from an acute medical unit.

## Objective

To develop practical experience analysing UK clinical trial data, including
healthcare resource use, costs, EQ-5D, and QALYs, and to produce a reproducible
cost-effectiveness analysis.

## Data

AMIGOS randomised controlled trial (n = 417).

The original dataset is not redistributed in this repository, as it contains
patient-level data. It is available from the original data repository, subject
to its terms of use.

## Methods

- Data cleaning and quality assessment
- Patient-level resource-use analysis
- UK EQ-5D-3L utility estimation (TTO value set, Dolan 1997)
- QALY calculation (area-under-the-curve method)
- Cost analysis using unit costs from the NHS National Schedule of Reference Costs
  2011-12 (matching the trial's HRG4-era coding):
  - Inpatient/daycase episodes costed using **setting-specific** HRG unit costs
    (daycase vs. combined elective/non-elective inpatient rates, selected per
    episode by episode duration), rather than a single blended rate
  - Outpatient attendances costed using treatment-function-code-level attendance
    tariffs (first vs. follow-up)
  - Intervention delivery time costed at £132/hour (PSSRU 2012 consultant medical
    wage, confirmed against the published trial's own reported intervention cost)
  - Social care and primary/tertiary care costed from the dataset's own cost fields
- Incremental cost-effectiveness analysis (unadjusted and baseline-adjusted)
- Uncertainty analysis via non-parametric bootstrap (cost-effectiveness plane, CEAC)

## Software

R / RStudio. Key packages: readxl, dplyr, eq5d, ggplot2, boot.

## Project structure

```
R/            - analysis scripts (01_import_cleaning -> 04_analysis)
data/         - raw data (not tracked) and unit cost lookups (tracked)
output/       - generated tables and figures
docs/         - preliminary report
```

## Results

**Baseline (n = 417):** the two arms were reasonably balanced on age (82.7 vs 82.9) and
comorbidity (Charlson 1.56 vs 1.55), with a modest baseline utility imbalance (0.499 vs 0.525)
that motivated a baseline-adjusted analysis alongside the unadjusted one.

**Cost and QALYs (complete cases, n = 254):**

| Arm | n | Mean cost | Mean QALY (90 days) |
|---|---|---|---|
| Usual care | 127 | £2,948.12 | 0.1149 |
| Geriatrician intervention | 127 | £4,137.36 | 0.1192 |

**Incremental cost-effectiveness:**

| Analysis | Incremental cost | Incremental QALY | ICER |
|---|---|---|---|
| Unadjusted | £1,189.24 | 0.0042 | £280,666/QALY |
| Adjusted (baseline utility) | £1,199.23 | 0.0024 | £496,557/QALY |

The intervention costs more with a small, uncertain QALY gain; both ICERs remain far above
conventional UK thresholds (£20,000-£30,000/QALY) even after the costing fixes below. Note
the cost-effectiveness plane and CEAC images below were generated before the fixes and are
based on the unadjusted bootstrap - re-run `04_analysis.R` and regenerate them for full
consistency with the numbers in this table.

![Cost-effectiveness plane](output/figures/cost_effectiveness_plane.png)

## Comparison with the published trial

The published economic evaluation (Tanajewski et al., 2015, *PLOS ONE*) analysed the
same complete-case subsample size (n = 254, 127 per arm) and reported:

| | Published (complete-case) | This analysis (original) | This analysis (after fixes) |
|---|---|---|---|
| Incremental cost (unadjusted) | £228 | £1,393 | £1,189 |
| Incremental cost (adjusted) | £235 | £1,404 | £1,199 |
| Incremental QALY | 0.004 | 0.004 | 0.004 |
| ICER (adjusted) | £116,326/QALY | £581,326/QALY | £496,557/QALY |

QALYs matched the published figures closely from the start; the gap was entirely in
incremental cost. Two issues were identified and fixed:

1. **Intervention wage rate** was £15.50/hour - a misread PSSRU table/reference number,
   not the actual wage. Corrected to £132/hour (confirmed exactly against the published
   trial's reported mean intervention cost: 1.577 mean hours/patient x £132 = £208).
2. **Inpatient/daycase costing** used a single blended HRG unit cost per episode
   regardless of setting, which overcosts daycase activity (typically much cheaper
   than an inpatient stay for the same HRG). Corrected to use setting-specific
   daycase vs. inpatient rates, selected per episode by episode duration.

These fixes reduced the incremental cost gap by about 15% but did not close it. The
remaining ~5x gap versus the published figure is attributed to two further scope
differences documented under Limitations, rather than a residual bug: this analysis's
total cost includes primary/tertiary/critical-care costs that the published two-centre
analysis deliberately excludes, and the adjusted model here controls for fewer covariates
than the published analysis.

## Limitations

- Complete-case analysis retained only 254/417 patients (61%) for cost/QALY estimation;
  multiple imputation would be the appropriate next step rather than dropping missing follow-up.
- QALYs for patients who died assume a linear utility decline to zero at date of death.
- Two of 155 HRG codes (~2.7% of inpatient episodes) could not be matched to the
  2011-12 schedule and are costed as £0.
- This analysis's total cost includes primary/tertiary/critical-care/ambulance costs,
  which are only recorded for the Nottingham sub-sample (zero-filled for Leicester
  patients). The published trial deliberately excludes these from its two-centre
  headline analysis for this reason, making this repository's total cost not directly
  comparable to the published two-centre figures on that basis alone.
- The adjusted analysis here controls only for baseline utility; the published analysis
  additionally adjusts for hospital site, ISAR risk category, and care-home residence.
- This is an independent, self-directed replication for methods practice, not a validated
  reproduction of the original trial's published economic evaluation.

## Changelog

- Fixed intervention hourly wage rate: was £15.50 (a misread PSSRU table/reference
  number), corrected to £132 (confirmed against the published trial's reported mean
  intervention cost).
- Fixed inpatient/daycase costing: was a single blended HRG unit cost per episode,
  changed to setting-specific rates (daycase vs. inpatient) selected by episode
  duration, to avoid overcosting daycase activity.
- Re-ran the analysis after both fixes; incremental cost fell from £1,393 to £1,189
  (unadjusted). Remaining gap versus the published trial attributed to cost-component
  scope and adjustment-covariate differences (see Comparison and Limitations above).

## Status

Preliminary exploratory analysis, complete. Cost-effectiveness plane and CEAC figures
should be regenerated from the post-fix data before final presentation.
