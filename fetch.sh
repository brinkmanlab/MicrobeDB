#!/usr/bin/env bash
#SBATCH --account=rpp-fiona
#SBATCH --job-name=microbedb-fetch
set -e                        # Halt on error

# For each chunk of the query results:
# - Populate the assembly and summary tables
# - Download genomic data from NCBI
# - Split assembly gbff into separate files per replicon
# - Generate fna, faa, ffn, and PTT for each replicon

FTP_GENOMES_PREFIX="genomes/" # NCBI rsync server returns error if you try to target root. This variable is the minimum path to avoid that.

echo "Downloading records.."
efetch -mode json -format docsum -start "$SLURM_ARRAY_TASK_ID" -stop "$(expr $SLURM_ARRAY_TASK_ID + $STEP - 1)" <query.xml >$SLURM_ARRAY_TASK_ID.json

# Verify API version
VERSION="$(jq -r '.header.version' $SLURM_ARRAY_TASK_ID.json)"
if [ "$VERSION" != '0.3' ]; then
  echo "Unexpected Entrez API version '$VERSION'. Revalidate schema as what this script expects."
  exit 1
fi

# Populate 'assembly' table
echo "Converting records to CSV.."
jq -r -f <(
  cat <<EOF
.result | del(.uids) | .[] | [
    # The array elements must match the same order as defined in the schema.sql 'assembly' table
    .uid, .rsuid, .gbuid, .assemblyaccession, .lastmajorreleaseaccession,
    .latestaccession, .chainid, .assemblyname, .ucscname, .ensemblname,
    .taxid, .organism, .speciestaxid, .speciesname, .assemblytype,
    .assemblyclass, .assemblystatus, .assemblystatussort, .wgs,
    .gb_bioprojects, .gb_projects, .rs_bioprojects, .rs_projects, .biosampleaccn,
    .biosampleid, .biosource.infraspecieslist, .biosource.sex, .biosource.isolate,
    .coverage, .partialgenomerepresentation, .primary, .assemblydescription, .releaselevel,
    .releasetype, .asmreleasedate_genbank, .asmreleasedate_refseq, .seqreleasedate,
    .asmupdatedate, .submissiondate, .lastupdatedate, .submitterorganization,
    .refseq_category, .anomalouslist, .exclfromrefseq, (.propertylist | join(",")),
    .fromtype, .synonym.genbank, .synonym.refseq, .synonym.similarity, .contign50,
    .scaffoldn50, .ftppath_genbank, .ftppath_refseq, .ftppath_assembly_rpt, .ftppath_stats_rpt,
    .ftppath_regions_rpt, .sortorder
] | map(. | tostring) | @csv
EOF
) $SLURM_ARRAY_TASK_ID.json >assembly_$SLURM_ARRAY_TASK_ID.csv

echo "Populating assembly table.."
sqlite3 -bail "${DBPATH}" <<EOF
PRAGMA foreign_keys = ON;
.mode csv
.import assembly_${SLURM_ARRAY_TASK_ID}.csv assembly
EOF

# Download data
echo "Downloading genomic data.."
# TODO verify that node has most recent commit of CVMFS repo mounted
# Generate file lists per ftp host (there should only be one but if that ever changes..)
rm -f "*_${SLURM_ARRAY_TASK_ID}.files" "${SLURM_ARRAY_TASK_ID}.paths"
jq -r -f <(
  cat <<EOF
.result | del(.uids) | to_entries | .[].value | {uid: .uid} + (
  if (.ftppath_refseq | length) > 0 then
      .ftppath_refseq
  else
      .ftppath_genbank
  end | capture("^ftp://(?<host>[^/]+)/${FTP_GENOMES_PREFIX}(?<path>.*)$")
) |
"\(.uid)\t\(.host)\t\(.path)"
EOF
) $SLURM_ARRAY_TASK_ID.json |
  while IFS=$'\t' read id host path; do
    # For each assembly, prepare directory and add to rsync --files-from
    mkdir -p "${OUTDIR}/${path}"
    echo "${path}" >>"${host}_${SLURM_ARRAY_TASK_ID}.files"         # Append to list of files to rsync
    printf "%s\t$%s" "$id" "$path" >>"${SLURM_ARRAY_TASK_ID}.paths" # Append to tsv of uid to path mappings
  done

# Rsync datasets per ftp host
for files in *_${SLURM_ARRAY_TASK_ID}.files; do
  if [[ "${files}" =~ ^(.*)_[[:digit:]]+\.files$ ]]; then
    if [ -d "${REPOPATH}/${FTP_GENOMES_PREFIX}" ]; then
      # Sync comparing to existing CVMFS repo
      rsync -rvcm --files-from="${files}" --compare-dest="${REPOPATH}/${FTP_GENOMES_PREFIX}" "rsync://${BASH_REMATCH[1]}/${FTP_GENOMES_PREFIX}" "${OUTDIR}"
    else
      # Download everything without comparing
      rsync -rvcm --files-from="${files}" "rsync://${BASH_REMATCH[1]}/${FTP_GENOMES_PREFIX}" "${OUTDIR}"
    fi
  fi
done

echo "Processing downloaded data.."
rm -f "summary_${SLURM_ARRAY_TASK_ID}.csv" "datasets_${SLURM_ARRAY_TASK_ID}.csv"
echo "accession\tindex\ttype" > "replicon_idx_${SLURM_ARRAY_TASK_ID}.tsv"
cat "${SLURM_ARRAY_TASK_ID}.paths" |
  while IFS=$'\t' read -r uid path; do
    # Decompress all files
    echo "Decompressing ${path}.."
    for file in ${OUTDIR}/${path}/*.gz; do
      gzip -d ${file}
    done

    # Split replicons and generate summaries
    echo "Separating replicons ${path}.."
    for f in ${OUTDIR}/${path}/*_genomic.gbff; do
      biopython.convert -si "${f}" genbank "${f%.*}.gbk" genbank |
        gawk -v UID="$uid" -f <(
          cat <<'EOF'
BEGIN {OFS=","}
/^[^#]/ {
# Unpack annotation column $9
split($9, annotation, ";")
for (a in annotation) {
  split(a, kv, "=")
  split(kv[1], annotations[kv[0]], ",")
}

rna_count = 0
# Unpack features column
for (f in annotations["features"]) {
  split(f, kv, ":")
  features[kv[0]]=kv[1]
  if (match(kv[0], "RNA") rna_count += kv[1]  # Sum all RNA types
}

# Output cols, order must match order present in schema.sql 'summary' table
# uid, seqid, accession, name, description, type, molecule_type, sequence_version, gi_number, cds_count, gene_count, rna_count, repeat_region_count, length, source
  print UID, $1, "\"" annotations["accessions"] "\"", annotations["Name"], "\"" annotations["desc"] "\"", "source_plasmid" in annotations ? "plasmid" : "chromosome", annotations["source_mol_type"], annotations["sequence_version"], annotations["gi"], features["cds"], features["gene"], rna_count, features["repeat_region"], $5, "\"" annotations["source"] "\""
}
EOF
        ) | tee >(gawk 'BEGIN{OFS=","}{print "\""$2"\"", NR-1, "gbk"}' >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv") >>"summary_${SLURM_ARRAY_TASK_ID}.csv"

      echo "Generating replicon fna ${path}.."
      biopython.convert -s "${f}" genbank "${f%.*}.fna" fasta |
      gawk 'BEGIN{OFS=","}{print "\""$1"\"", NR-1, "fna"}' >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
      # TODO Extract CDS transcripts, or split protein_gbff?
    done

    for f in ${OUTDIR}/${path}/*.gbk; do
      # Generate PTT files
      # biopython does not support ptt files so we are going to bodge something together using the existing script dependencies
      # https://github.com/biopython/biopython/issues/1725
      # Note the query is JMESPath and not jq
      # GAWK is only required because JMESPath is missing split() https://github.com/jmespath/jmespath.py/issues/159
      biopython.convert -i -q $(cat <<'EOF'
[0].[join(' - 1..', [description, to_string(length(seq))]), join(' ', [to_string(length(features[?type=='CDS' && qualifiers.translation])), 'proteins']), join(`"\t"`, ['Location', 'Strand', 'Length', 'PID', 'Gene', 'Synonym', 'Code', 'COG', 'Product']), (features[?type=='CDS' && qualifiers.translation].[join('..', [to_string(sum([location.start, `1`])), to_string(location.end)]), [location.strand][?@==`1`] && '+' || '-', length(qualifiers.translation[0]), qualifiers.db_xref[?starts_with(@, 'GI')][0] || '-', qualifiers.gene[0] || '-', qualifiers.locus_tag[0] || '-', '-', '-', qualifiers.product[0] ] | [*].join(`"\t"`, [*].to_string(@)) )] | []
EOF
      ) "${f}" genbank >(gawk 'BEGIN{IFS=OFS="\t"} $4!="-"{split($4, a, ":"); $4=a[2]} { print }' > "${f%.*}.ptt") text |
      #Gallaecimonas mangrovi strain HK-28 chromosome, complete genome. - 1..4071977
      #3721 proteins
      #Location        Strand  Length  PID     Gene    Synonym         Code    COG     Product
      #1..4071977      +       466     -       dnaA    DW350_RS00005   -       -       chromosomal replication initiator protein DnaA
      #1348..2451      +       367     -       dnaN    DW350_RS00010   -       -       DNA polymerase III subunit beta
      gawk 'BEGIN{OFS=","}{print "\""$1"\"", NR-1, "ptt"}' >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
    done

    # Generate protein datasets
    for f in ${OUTDIR}/${path}/*_protein.faa; do
      # TODO verify order in genomic.gbff == protein.faa
      biopython.convert -si "${f}" fasta "${f%.*}.faa" fasta |
      gawk 'BEGIN{OFS=","}{print "\""$1"\"", NR-1, "faa"}' >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
    done

    # Generate datasets table
    for f in ${OUTDIR}/${path}/*; do
      if [[ "$f" =~ ^[^_]+_[^_]+_[^_]+_(.+)\.(.+)$ ]]; then
        echo "${UID},,\"${f}\",\"${BASH_REMATCH[2]}\",\"${BASH_REMATCH[1]}\"" >>"datasets_${SLURM_ARRAY_TASK_ID}.csv"
      fi
    done
  done

echo "Populating summary and datasets table.."
sqlite3 -bail "${DBPATH}" <<EOF
PRAGMA foreign_keys = ON;
.mode csv
# To trigger the autoincrement function on the 'id' column, the csv must be imported into a temporary table and copied over
CREATE TEMPORARY TABLE summary_noid AS SELECT * FROM summary WHERE 0;
ALTER TABLE summary_noid DROP COLUMN id;
.import summary_${SLURM_ARRAY_TASK_ID}.csv summary_noid
INSERT INTO summary SELECT NULL, * FROM summary_noid;
.import datasets_${SLURM_ARRAY_TASK_ID}.csv datasets
EOF

# TODO import replicon_idx_XX.csv into temporary table and run update to relink all datasets in datasets table

echo "Done."
