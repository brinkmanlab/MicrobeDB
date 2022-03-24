#!/usr/bin/env bash
#SBATCH --account=rrg-fiona-ad
#SBATCH --time=02:59:00
#SBATCH --job-name=microbedb-process
#SBATCH --mem-per-cpu=2000M
#SBATCH --export=ALL
#SBATCH --mail-type=FAIL
#SBATCH --mail-user=nolan_w@sfu.ca
#SBATCH --output=%x_%a.out
# brinkman-ws+microbedb@sfu.ca
set -e -o pipefail            # Halt on error
shopt -s nullglob

# Skip if no records to process
if [[ $(jq 'length' "${SLURM_ARRAY_TASK_ID}.json") == 0 ]]; then
  echo "No records have a refseq uid of $(jq '.result.uids | length' "${SLURM_ARRAY_TASK_ID}.json") records, skipping processing ${SLURM_ARRAY_TASK_ID}."
  echo $SLURM_ARRAY_TASK_ID >> "completed_tasks"
  exit 0
fi

# Use node local filesystem and copy to OUTDIR upon completion
FINALOUTDIR="$OUTDIR"
OUTDIR="${SLURM_TMPDIR}/outdir"
mkdir -p "$OUTDIR"
WORKDIR="$(pwd)"
cd "$SLURM_TMPDIR"

if [[ -z $LOCAL_FETCH ]]; then
  if [[ -z $CLEAN && ! -d $REPOPATH ]]; then
    # mount repo in userspace if doesn't exist
    export REPOPATH="${WORKDIR}/cvmfs/"
    mkdir -p "$REPOPATH"
    cvmfs2 -o config="$SRCDIR/cvmfs.cc.conf" "$REPONAME" "$REPOPATH"
  fi
  "${SRCDIR}/fetch.sh"
  if [[ "$REPOPATH" = "${WORKDIR}/cvmfs/" ]]; then
    fusermount -u "$REPOPATH"
  fi
else
  # Sync NFS scratch to local scratch
  echo "Copying data from ${FINALOUTDIR} to $OUTDIR"
  cat "${WORKDIR}"/*_"${SLURM_ARRAY_TASK_ID}.files" >"${SLURM_ARRAY_TASK_ID}.files"
  rsync -av --files-from="${SLURM_ARRAY_TASK_ID}.files" --inplace "${FINALOUTDIR}" "${OUTDIR}"
fi

# Populate 'assembly' table
echo "Converting records to CSV.."
jq -r -f <(
  cat <<EOF
.[] | [
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
) "${WORKDIR}/${SLURM_ARRAY_TASK_ID}.json" >"assembly_${SLURM_ARRAY_TASK_ID}.csv"

echo "Processing downloaded data.."
# Generate CSV files containing summary and datasets table information.
# replicon_idx_${SLURM_ARRAY_TASK_ID}.csv is generated as intermediate data
# for the datasets table with the replicon column replaced with the sequence id.
truncate -s0 "datasets_${SLURM_ARRAY_TASK_ID}.csv" "summary_${SLURM_ARRAY_TASK_ID}.csv" "replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
#echo "uid,seqid,accession,name,description,type,molecule_type,sequence_version,gi_number,cds_count,gene_count,rna_count,repeat_region_count,length,source" >"summary_${SLURM_ARRAY_TASK_ID}.csv"
#echo "uid,seqid,path,format,suffix,parent" >"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
TOSCHEMA='@load "filefuncs";BEGIN{OFS=","}/^[^#]/ && (stat("\"" PATH "/" PREFIX "." (NR-1) "." EXT "\"", f) >= 0){print UID, "\""$1"\"", "\"" PATH "/" PREFIX "." (NR-1) "." EXT "\"", EXT, "genomic", PARENT}' # gawk script to convert summary GFF3 to replicon_idx schema, skips record if file doesn't exist
cat "${WORKDIR}/${SLURM_ARRAY_TASK_ID}.paths" |
  while IFS=$'\t' read -r uid path; do
    [[ -d "${OUTDIR}"/"${path}" ]] || continue # Only process paths actually downloaded by rsync

    if [[ -z $SKIP_RSYNC ]]; then
      # Decompress all files
      echo "Decompressing ${path}.."
      parallel gzip -f -d ::: "${OUTDIR}"/"${path}"/*.gz
    fi

    # Generate datasets table
    for f in ${OUTDIR}/${path}/*; do
      if [[ "${f##*/}" =~ ^[^_]+_[^_]+_[^_]+_(.+)\.(.+)$ ]]; then
        format="${BASH_REMATCH[2]}"
        suffix="${BASH_REMATCH[1]}"
        if [[ ! ( $format =~ ^\d+\..*$ ) ]]; then  # do not capture generated files if this script is re-ran. Matches on replicon number (.0.fna) extensions
          echo "${uid},,\"${path}/${f##*/}\",\"${format}\",\"${suffix}\"," >>"datasets_${SLURM_ARRAY_TASK_ID}.csv"
        fi
      fi
    done

    # Split replicons and generate summaries
    # biopython.convert provides the splitting functionality while also outputting a replicon summary gff3
    # gawk takes that GFF3 summary and converts it to the table schema
    # biopython.convert automatically adds an index suffix to the output filename for each replicon output
    # the order of the replicons is stored into replicon_idx_XX.tsv to allow relinking to table record by the second call to gawk
    echo "Separating replicons of ${path}.."
    for f in ${OUTDIR}/${path}/*_genomic.gbff; do
      prefix=${f##*/}
      prefix=${prefix%.*}
      biopython.convert -si "${f}" genbank "${f%.*}.gbk" genbank |
        gawk -v UID="$uid" -f <(
          cat <<'EOF'
BEGIN {FS="\t";OFS=","}
/^[^#]/ {
# Unpack annotation column $9
split($9, annotation, ";")
for (a in annotation) {
  split(annotation[a], kv, "=")
  annotations[kv[1]] = kv[2]
}

features["CDS"] = 0
features["gene"] = 0
features["repeat_region"] = 0
rna_count = 0
split(annotations["features"], feats, ",")
# Unpack features annotation
for (f in feats) {
  split(feats[f], kv, ":")
  features[kv[1]] = kv[2]
  if (match(kv[1], "RNA")) { rna_count += kv[2] }  # Sum all RNA types
}

# Output cols, order must match order present in schema.sql 'summary' table
# uid, seqid, accession, name, description, type, molecule_type, sequence_version, gi_number, cds_count, gene_count, rna_count, repeat_region_count, length, source
  print UID, $1, "\"" annotations["accessions"] "\"", annotations["Name"], "\"" annotations["desc"] "\"", "source_plasmid" in annotations ? "plasmid" : "chromosome", "\"" annotations["source_mol_type"] "\"", annotations["sequence_version"], annotations["gi"], features["CDS"], features["gene"], rna_count, features["repeat_region"], $5, "\"" annotations["source"] "\""
}
EOF
        ) | tee >(gawk -v UID="$uid" -v PREFIX="${prefix}" -v PATH="${path}" -v EXT='gbk' -v PARENT="${f#"$OUTDIR/"}" 'BEGIN{FS=",";OFS=","}{print $1, "\"" $2 "\"", "\"" PATH "/" PREFIX "." (NR-1) "." EXT "\"", EXT, "genomic", PARENT}' >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv") >>"summary_${SLURM_ARRAY_TASK_ID}.csv"

      echo "Generating replicon fna of ${path}.."
      biopython.convert -si "${f}" genbank "${f%.*}.fna" fasta |
        gawk -v UID="$uid" -v PREFIX="${prefix}" -v PATH="${path}" -v EXT='fna' -v PARENT="${f#"$OUTDIR/"}" "$TOSCHEMA" >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
    done

    echo "Generating replicon ffn of ${path}.."
    for f in ${OUTDIR}/${path}/*.gbk; do
      # Recover the seqid from the file directly
      seqid="$(biopython.convert -q '[[0].id]' "${f}" genbank /dev/stdout text)"
      prefix="${f##*/}"
      suffix="${prefix#*_}"
      suffix="${suffix#*_}"
      suffix="${suffix#*_}"
      suffix="${suffix%.*}" # Text after GCF_XXXX_XXXX_
      prefix="${prefix%.*}" # basename of file without extension
      biopython.convert -q "$(
        cat <<'EOF'
[0].let({desc: description, seq: seq}, &features[?type=='gene'].{id:
join('|', [
  (qualifiers.db_xref[?starts_with(@, 'GI')].['gi', split(':', @)[1]]),
  (qualifiers.protein_id[*].['ref', @]),
  (qualifiers.locus_tag[*].['locus', @]),
  join('', [':', [location][?strand==`-1`] && 'c' || '', to_string(sum([location.start, `1`])), '..', to_string(location.end)])
][][]),
seq: extract(seq, @),
description: desc})
EOF
      )" "${f}" genbank "${f%.*}.ffn" fasta
      echo "${uid},${seqid},\"${path}/${prefix}.ffn\",ffn,\"${suffix}\",\"${f#"$OUTDIR/"}\"" >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"

      echo "Generating replicon faa of ${path}.."
      biopython.convert -q "$(
        cat <<'EOF'
[0].let({organism: (annotations.organism || annotations.source)}, &features[?type=='CDS' && qualifiers.translation].{id:
join('|', [
  (qualifiers.db_xref[?starts_with(@, 'GI')].['gi', split(':', @)[1]]),
  (qualifiers.protein_id[*].['ref', @]),
  (qualifiers.locus_tag[*].['locus', @]),
  join('', [':', [location][?strand==`-1`] && 'c' || '', to_string(sum([location.start, `1`])), '..', to_string(location.end)])
][][]),
seq: qualifiers.translation[0],
description: (organism && join('', [qualifiers.product[0] || qualifiers.protein_id[0], ' [', organism, ']']) || qualifiers.product[0])})
EOF
      )" "${f}" genbank "${f%.*}.faa" fasta
      echo "${uid},${seqid},\"${path}/${prefix}.faa\",faa,\"${suffix}\",\"${f#"$OUTDIR/"}\"" >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"

      # Generate PTT files
      # biopython does not support ptt files so we are going to bodge something together using a complex JMESPath
      # https://github.com/biopython/biopython/issues/1725
      # Note the query is JMESPath and not jq
      # Sample PTT for reference
      #Gallaecimonas mangrovi strain HK-28 chromosome, complete genome. - 1..4071977
      #3721 proteins
      #Location        Strand  Length  PID     Gene    Synonym         Code    COG     Product
      #1..4071977      +       466     -       dnaA    DW350_RS00005   -       -       chromosomal replication initiator protein DnaA
      #1348..2451      +       367     -       dnaN    DW350_RS00010   -       -       DNA polymerase III subunit beta
      echo "Generating replicon ptt of ${path}.."
      biopython.convert -q "$(
        cat <<'EOF'
[0].[
  join(' - 1..', [description, to_string(length(seq))]),
  join(' ', [to_string(length(features[?type=='CDS' && qualifiers.translation])), 'proteins']),
  join(`"\t"`, ['Location', 'Strand', 'Length', 'PID', 'Gene', 'Synonym', 'Code', 'COG', 'Product']),
  (features[?type=='CDS' && qualifiers.translation].[
    join('..', [to_string(sum([location.start, `1`])), to_string(location.end)]),
    [location.strand][?@==`1`] && '+' || '-',
    length(qualifiers.translation[0]),
    (qualifiers.db_xref[?starts_with(@, 'GI')].split(':', @)[1])[0] || '-',
    qualifiers.gene[0] || '-',
    qualifiers.locus_tag[0] || '-',
    '-',
    '-',
    qualifiers.product[0]
  ] | [*].join(`"\t"`, [*].to_string(@)) )
] | []
EOF
      )" "${f}" genbank "${f%.*}.ptt" text
      echo "${uid},${seqid},\"${path}/${prefix}.ptt\",ptt,\"${suffix}\",\"${f#"$OUTDIR/"}\"" >>"replicon_idx_${SLURM_ARRAY_TASK_ID}.csv"
    done
  done

echo "Copying data from $OUTDIR to $FINALOUTDIR"
rsync -av --inplace "${OUTDIR}"/* "${FINALOUTDIR}"
rsync -ptgov --inplace ./* "$WORKDIR"

echo "Populating assembly, summaries and datasets tables.."
sqlite3 -bail "${DBPATH}" <<EOF
-- PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 10800000;
.read ${SRCDIR}/temp_tables.sql
.mode csv

BEGIN IMMEDIATE TRANSACTION;
.import assembly_${SLURM_ARRAY_TASK_ID}.csv assembly

.import summary_${SLURM_ARRAY_TASK_ID}.csv summary_noid
INSERT INTO summaries SELECT NULL, * FROM summary_noid;

.import $WORKDIR/checksums_${SLURM_ARRAY_TASK_ID}.csv checksums
.import datasets_${SLURM_ARRAY_TASK_ID}.csv replicon_idx
INSERT INTO datasets SELECT r.uid, NULL, r.path, r.format, r.suffix, c.checksum, r.parent
FROM replicon_idx r LEFT JOIN checksums c ON r.path == c.path;
DELETE FROM replicon_idx;

.import replicon_idx_${SLURM_ARRAY_TASK_ID}.csv replicon_idx
INSERT INTO datasets SELECT r.uid as uid, s.id as replicon, r.path as path, r.format as format, r.suffix as suffix, NULL, r.parent
FROM replicon_idx r JOIN summaries s ON s.uid == r.uid AND s.seqid == r.seqid;

END TRANSACTION;
EOF

echo "Done processing."
echo $SLURM_ARRAY_TASK_ID >> "${WORKDIR}/completed_processing"