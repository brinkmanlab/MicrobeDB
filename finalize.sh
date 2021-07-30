#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-finalize
#SBATCH --mail-user=brinkman-ws+microbedb@sfu.ca
#SBATCH --mail-type=END
#SBATCH --mail-type=FAIL

#open cvmfs transaction
ssh -i ${KEYPATH} ${STRATUM0} <<REMOTE
sudo cvmfs_server transaction microbedb.brinkmanlab.ca
REMOTE

#rsync all files to stratum0
rsync -av --no-g --no-p -e "ssh -i ${KEYPATH}" "${OUTDIR}"/* "${STRATUM0}:${REPOPATH}"

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
