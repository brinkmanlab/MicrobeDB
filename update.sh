#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --time=00:15:00
#SBATCH --job-name=microbedb-update
#SBATCH --export=ALL
#SBATCH --mail-user=brinkman-ws+microbedb@sfu.ca
#SBATCH --mail-type=BEGIN
#SBATCH --mail-type=FAIL
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
# KEYPATH - Path to stratum0 ssh key on Cedar
# STRATUM0 - ssh target including user name to access stratum0
# EDIRECT - Path to Entrez edirect folder

# Create unique working directory
export WORKDIR=${WORKDIR:-$(mktemp -d ${HOME}/scratch/microbedb_update$(date +'%Y_%m_%d').XXXXXXXXX)}
export QUERY=${QUERY:-'("bacteria"[Organism] OR "archaea"[Organism]) AND ("complete genome"[Assembly Level] OR "reference genome"[RefSeq Category])'}
export OUTDIR=${OUTDIR:-${WORKDIR}/microbedb}
export DBPATH=${DBPATH:-${OUTDIR}/microbedb.sqlite}
export REPOPATH=${REPOPATH:-'/cvmfs/microbedb.brinkmanlab.ca'}
export SRCDIR="$(dirname "$0")"
export STEP=${STEP:-200} # Number of assemblies to process per job
export KEYPATH=${KEYPATH:-${HOME}/.ssh/cvmfs.pem}
export STRATUM0=${STRATUM0:-'centos@stratum-0.brinkmanlab.ca'}
export PATH=${PATH}:${EDIRECT:-$(realpath "$SRCDIR"/edirect)}

cd "$WORKDIR"

module load python/3.9.6
source $SRCDIR/venv/bin/activate

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
cp "${SRCDIR}/subclassOf.sh" "${OUTDIR}"

echo "Generating query.."
esearch -db 'assembly' -query "${QUERY}" >query.xml
export COUNT=${COUNT:-$(xq -r '.ENTREZ_DIRECT.Count' query.xml)}
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

chmod -R o+rX "$WORKDIR"

if [[ -n $LOCAL ]]; then
  # Run scripts locally rather than sbatch
  echo "Running fetch.sh locally for $COUNT records"
  for ((i = 0; i <= $COUNT; i += $STEP)); do
    SLURM_ARRAY_TASK_ID=$i SKIP_RSYNC=$SKIP_RSYNC "${SRCDIR}/fetch.sh"
  done
  echo "Running finalize.sh locally.."
  "$SRCDIR"/finalize.sh
else
  # Batch submit fetch.sh
  echo "Submitting $COUNT records with fetch.sh to sbatch"
  job=$(sbatch --array="0-${COUNT}:${STEP}%10" "${SRCDIR}/fetch.sh")
  if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
    echo "Scheduling finalize.sh after job ${job} completes"
    sbatch --dependency="afterok:${BASH_REMATCH[1]}" "${SRCDIR}/finalize.sh"
  else
    echo "finalize.sh failed to schedule, sbatch failed to return job id for fetch.sh"
    exit 1
  fi
fi

echo "Done."
