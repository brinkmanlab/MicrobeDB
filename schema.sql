CREATE TABLE assembly
    --- Results from querying NCBI Entrez Assembly database
(
    "uid"                         TEXT PRIMARY KEY, -- Record Id
    "rsuid"                       TEXT,             -- RefSeq Id
    "gbuid"                       TEXT,             -- GenBank Id
    "assemblyaccession"           TEXT,
    "lastmajorreleaseaccession"   TEXT,
    "latestaccession"             TEXT,
    "chainid"                     TEXT,
    "assemblyname"                TEXT,
    "ucscname"                    TEXT,
    "ensemblname"                 TEXT,
    "taxid"                       TEXT,
    "organism"                    TEXT,
    "speciestaxid"                TEXT,
    "speciesname"                 TEXT,
    "assemblytype"                TEXT,
    "assemblyclass"               TEXT,
    "assemblystatus"              TEXT,
    "assemblystatussort"          INTEGER,
    "wgs"                         TEXT,
    "gb_bioprojects"              TEXT,             -- JSON encoded list of genbank bioproject objects
    "gb_projects"                 TEXT,             -- JSON encoded list of genbank projects
    "rs_bioprojects"              TEXT,             -- JSON encoded list of RefSeq bioproject objects
    "rs_projects"                 TEXT,             -- JSON encoded list of RefSeq projects
    "biosampleaccn"               TEXT,
    "biosampleid"                 TEXT,
--  "biosource"                   object,  -- This structure flattened into biosource_* columns
    "biosource_infraspecieslist"  TEXT,             -- JSON encoded list
    "biosource_sex"               TEXT,
    "biosource_isolate"           TEXT,
    "coverage"                    TEXT,
    "partialgenomerepresentation" TEXT,
    "primary"                     TEXT,
    "assemblydescription"         TEXT,
    "releaselevel"                TEXT,
    "releasetype"                 TEXT,
    "asmreleasedate_genbank"      TEXT,
    "asmreleasedate_refseq"       TEXT,
    "seqreleasedate"              TEXT,
    "asmupdatedate"               TEXT,
    "submissiondate"              TEXT,
    "lastupdatedate"              TEXT,
    "submitterorganization"       TEXT,
    "refseq_category"             TEXT,
    "anomalouslist"               TEXT,             -- JSON encoded list
    "exclfromrefseq"              TEXT,             -- JSON encoded list
    "propertylist"                TEXT,             -- COMMA separated list
    "fromtype"                    TEXT,
--  "synonym"                     object,  -- This structure flattened into synonym_* columns
    "synonym_genbank"             TEXT,
    "synonym_refseq"              TEXT,
    "synonym_similarity"          TEXT,
    "contign50"                   INTEGER,
    "scaffoldn50"                 INTEGER,
    "ftppath_genbank"             TEXT,
    "ftppath_refseq"              TEXT,
    "ftppath_assembly_rpt"        TEXT,
    "ftppath_stats_rpt"           TEXT,
    "ftppath_regions_rpt"         TEXT,
    "sortorder"                   TEXT
--  "meta"                        TEXT  -- Omitted
) WITHOUT ROWID;

CREATE TABLE summaries
    --- Statistics generated from the genomic datasets. One record per replicon.
(
    "id"                  INTEGER PRIMARY KEY,                                         -- Alias of rowid
    "uid"                 TEXT REFERENCES assembly ("uid") ON UPDATE CASCADE NOT NULL, -- Foreign key to assembly table
    "seqid"               TEXT                                               NOT NULL, -- Replicon Id
    "accession"           TEXT,                                                        -- Replicon accession
    "name"                TEXT,                                                        -- Replicon name
    "description"         TEXT,                                                        -- Replicon description
    "type"                TEXT,                                                        -- Replicon type (chromosome/plasmid)
    "molecule_type"       TEXT,                                                        -- Molecule type [DNA/RNA]
    "sequence_version"    INTEGER,                                                     -- Version of replicon sequence
    "gi_number"           INTEGER,                                                     --
    "cds_count"           INTEGER,                                                     -- # of CDS features
    "gene_count"          INTEGER,                                                     -- # of gene features
    "rna_count"           INTEGER,                                                     -- # of xRNA features
    "repeat_region_count" INTEGER,                                                     -- # of repeat_region features
    "length"              INTEGER,                                                     -- Length of replicon sequence
    "source"              TEXT,                                                        -- Replicon source
    UNIQUE (uid, seqid)
);

CREATE TABLE datasets
    --- Listing of all files
(
    "uid"      TEXT REFERENCES assembly ("uid") ON UPDATE CASCADE NOT NULL, -- Foreign key to assembly table
    "replicon" INTEGER REFERENCES summaries ("id") ON UPDATE CASCADE,       -- Foreign key to summary table, NULL when dataset represents all replicons
    "path"     TEXT,                                                        -- Path to dataset relative to the database
    "format"   TEXT,                                                        -- Format of dataset
    "suffix"   TEXT                                                         -- Filename suffix excluding extension, describes file content
);

/* TODO is this table even required?
CREATE TABLE metadata
    --- Genome metadata
(
    "uid" TEXT REFERENCES assembly ("uid") ON UPDATE CASCADE NOT NULL -- Foreign key to assembly table
    TODO gram stain
    TODO chromosome, plasmid counts
);
*/

CREATE TABLE taxonomy_names
    --- Names of tax_ids in taxonomy_nodes table. Multiple records exist per tax_id.
(
    tax_id      INTEGER, -- the id of node associated with this name
    name_txt    TEXT,    -- name itself
    unique_name TEXT,    -- the unique variant of this name if name not unique
    name_class  TEXT     -- (synonym, common name, ...)
);

CREATE TABLE taxonomy_divisions
    --- Taxonomy divisions referenced by taxonomy_nodes table
(
    id       INTEGER PRIMARY KEY, -- taxonomy database division id
    cde      TEXT,                -- GenBank division code (three characters)
    name     TEXT,                -- e.g. BCT, PLN, VRT, MAM, PRI...
    comments TEXT                 -- free-text comments
);

CREATE TABLE taxonomy_gencode
    --- Genbank genetic codes referenced by taxonomy_nodes table
(
    id           INTEGER PRIMARY KEY, -- GenBank genetic code id
    abbreviation TEXT,                -- genetic code name abbreviation
    name         TEXT,                -- genetic code name
    cde          TEXT,                -- translation table for this genetic code
    starts       TEXT                 -- start codons for this genetic code
);

CREATE TABLE taxonomy_nodes
    --- Taxonomic tree of Genbank taxonomy database
(
    tax_id                        INTEGER PRIMARY KEY,                                          -- node id in GenBank taxonomy database
    parent_tax_id                 INTEGER REFERNCES taxonomy_nodes,                             -- parent node id in GenBank taxonomy database
    rank                          TEXT,                                                         -- rank of this node (superkingdom, kingdom, ...)
    embl_code                     TEXT,                                                         -- locus-name prefix; not unique
    division_id                   INTEGER REFERENCES taxonomy_divisions (id) ON UPDATE CASCADE, -- see taxonomy_divisions table
    inherited_div_flag            BOOLEAN,                                                      -- 1 if node inherits division from parent
    genetic_code_id               INTEGER REFERENCES taxonomy_gencode (id) ON UPDATE CASCADE,   -- see taxonomy_gencode table
    inherited_GC_flag             BOOLEAN,                                                      -- 1 if node inherits genetic code from parent
    mitochondrial_genetic_code_id INTEGER REFERENCES taxonomy_gencode (id) ON UPDATE CASCADE,   -- see taxonomy_gencode table
    inherited_MGC_flag            BOOLEAN,                                                      -- 1 if node inherits mitochondrial gencode from parent
    GenBank_hidden_flag           BOOLEAN,                                                      -- 1 if name is suppressed in GenBank entry lineage
    hidden_subtree_root_flag      BOOLEAN,                                                      -- 1 if this subtree has no sequence data yet
    comments                      TEXT                                                          -- free-text comments and citations
);

CREATE TABLE taxonomy_deleted
    --- Taxonomy ids that have been previously deleted
(
    tax_id INTEGER PRIMARY KEY -- deleted node id
);

CREATE TABLE taxonomy_merged
    --- Taxonomy nodes that have been previously merged
(
    old_tax_id INTEGER PRIMARY KEY,                       -- id of nodes which has been merged
    new_tax_id INTEGER REFERENCES taxonomy_nodes (tax_id) -- id of nodes which is result of merging
);

CREATE TABLE taxonomy_citations
    --- Citation information for taxonomy data
(
    cit_id     INTEGER PRIMARY KEY, -- the unique id of citation
    cit_key    TEXT,                -- citation key
    pubmed_id  INTEGER,             -- unique id in PubMed database (0 if not in PubMed)
    medline_id INTEGER,             -- unique id in MedLine database (0 if not in MedLine)
    url        TEXT,                -- URL associated with citation
    text       TEXT,                -- any text (usually article name and authors). The following characters are escaped in this text by a backslash: newline (appear as "\n"), tab character ("\t"), double quotes ('\"'), backslash character ("\\").
    taxid_list TEXT                 -- list of node ids separated by a single space
);

--- TODO genomeproject, genomeproject_meta, replicon, taxonomy table views