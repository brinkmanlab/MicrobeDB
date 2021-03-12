#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-finalize

# TODO
# - deletes all files not referenced in the database
# - calculates gram stain column
# - verify all database values and paths