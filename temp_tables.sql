CREATE TEMPORARY TABLE summary_noid
(
    "uid"                 TEXT NOT NULL, -- Foreign key to assembly table
    "seqid"               TEXT NOT NULL, -- Replicon Id
    "accession"           TEXT,          -- Replicon accession
    "name"                TEXT,          -- Replicon name
    "description"         TEXT,          -- Replicon description
    "type"                TEXT,          -- Replicon type (chromosome/plasmid)
    "molecule_type"       TEXT,          -- Molecule type [DNA/RNA]
    "sequence_version"    INTEGER,       -- Version of replicon sequence
    "gi_number"           INTEGER,       --
    "cds_count"           INTEGER,       -- # of CDS features
    "gene_count"          INTEGER,       -- # of gene features
    "rna_count"           INTEGER,       -- # of xRNA features
    "repeat_region_count" INTEGER,       -- # of repeat_region features
    "length"              INTEGER,       -- Length of replicon sequence
    "source"              TEXT,          -- Replicon source
    UNIQUE (uid, seqid)
);

CREATE TEMPORARY TABLE replicon_idx
(
    "uid"    TEXT NOT NULL, -- Foreign key to assembly table
    "seqid"  TEXT NOT NULL, -- Sequence ID
    "path"   TEXT,          -- Path to dataset relative to the database
    "format" TEXT,          -- Format of dataset
    "suffix" TEXT           -- Filename suffix excluding extension, describes file content
);