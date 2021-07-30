#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --time=00:15:00
#SBATCH --job-name=microbedb-update
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

# Create unique working directory
WORKDIR=${WORKDIR:-$(mktemp -d ${HOME}/scratch/microbedb_update$(date +'%Y_%m_%d').XXXXXXXXX)}
QUERY=${QUERY:-'("bacteria"[Organism] OR "archaea"[Organism]) AND ("complete genome"[Assembly Level] OR "reference genome"[RefSeq Category])'}
OUTDIR=${OUTDIR:-${WORKDIR}/microbedb}
DBPATH=${DBPATH:-${OUTDIR}/microbedb.sqlite}
REPOPATH=${REPOPATH:-'/cvmfs/microbedb.brinkmanlab.ca'}
SRCDIR="$(dirname "$0")"
STEP=${STEP:-200} # Number of assemblies to process per job
KEYPATH=${KEYPATH:-${HOME}/.ssh/cvmfs.pem}
STRATUM0=${STRATUM0:-'centos@stratum-0.brinkmanlab.ca'}

cd "$WORKDIR"
# TODO module load

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

  # Populate taxonomy table
  sqlite3 -bail "${DBPATH}" 'SELECT uid, taxid FROM assembly;' | while IFS='|' read uid taxid; do
    sqlite3 -bail "${DBPATH}" <<EOF
WITH RECURSIVE
  subClassOf(n, r, name) AS (
    VALUES($taxid, null, null)
    UNION
    SELECT parent_tax_id, rank, name_txt FROM taxonomy_nodes, subClassOf, taxonomy_names
     WHERE taxonomy_nodes.tax_id = subClassOf.n AND taxonomy_names.tax_id == taxonomy_nodes.tax_id AND taxonomy_names.name_class == 'scientific name' AND taxonomy_nodes.rank != 'no rank'
  )
INSERT INTO taxonomy ("taxon_id","superkingdom","phylum","tax_class","order","family","genus","species","other","synonyms") VALUES (
        $taxid,
       (SELECT name FROM subClassOf WHERE r == 'superkingdom'),
       (SELECT name FROM subClassOf WHERE r == 'phylum'),
       (SELECT name FROM subClassOf WHERE r == 'class'),
       (SELECT name FROM subClassOf WHERE r == 'order'),
       (SELECT name FROM subClassOf WHERE r == 'family'),
       (SELECT name FROM subClassOf WHERE r == 'genus'),
       (SELECT name FROM subClassOf WHERE r == 'species'),
       (SELECT name FROM subClassOf WHERE r NOT IN ('superkingdom','phylum','tax_class','order','family','genus','species', NULL)),
       (SELECT GROUP_CONCAT(name_txt, ';') FROM taxonomy_names WHERE tax_id = $taxid AND name_class = 'synonym' );
EOF
  done
fi

if [[ -n $LOCAL ]]; then
  # Run scripts locally rather than sbatch
  echo "Running fetch.sh locally for $COUNT records"
  for ((i = 0; i <= $COUNT; i += $STEP)); do
    STEP=$STEP COUNT=$COUNT OUTDIR="${OUTDIR}" DBPATH="${DBPATH}" SRCDIR="${SRCDIR}" REPOPATH="${REPOPATH}" SLURM_ARRAY_TASK_ID=$i SKIP_RSYNC=$SKIP_RSYNC "${SRCDIR}/fetch.sh"
  done
  echo "Running finalize.sh locally.."
  OUTDIR="${OUTDIR}" DBPATH="${DBPATH}" COUNT=$COUNT REPOPATH="${REPOPATH}" STRATUM0="${STRATUM0}" KEYPATH="${KEYPATH}" "${SRCDIR}/finalize.sh"
else
  # Batch submit fetch.sh
  echo "Submitting $COUNT records with fetch.sh to sbatch"
  job=$(sbatch --export=STEP="${STEP}" --export=COUNT="${COUNT}" --export=OUTDIR="${OUTDIR}" --export=DBPATH="${DBPATH}" --export=SRCDIR="${SRCDIR}" --export=REPOPATH="${REPOPATH}" --array="0-${COUNT}:${STEP}%10" "${SRCDIR}/fetch.sh")
  if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
    echo "Scheduling finalize.sh after job ${job} completes"
    sbatch --export=OUTDIR="${OUTDIR}" --export=DBPATH="${DBPATH}" --export=COUNT="${COUNT}" --export=REPOPATH="${REPOPATH}" --export=STRATUM0="${STRATUM0}" --export=KEYPATH="${KEYPATH}" --dependency="afterok:${BASH_REMATCH[1]}" "${SRCDIR}/finalize.sh"
  else
    echo "finalize.sh failed to schedule, sbatch failed to return job id for fetch.sh"
    exit 1
  fi
fi

echo "Done."
