#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-finalize

# TODO
# - deletes all files not referenced in the database
# - verify all database values and paths