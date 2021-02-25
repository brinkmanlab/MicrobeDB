#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-finalize

# TODO
# - deletes all files not referenced in the database
# - calculates gram stain column
# - relinks datasets.replicon to summary table via index in file name and replicon_idx_${SLURM_ARRAY_TASK_ID}.tsv
# - verify all database values and paths