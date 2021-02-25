# MicrobeDB

## How to access
MicrobeDB is distributed using the CERN VM File System (CVMFS).  

## Schema documentation
Run `sqlite3 microbedb.sqlite '.schema'` to view documentation of the various tables and columns.
The assembly table is largely undocumented because NCBI does not document their data schemas.

## Working with taxonomy data

Use SQLite recursive query to determine if tax_id is subclass of ancestor
```sqlite
WITH RECURSIVE
  subClassOf(n) AS (
    VALUES('<query_tax_id>')
    UNION
    SELECT parent_tax_id FROM taxonomy_nodes, subClassOf
     WHERE taxonomy_nodes.tax_id=subClassOf.n AND taxonomy_nodes.tax_id != '<ancestor_tax_id>'
  )
SELECT LAST_VALUE(n) FROM subClassOf;
```

## Build requirements
- [yq](https://pypi.org/project/yq/) which also installs the xq executable
- [jq](https://stedolan.github.io/jq/download/)
- [Entrez CLI](https://www.ncbi.nlm.nih.gov/books/NBK179288/)
- [SQLite3](https://www.sqlite.org/download.html)
- [GNU awk](https://www.gnu.org/software/gawk/)