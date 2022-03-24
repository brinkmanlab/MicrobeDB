#!/usr/bin/env bash
#SBATCH --account=rrg-fiona-ad
#SBATCH --time=02:59:00
#SBATCH --job-name=microbedb-fetch
#SBATCH --mem-per-cpu=2000M
#SBATCH --export=ALL
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=nolan_w@sfu.ca
#SBATCH --output=%x_%a.out
# brinkman-ws+microbedb@sfu.ca
set -e -o pipefail            # Halt on error
shopt -s nullglob

# For each chunk of the query results:
# - Download genomic data from NCBI
# - Split assembly gbff into separate files per replicon
# - Generate fna, faa, ffn, and PTT for each replicon
# - Populate the assembly, datasets, and summaries tables

FTP_GENOMES_PREFIX="genomes/" # NCBI rsync server returns error if you try to target root. This variable is the minimum path to avoid that.
REPONAME="microbedb.brinkmanlab.ca"
WORKDIR="$(pwd)"

IGNOREEXIT=24
IGNOREOUT='^(file has vanished: |rsync warning: some files vanished before they could be transferred)'
RETRIES=10  # Number of times to reattempt rsync network errors before failing

# Skip if no records to process
if [[ $(jq 'length' "${SLURM_ARRAY_TASK_ID}.json") == 0 ]]; then
  echo "No records have a refseq uid of $(jq '.result.uids | length' "${SLURM_ARRAY_TASK_ID}.json") records, skipping fetch ${SLURM_ARRAY_TASK_ID}."
  exit 0
fi

# Download data
echo "Preparing download lists.."
if [[ -z $CLEAN && -d $REPOPATH && $(cvmfs_config showconfig "$REPONAME" | grep -P 'CVMFS_REPOSITORY_TAG=$|CVMFS_REPOSITORY_DATE=$|CVMFS_ROOT_HASH=$' | wc -l) == 3 ]]; then
  # verify that node has most recent commit of CVMFS repo mounted
  echo "ERROR: $REPONAME targets commit other than trunk. The diff should be against the most recent commit."
  exit 1
fi

# Generate file lists per ftp host (there should only be one but if that ever changes..)
# Output one file path per line to {hostname}_${SLURM_ARRAY_TASK_ID}.files
# ${SLURM_ARRAY_TASK_ID}.paths stores the Entrez uid to path mapping
rm -f *_${SLURM_ARRAY_TASK_ID}.files *_${SLURM_ARRAY_TASK_ID}.md5 "${SLURM_ARRAY_TASK_ID}.paths"
jq -r -f <(
  cat <<EOF
to_entries | .[].value | {uid: .uid} + (
  if (.ftppath_refseq | length) > 0 then
      .ftppath_refseq
  else
      .ftppath_genbank
  end | capture("^ftp://(?<host>[^/]+)/${FTP_GENOMES_PREFIX}(?<path>.*)$")
) |
"\(.uid)\t\(.host)\t\(.path)"
EOF
) "${SLURM_ARRAY_TASK_ID}.json" |
  while IFS=$'\t' read -r id host path; do
    # For each assembly, prepare directory and add to rsync --files-from
    mkdir -p "${OUTDIR}/${path}"
    echo "${path}/md5checksums.txt" >>"${host}_${SLURM_ARRAY_TASK_ID}.md5" # Append to list of md5 checksum files to rsync
    echo "${path}" >>"${host}_${SLURM_ARRAY_TASK_ID}.files"              # Append to list of files to rsync
    printf "%s\t%s\n" "${id}" "${path}" >>"${SLURM_ARRAY_TASK_ID}.paths" # Append to tsv of uid to path mappings
  done

# Convert .md5 to checksums_*.csv
to_checksums () {
  local TOSCHEMA='BEGIN{FS="  ";OFS=","}{file=substr($2,2); sub(/\.gz$/, "", file); print "\""$1"\"", "\"" PATH file "\"", "\"" PATH substr($2,2) "\""}'
  while read -r path; do
    gawk -v PATH=$(dirname $path) "$TOSCHEMA" "${OUTDIR}/${path}" >>"checksums_${SLURM_ARRAY_TASK_ID}.csv"
  done
}

sync () {
  local ret=30
  local retries=$RETRIES
  while (( (ret == 30 || ret == 35) && retries > 0 )); do
    rsync -rvvm --no-g --no-p --chmod=u+rwX,go+rX --ignore-missing-args --files-from="$1" $2 --inplace "rsync://${host}/${FTP_GENOMES_PREFIX}" "${OUTDIR}" 2>&1 | (grep -vP "$IGNOREOUT" || true)
    ret=$?
    ((--retries))
  done
  if (( ret != IGNOREEXIT && ret != 0 )); then
    return $ret
  fi
  return 0
}

truncate -s0 "checksums_${SLURM_ARRAY_TASK_ID}.csv"
if [[ -n $SKIP_RSYNC ]]; then
  echo "Skipping rsync."
  for md5s in *_"${SLURM_ARRAY_TASK_ID}.md5"; do
    to_checksums <"$md5s"
  done
  exit 0
fi

# Rsync datasets per ftp host
# Passes the previously generated {hostname}_${SLURM_ARRAY_TASK_ID}.files to rsyncs '--files-from' argument
for files in *_${SLURM_ARRAY_TASK_ID}.files; do  # for each host
  if [[ "${files}" =~ ^(.*)_[^_]+\.files$ ]]; then  # extract host from file name
    host="${BASH_REMATCH[1]}"
    echo "Downloading genomic data from ${host}.."
    set +e
    if [[ -d $REPOPATH && -z $CLEAN ]]; then
      # Sync comparing to existing CVMFS repo
      if [[ -d "${host}_${SLURM_ARRAY_TASK_ID}.md5" && -f "${REPOPATH}/microbedb.sqlite" ]]; then
        # Download .md5 file for each dataset
        # Use checksums to only download files that have changed
        sync "${host}_${SLURM_ARRAY_TASK_ID}.md5"
        ret=$?
        if (( ret != 0 )); then
          echo "Detected rsync error ($ret) during md5checksums sync."
          exit $ret
        fi
        # Compare checksums and rewrite $files content to explicitly specify individual files
        to_checksums <"${host}_${SLURM_ARRAY_TASK_ID}.md5"
        sqlite3 -bail -readonly "${REPOPATH}/microbedb.sqlite" <<EOF >"$files"
.read ${SRCDIR}/temp_tables.sql
.mode csv
.import checksums_${SLURM_ARRAY_TASK_ID}.csv checksums
.mode list
SELECT c.ncbi_path FROM datasets d LEFT JOIN checksums c ON d.path = c.path WHERE d.path IS NULL OR d.checksum != c.checksum;
EOF
      fi

      # Download remaining files
      sync "${files}" --compare-dest="${REPOPATH}"
      ret=$?
    else
      # Download everything without comparing
      sync "${files}"
      ret=$?
      if (( ret == 0 )); then
        to_checksums <"${host}_${SLURM_ARRAY_TASK_ID}.md5"
      fi
    fi
    if (( ret != 0 )); then
      echo "Detected rsync error ($ret)."
      exit $ret
    fi
    set -e
  else
    echo "Unable to extract host from '$files'"
  fi
done

echo "Done fetch."
echo $SLURM_ARRAY_TASK_ID >> "${WORKDIR}/completed_fetch"