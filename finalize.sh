#!/usr/bin/env bash
#SBATCH --account=rrg-fiona-ad
#SBATCH --job-name=microbedb-finalize
#SBATCH --export=ALL
#SBATCH --mail-user=brinkman-ws+microbedb@sfu.ca
#SBATCH --mail-type=END
#SBATCH --mail-type=FAIL
set -e -o pipefail  # Halt on error

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
INSERT OR REPLACE INTO taxonomy ("taxon_id","superkingdom","phylum","tax_class","order","family","genus","species","other","synonyms") VALUES (
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

if [[ -z $NOCOMMIT ]]; then
  #open cvmfs transaction
  ssh -i ${KEYPATH} ${STRATUM0} <<REMOTE
sudo ulimit -n 1048576  # CVMFS holds open file handles on all touched files during a transaction
sudo cvmfs_server transaction microbedb.brinkmanlab.ca
REMOTE

  #rsync all files to stratum0
  rsync -av --no-g -e "ssh -i ${KEYPATH}" "${OUTDIR}"/* "${STRATUM0}:${REPOPATH}"

  #execute remaining tasks on stratum0
  ssh -i "${KEYPATH}" "${STRATUM0}" <<REMOTE
# delete all files not referenced in the database
if [[ -f ${REPOPATH}/microbedb.sqlite ]]; then
  sqlite3 -bail "${DBPATH}" <<EOF | xargs -I % rm -rfdv "${REPOPATH}/%"
.mode list
ATTACH DATABASE '${REPOPATH}/microbedb.sqlite' AS old;
SELECT od.path FROM old.datasets od LEFT JOIN main.datasets d ON d.path = od.path;
EOF
fi

# delete all empty directories
find "$REPOPATH" -type d -empty -delete

# TODO verify all database values and paths
# $COUNT

#commit transaction
sudo cvmfs_server publish -m 'Automatic sync with NCBI' microbedb.brinkmanlab.ca
REMOTE
  echo "Cleaning up download directory.."
  rm -rf "$OUTDIR"
fi

echo "Done."