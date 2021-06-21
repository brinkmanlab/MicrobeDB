#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-finalize

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