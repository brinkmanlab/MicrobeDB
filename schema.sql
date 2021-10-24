CREATE TABLE assembly
    --- Results from querying NCBI Entrez Assembly database
(
    -- Column list order must match order stated in fetch.sh line #39
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
    -- Column list order must match order stated in fetch.sh line #170
    "id"                  INTEGER PRIMARY KEY,                                         -- Alias of rowid
    "uid"                 TEXT REFERENCES assembly ("uid") ON DELETE CASCADE NOT NULL, -- Foreign key to assembly table
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
    "uid"      TEXT REFERENCES assembly ("uid") ON DELETE CASCADE NOT NULL,        -- Foreign key to assembly table
    "replicon" INTEGER REFERENCES summaries ("id") ON DELETE CASCADE,              -- Foreign key to summary table, NULL when dataset represents all replicons
    "path"     TEXT                                               NOT NULL UNIQUE, -- Path to dataset relative to the database
    "format"   TEXT                                               NOT NULL,        -- Format of dataset (file extension)
    "suffix"   TEXT                                               NOT NULL,        -- Filename suffix excluding extension, describes file content
    "checksum" TEXT,                                                               -- MD5 Checksum of dataset (or compressed dataset) as reported by NCBI
    "parent"   TEXT REFERENCES datasets ("path") ON DELETE CASCADE                 -- Reference to derivative dataset
);

CREATE TABLE taxonomy_names
    --- Names of tax_ids in taxonomy_nodes table. Multiple records exist per tax_id.
(
    tax_id      INTEGER, -- the id of node associated with this name
    name_txt    TEXT,    -- name itself
    unique_name TEXT,    -- the unique variant of this name if name not unique
    name_class  TEXT     -- (synonym, common name, ...)
);
CREATE INDEX taxonomy_names_tax_id ON taxonomy_names (tax_id);

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
    division_id                   INTEGER REFERENCES taxonomy_divisions (id) ON DELETE CASCADE, -- see taxonomy_divisions table
    inherited_div_flag            BOOLEAN,                                                      -- 1 if node inherits division from parent
    genetic_code_id               INTEGER REFERENCES taxonomy_gencode (id) ON DELETE CASCADE,   -- see taxonomy_gencode table
    inherited_GC_flag             BOOLEAN,                                                      -- 1 if node inherits genetic code from parent
    mitochondrial_genetic_code_id INTEGER REFERENCES taxonomy_gencode (id) ON DELETE CASCADE,   -- see taxonomy_gencode table
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

CREATE VIEW metadata
    --- Genome metadata. gram_stain data is approximated based on taxonomic relation
AS
SELECT s.uid,
       s.chromosomes,
       s.plasmids,
       (CASE
            WHEN t.phylum IN ('Actinobacteria', 'Chloroflexi', 'Firmicutes') THEN '+'
            WHEN t.genus == 'Chlorobi' OR t.phylum IN
                                          ('Acidobacteria', 'Aquificae', 'Bacteroidetes', 'Deinococcus-Thermus', 'Chlamydiae', 'Cyanobacteria',
                                           'Elusimicrobia', 'Fusobacteria', 'Nitrospirae', 'Planctomycetes', 'Proteobacteria', 'Spirochaetes',
                                           'Tenericutes', 'Thermotogae', 'Verrucomicrobia', 'Dictyoglomi') THEN '-' END) as gram_stain
FROM (
         SELECT uid,
                COUNT(CASE type WHEN 'chromosome' THEN 1 END) as chromosomes,
                COUNT(CASE type WHEN 'plasmid' THEN 1 END)    as plasmids
         FROM summaries
         GROUP BY uid
     ) as s
         JOIN assembly a ON s.uid == s.uid
         JOIN taxonomy t ON t.taxon_id == a.taxid;

CREATE VIEW genomeproject
    --- Depreciated. This view is included for backwards compatibility only.
AS
SELECT assembly.uid                                                                                                              AS gpv_id,
       assemblyaccession                                                                                                         AS assembly_accession,
       assemblyname                                                                                                              AS asm_name,
       replace(speciesname, ' ', '_')                                                                                            AS genome_name,
       json_extract(rs_bioprojects, '$[0].bioprojectaccn')                                                                       AS bioproject,
       biosampleaccn                                                                                                             AS biosample,
       taxid                                                                                                                     AS taxid,
       speciestaxid                                                                                                              AS species_taxid,
       speciesname                                                                                                               AS org_name,
       json_extract(biosource_infraspecieslist, '$[0].sub_type') | '=' |
       json_extract(biosource_infraspecieslist, '$[0].sub_value')                                                                AS infraspecific_name,
       submitterorganization                                                                                                     AS submitter,
       seqreleasedate                                                                                                            AS release_date,
       rtrim(datasets.path, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.[]()-_')                             AS gpv_directory,
       replace(datasets.path, rtrim(datasets.path, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.[]()-_'), '') AS filename,
       ' .' | group_concat(datasets.format, ' .')                                                                                AS file_types,
       NULL                                                                                                                      AS prev_gpv
FROM assembly,
     datasets
WHERE assembly.uid = datasets.uid
GROUP BY datasets.uid;


CREATE VIEW replicon
    --- Depreciated. This view is included for backwards compatibility only.
AS
SELECT id                                                                                        AS rpv_id,
       summaries.uid                                                                             AS gpv_id,
       accession                                                                                 AS rep_accnum,
       sequence_version                                                                          AS rep_version,
       description                                                                               AS definition,
       type                                                                                      AS rep_type,
       gi_number                                                                                 AS rep_ginum,
       rtrim(rtrim(replace(datasets.path, rtrim(datasets.path, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.[]()-_'), ''),
                   'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789[]()-_'), '.') AS file_name,
       ' .' | group_concat(datasets.format, ' .')                                                AS file_types,
       cds_count                                                                                 AS cds_num,
       gene_count                                                                                AS gene_num,
       length                                                                                    AS rep_size,
       rna_count                                                                                 AS rna_num
FROM summaries,
     datasets
WHERE summaries.id = datasets.replicon
GROUP BY datasets.uid;

CREATE VIEW genomeproject_meta
    --- Depreciated. This view is included for backwards compatibility only.
AS
SELECT metadata.uid AS gpv_id,
       gram_stain   AS gram_stain,
       NULL         AS genome_gc,
       NULL         AS patho_status,
       NULL         AS disease,
       NULL         AS genome_size,
       NULL         AS pathogenic_in,
       NULL         AS temp_range,
       NULL         AS habitat,
       NULL         AS shape,
       NULL         AS arrangement,
       NULL         AS endospore,
       NULL         AS motility,
       NULL         AS salinity,
       NULL         AS oxygen_req,
       chromosomes  AS chromosome_num,
       plasmids     AS plasmid_num,
       0            AS contig_num
FROM metadata;

CREATE VIEW genomeproject_checksum
    --- Depreciated. This view is included for backwards compatibility only.
AS
SELECT replace(datasets.path, rtrim(datasets.path, 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.[]()-_'), '') AS filename,
       checksum                                                                                                                  AS checksum,
       uid                                                                                                                       AS gpv_id
FROM datasets;

CREATE TABLE taxonomy
    --- Depreciated. Flattened taxonomy information for each assembly entry. This table is included for backwards compatibility only.
(
    taxon_id     TEXT PRIMARY KEY REFERENCES assembly ("taxid") NOT NULL,
    superkingdom TEXT,
    phylum       TEXT,
    tax_class    TEXT,
    "order"      TEXT,
    family       TEXT,
    genus        TEXT,
    species      TEXT,
    other        TEXT,
    synonyms     TEXT
);