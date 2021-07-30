#!/usr/bin/env bash

if [[ $# -ne 2 ]]; then
  echo "Use: ./subclassOf.sh <query_tax_id> <ancestor_tax_id>"
  exit -1
fi

sqlite3 -bail microbedb.sqlite <<EOF
WITH RECURSIVE
  subClassOf(n) AS (
    VALUES($1)
    UNION
    SELECT parent_tax_id FROM taxonomy_nodes, subClassOf
     WHERE taxonomy_nodes.tax_id = subClassOf.n AND taxonomy_nodes.tax_id != $2
  )
SELECT 1 FROM subClassOf WHERE n = $2 LIMIT 1;
EOF