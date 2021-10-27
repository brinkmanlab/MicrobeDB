#!/usr/bin/env bash
#SBATCH --account=rrg-fiona-ad
#SBATCH --job-name=microbedb-finalize
#SBATCH --time=20:00:00
#SBATCH --mem-per-cpu=2000M
#SBATCH --export=ALL
#SBATCH --mail-type=END
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=nolan_w@sfu.ca
#SBATCH --output=%x.out
# brinkman-ws+microbedb@sfu.ca
set -e -o pipefail  # Halt on error

echo "Generating taxonomy table.."
cp "$DBPATH" "${SLURM_TMPDIR}/microbedb.sqlite"
sqlite3 -bail "${DBPATH}" 'SELECT DISTINCT taxid FROM assembly;' | while IFS='|' read taxid; do
  cat <<EOF
WITH RECURSIVE
  subClassOf(n, r, name) AS MATERIALIZED (
    VALUES($taxid, null, null)
    UNION
    SELECT parent_tax_id, rank, name_txt FROM taxonomy_nodes, subClassOf, taxonomy_names
     WHERE taxonomy_nodes.tax_id = subClassOf.n AND taxonomy_names.tax_id == taxonomy_nodes.tax_id AND taxonomy_names.name_class == 'scientific name' AND taxonomy_nodes.rank != 'no rank'
  )
SELECT
  $taxid,
  (SELECT name FROM subClassOf WHERE r == 'superkingdom' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'phylum' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'class' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'order' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'family' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'genus' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r == 'species' LIMIT 1),
  (SELECT name FROM subClassOf WHERE r NOT IN ('superkingdom','phylum','tax_class','order','family','genus','species', NULL) LIMIT 1),
  (SELECT GROUP_CONCAT(name_txt, ';') FROM taxonomy_names WHERE tax_id = $taxid AND name_class = 'synonym' )
;
EOF
done | cat <(echo '.mode insert taxonomy'; echo 'DELETE FROM taxonomy;') - | sqlite3 -bail -readonly "${SLURM_TMPDIR}/microbedb.sqlite" > "${SLURM_TMPDIR}/taxonomy.sql"
cp "${SLURM_TMPDIR}/taxonomy.sql" .
echo "Populating taxonomy table.."
sqlite3 -bail "${SLURM_TMPDIR}/microbedb.sqlite" <"${SLURM_TMPDIR}/taxonomy.sql"

if [[ -z $CLEAN && -f ${REPOPATH}/microbedb.sqlite ]]; then
  echo "Copying forward any summaries and datasets that were not synced.."
  cat checksums_*.csv > checksums.csv
# TODO needs a multi-way inner join between checksums, summaries, and datasets across old, inserted or ignored into new
#  sqlite3 -bail "${SLURM_TMPDIR}/microbedb.sqlite" <<EOF
#.read ${SRCDIR}/temp_tables.sql
#.import checksums.csv checksums
#PRAGMA foreign_keys = ON;
#ATTACH DATABASE '${REPOPATH}/microbedb.sqlite' AS old;
#BEGIN TRANSACTION;
## copy summaries that weren't synced
#INSERT OR IGNORE INTO main.summaries
#SELECT os.* FROM old.summaries AS os
#INNER JOIN checksums AS c ON os.path = c.path;
#
## copy datasets that weren't synced
#INSERT OR IGNORE INTO main.datasets
#SELECT od.* FROM old.datasets od
#INNER JOIN checksums AS c ON od.path = c.path;
#
#END TRANSACTION;
#EOF
fi

mv "${SLURM_TMPDIR}/microbedb.sqlite" "$DBPATH"

if [[ -z $NOCOMMIT ]]; then
  echo "Opening CVMFS transaction.."
  ssh -i ${KEYPATH} ${STRATUM0} <<REMOTE
sudo bash
ulimit -n 1048576  # CVMFS holds open file handles on all touched files during a transaction
cvmfs_server transaction microbedb.brinkmanlab.ca
if [[ -z "$CLEAN" && -f ${REPOPATH}/microbedb.sqlite ]]; then
  cp ${REPOPATH}/microbedb.sqlite ${REPOPATH}/microbedb.sqlite.old
fi
REMOTE

  echo "rsync all files to stratum0.."
  rsync -av --no-g -e "ssh -i ${KEYPATH}" --rsync-path="sudo rsync" "${OUTDIR}"/* "${STRATUM0}:${REPOPATH}"

  echo "Executing remaining tasks on stratum0.."
  ssh -i "${KEYPATH}" "${STRATUM0}" <<REMOTE
sudo bash
set -e -o pipefail  # Halt on error
if [[ -f ${REPOPATH}/microbedb.sqlite.old ]]; then
  echo "Deleting all files no longer referenced in the database.."
  sqlite3 -bail "${REPOPATH}/microbedb.sqlite" <<EOF | xargs -I % rm -rfdv "${REPOPATH}/%"
.mode list
ATTACH DATABASE '${REPOPATH}/microbedb.sqlite.old' AS old;
SELECT od.path FROM old.datasets od LEFT JOIN main.datasets d ON d.path = od.path;
EOF
  rm -f ${REPOPATH}/microbedb.sqlite.old
fi

echo "Deleting all empty directories.."
find "$REPOPATH" -type d -empty -delete

# query all paths and check existence
echo "Verifying dataset existence.."
sqlite3 -bail "${REPOPATH}/microbedb.sqlite" <<EOF | while read path; do [[ -f "${REPOPATH}/\$path" ]] || echo "WARNING: Dataset in database doesn't exist"; done
.mode list
SELECT path FROM datasets;
EOF
# count total assemblies and compare to $COUNT
DBCOUNT=$(sqlite3 -bail "${REPOPATH}/microbedb.sqlite" 'SELECT count(*) FROM assembly;')
[[ $COUNT == \$DBCOUNT ]] || echo "WARNING: assembly table has more entries than returned by Entrez: \$DBCOUNT > $COUNT"

echo "Committing transaction.."
cvmfs_server publish -m 'Automatic sync with NCBI' microbedb.brinkmanlab.ca
REMOTE
  echo "Cleaning up download directory.."
  [[ -z $KEEP_OUTDIR ]] || rm -rf "$OUTDIR"
fi

echo "Done."