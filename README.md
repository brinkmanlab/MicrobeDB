# MicrobeDB

## How to access

MicrobeDB is distributed using the CERN VM File System (CVMFS). Docker and CSI deployment recipes are available in `./destinations`. The recipes are
executed by [Terraform](https://www.terraform.io/).

Docker may fail to unmount CVMFS during shutdown, run `sudo fusermount -u ./microbedb/mount` if you encounter `transport endpoint is not connected`
errors.

### OSX Peculiarities

OSX does not natively support Docker, it runs Docker within a Linux virtual machine. This workaround means that support is limited to only the most
basic use case. While mounting MicrobeDB via CVMFS, it will fail with an error.

To work around this CVMFS must be installed and configured manually. First ensure that [FUSE](http://osxfuse.github.io/) is enabled by
running `kextstat | grep -i fuse`. Download the [CVMFS package](https://ecsft.cern.ch/dist/cvmfs/cvmfs-2.8.0/cvmfs-2.8.0.pkg). Install the pkg and
reboot. Copy [../destinations/docker/cvmfs.config](../destinations/docker/cvmfs.config) to `/etc/cvmfs/default.local`.
Copy [./microbedb.brinkmanlab.ca.pub](./microbedb.brinkmanlab.ca.pub) to `/etc/cvmfs/keys/microbedb.brinkmanlab.ca.pub`. Ensure everything is
configured properly by running `sudo cvmfs_config chksetup`. You **MUST** mount the CVMFS repository under a shared folder as configured in your
Docker settings for it to be accessible by Docker. By default `/tmp` should be included as a shared folder and you can mount the repository
to `/tmp/microbedb`. Ensure `/tmp/microbedb` exists and run `sudo mount -t cvmfs microbedb.brinkmanlab.ca /tmp/microbedb`.

## Schema documentation

Run `sqlite3 microbedb.sqlite '.schema'` to view documentation of the various tables and columns. The assembly table is largely undocumented because
NCBI does not document their data schemas.

## Working with taxonomy data

Use SQLite recursive query to determine if tax_id is subclass of ancestor. The following returns 1 if the query_tax_id is a subclass of
ancestor_tax_id:

```sqlite
WITH RECURSIVE subClassOf(n) AS (
    VALUES (query_tax_id)
    UNION
    SELECT parent_tax_id
    FROM taxonomy_nodes,
         subClassOf
    WHERE taxonomy_nodes.tax_id = subClassOf.n
      AND taxonomy_nodes.tax_id != ancestor_tax_id
)
SELECT 1
FROM subClassOf
WHERE n = ancestor_tax_id
LIMIT 1;
```

## Build requirements

- [bash](https://www.gnu.org/software/bash/) with filefuncs extension
- [yq](https://pypi.org/project/yq/) which also installs the xq executable
- [jq](https://stedolan.github.io/jq/download/) compiled with ONIGURUMA regex libary
- [Entrez CLI](https://www.ncbi.nlm.nih.gov/books/NBK179288/)
- [SQLite3](https://www.sqlite.org/download.html)
- [GNU awk](https://www.gnu.org/software/gawk/)
- [parallel](https://www.gnu.org/software/parallel/)
- [gzip](https://www.gnu.org/software/gzip/)
- [biopython.convert](https://pypi.org/project/biopython.convert/)
- [rsync](https://rsync.samba.org/)

Ensure the `find` command supports `-empty` by running `find --help | grep '-empty'`. The most recent CVMFS commit of the repository must be mounted
on all compute nodes.
`cvmfs_config` must be accessible on all compute nodes.

## Project Layout

- `destinations/*` - terraform modules to deploy a CVMFS client configured with microbedb to various environments
- `update.sh` - Script to sync data with NCBI for a CVMFS server
- `init_env.sh` - Script to install dependencies for `update.sh`
- `fetch.sh` - Executed by `update.sh` per chunk of datasets returned by Entrez
- `finalize.sh` - Executed by `update.sh` once all invocations of `fetch.sh` have completed
- `resume.sh` - Script to allow resuming execution of `fetch.sh` invocations in the event that any fail. This script is copied to the job directory
  by `update.sh` and is intended to be executed from there.
- `schema.sql` - Database schema
- `temp_tables.sql` - Temporary table schema used by `fetch.sh`
- `subclassOf.sh` - Example utility to query database taxonomy data