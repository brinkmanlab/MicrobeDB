#!/usr/bin/env bash
set -e

# This script is responsible for rebuilding/updating MicrobeDB from scratch
# It fetches all complete bacterial and archea genomes from NCBI Entrez, including all available meta data.
# By default this script will submit work using SLURM sbatch, it can be run locally by setting LOCAL=1 environment variable.
# Optional environment variable configuration:
# QUERY - Override the Entrez query for fetching the list of assemblies
# OUTDIR - Override the staging folder where the data will be generated
# DBPATH - Override the path to where the sqlite database will be generated
# REPOPATH - Override the path to where the current CVMFS MicrobeDB repo is mounted. This is compared against while downloading/cleaning data.
# NCBI_API_KEY - Override the API key used to access NCBI Entrez. By default gopass will query the brinkmanlab password store for the key.
# STEP - Override the number of assemblies processed per job
# COUNT - Limit the script to the first COUNT number of entries returned by Entrez

QUERY=${QUERY:-'("bacteria"[Organism] OR "archaea"[Organism]) AND ("complete genome"[Assembly Level] OR "reference genome"[RefSeq Category])'}
OUTDIR=${OUTDIR:-${HOME}/scratch/microbedb}
DBPATH=${DBPATH:-${OUTDIR}/microbedb.sqlite}
REPOPATH=${REPOPATH:-'/cvmfs/microbedb.brinkmanlab.ca'}
SRCDIR="$(dirname "$0")"
STEP=${STEP:-200} # Number of assemblies to process per job

export NCBI_API_KEY=${NCBI_API_KEY:-$(gopass show 'brinkman/websites/ncbi.nlm.nih.gov/brinkmanlab' api_key)}

echo "Preparing ${OUTDIR}.."
if [[ -z $SKIP_RSYNC ]]; then
  rm -rf "${OUTDIR}"
  mkdir -p "${OUTDIR}"
else
  rm -f ${OUTDIR}/*.*
fi

# Copy README.md into repository
cp "${SRCDIR}/README.md" "${OUTDIR}"
# TODO copy recursive query.sql into outdir

echo "Generating query.."
esearch -db 'assembly' -query "${QUERY}" >query.xml
COUNT=${COUNT:-$(xq -r '.ENTREZ_DIRECT.Count' query.xml)}
if [[ -z "$COUNT" || "$COUNT" -eq 0 ]]; then
  echo "No results returned from query"
  exit 1
fi

# Prepare microbedb.sqlite
echo "Preparing database.."
rm -f "${DBPATH}"
sqlite3 -bail "${DBPATH}" <"${SRCDIR}/schema.sql"

if [[ -z $SKIP_TAXONOMY ]]; then
  # Load taxonomy table
  echo "Downloading taxonomy data.."
  rsync --progress --update rsync://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz .
  rm -rf taxdump
  mkdir taxdump
  tar -xvf taxdump.tar.gz -C taxdump

  echo "Converting taxonomy data to CSV.."
  # Convert to CSV as SQLITE doesn't support multi-char delimiters
  sed -i 's/"/""/g' taxdump/*.dmp
  sed -i 's/^/"/g' taxdump/*.dmp
  sed -i 's/\t|$/"/g' taxdump/*.dmp
  sed -i 's/\t|\t/","/g' taxdump/*.dmp

  echo "Loading taxonomy table.."
  sqlite3 -bail "${DBPATH}" <<EOF
PRAGMA foreign_keys = ON;
.mode csv
.import taxdump/names.dmp taxonomy_names
.import taxdump/division.dmp taxonomy_divisions
.import taxdump/gencode.dmp taxonomy_gencode
.import taxdump/nodes.dmp taxonomy_nodes
.import taxdump/merged.dmp taxonomy_merged
.import taxdump/delnodes.dmp taxonomy_deleted
.import taxdump/citations.dmp taxonomy_citations
EOF
fi

if [[ -n $LOCAL ]]; then
  # Run scripts locally rather than sbatch
  echo "Running fetch.sh locally for $COUNT records"
  for ((i = 0; i <= $COUNT; i += $STEP)); do
    OUTDIR="${OUTDIR}" DBPATH="${DBPATH}" REPOPATH="${REPOPATH}" SLURM_ARRAY_TASK_ID=$i STEP=$STEP COUNT=$COUNT SKIP_RSYNC=$SKIP_RSYNC SRCDIR="${SRCDIR}" "${SRCDIR}/fetch.sh"
  done
  echo "Running finalize.sh locally.."
  OUTDIR="${OUTDIR}" DBPATH="${DBPATH}" COUNT=$COUNT "${SRCDIR}/finalize.sh"
else
  # Batch submit fetch.sh
  echo "Submitting $COUNT records with fetch.sh to sbatch"
  job=$(sbatch --export=STEP="${STEP}" --export=COUNT="${COUNT}" --export=OUTDIR="${OUTDIR}" --export=DBPATH="${DBPATH}" --export=SRCDIR="${SRCDIR}" --export=REPOPATH="${REPOPATH}" --array="0-${COUNT}:${STEP}%10" "${SRCDIR}/fetch.sh")
  if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
    echo "Scheduling finalize.sh after job ${job} completes"
    sbatch --export=OUTDIR="${OUTDIR}" --export=DBPATH="${DBPATH}" --export=COUNT="${COUNT}" --export=SRCDIR="${SRCDIR}" --dependency="afterok:${BASH_REMATCH[1]}" "${SRCDIR}/finalize.sh"
  else
    echo "finalize.sh failed to schedule, sbatch failed to return job id for fetch.sh"
    exit 1
  fi
fi

echo "Done."
