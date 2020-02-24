#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/genomeassembly
========================================================================================
 nf-core/genomeassembly Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/genomeassembly
----------------------------------------------------------------------------------------
*/

nextflow.preview.dsl=2

def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/genomeassembly --reads '*_R{1,2}.fastq.gz' -profile docker

    Mandatory arguments:
      --reads                       Path to input data (must be surrounded with quotes)
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Options:
      --singleEnd                   Specifies that the input is single end reads

    References                      If not specified in the configuration file or you wish to overwrite any of the references.
      --fasta                       Path to Fasta reference

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail               Same as --email, except only send mail if the workflow is not successful
      --maxMultiqcEmailFileSize     Theshold size for MultiQC report to be attached in notification email. If file generated by pipeline exceeds the threshold, it will not be attached (Default: 25MB)
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Check if genome exists in the config file
// if (params.genomes && params.genome && !params.genomes.containsKey(params.genome)) {
//     exit 1, "The provided genome '${params.genome}' is not available in the iGenomes file. Currently the available genomes are ${params.genomes.keySet().join(", ")}"
// }

// TODO nf-core: Add any reference files that are needed
// Configurable reference genomes
//
// NOTE - THIS IS NOT USED IN THIS PIPELINE, EXAMPLE ONLY
// If you want to use the channel below in a process, define the following:
//   input:
//   file fasta from ch_fasta
//
// params.fasta = params.genome ? params.genomes[ params.genome ].fasta ?: false : false
// if (params.fasta) { ch_fasta = file(params.fasta, checkIfExists: true) }

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
  custom_runName = workflow.runName
}

if ( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = file(params.multiqc_config, checkIfExists: true)
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)

/*
 * Create a channel for input read files
 */
// if (params.readPaths) {
//     if (params.singleEnd) {
//         Channel
//             .from(params.readPaths)
//             .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true) ] ] }
//             .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
//             .into { read_files_fastqc; read_files_trimming }
//     } else {
//         Channel
//             .from(params.readPaths)
//             .map { row -> [ row[0], [ file(row[1][0], checkIfExists: true), file(row[1][1], checkIfExists: true) ] ] }
//             .ifEmpty { exit 1, "params.readPaths was empty - no input files supplied" }
//             .into { read_files_fastqc; read_files_trimming }
//     }
// } else {
//     Channel
//         .fromFilePairs( params.reads, size: params.singleEnd ? 1 : 2 )
//         .ifEmpty { exit 1, "Cannot find any reads matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\nIf this is single-end data, please specify --singleEnd on the command line." }
//         .into { read_files_fastqc; read_files_trimming }
// }
if( params.reads =~ /.csv$/ ){
    // CSV file of input
} else if ( params.reads =~ /.bam$/ ) {
    // Assume unaligned pacbio
} else if ( params.reads =~ /\{1,2\}.fastq.gz$/ ) {
    // Assume Illumina paired end
} else if ( params.reads =~ /\*.fastq.gz$/ ) {
    // Assume Oxford Nanopore reads
} else {
    exit 1, "Cannot find any read input matching: ${params.reads}\nNB: Path needs to be enclosed in quotes!\n"
}

// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
// TODO nf-core: Report custom parameters here
//summary['Reads']            = params.reads
//summary['Fasta Ref']        = params.fasta
//summary['Data Type']        = params.singleEnd ? 'Single-End' : 'Paired-End'
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile == 'awsbatch') {
  summary['AWS Region']     = params.awsregion
  summary['AWS Queue']      = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if (params.email || params.email_on_fail) {
  summary['E-mail Address']    = params.email
  summary['E-mail on failure'] = params.email_on_fail
  summary['MultiQC maxsize']   = params.maxMultiqcEmailFileSize
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-genomeassembly-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/genomeassembly Workflow Summary'
    section_href: 'https://github.com/nf-core/genomeassembly'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}

/*
 * Helper functions
 */

def check_sequence_input(csv_input) {
}

def get_sequence_input_channels(csv_input) {

    return Channel.fromPath(csv_input)
        .splitCsv(header: ['platform','reads'], skip:1, quote:"'" )
        .branch {
            ipe     : it[0] == 'ipe'     // WGS Illumina paired end library
            pac     : it[0] == 'pac'     // WGS Pacific Biosciences library
            ont     : it[0] == 'ont'     // WGS Oxford Nanopore technologies library
            hic     : it[0] == 'hic'     // Hi-C Illumina paired end library
        }
}

/*
 * Primary workflow
 */
workflow {

    main:
    quality_check_illumina_data

}

workflow quality_check_illumina_data {

    get:
    reads

    main:
    fastqc
    fastqc_screen
    kat_hist
    kat_gcp
    kraken
    mash_screen

}

workflow quality_check_pacbio_data {

    get:
    reads

    main:
    nanoplot
    kraken
    mash_screen
    ycard //chimeric read detection

}

workflow quality_check_ont_data {

    get:
    reads

    main:
    nanoplot
    kraken
    mash_screen
    yacrd // Chimeric read detection

}

workflow quality_check_hic_data {

    get:
    reads

    main:
    fastqc
    kat_hist
    kat_gcp
    kraken
    mash_screen

}

workflow filter_illumina_data {

    get:
    reads
    contaminant_references

    main:
    fastp
    subtract_filter
    seqtk_subsample
    bbmap_normalize

}

workflow filter_pacbio_data {

    get:
    reads
    contaminant_references

    main:
    subtract_filter
    subsample

}

workflow filter_ont_data {

    get:
    reads
    contaminant_references

    main:
    subtract_filter
    subsample

}

workflow assemble_illumina_data {

    get:
    reads

    main:
    spades
    masurca
    abyss

}

workflow assemble_pacbio_data {

    get:
    reads

    main:
    canu
    flye
    redbean
    peregrin
    marvel
    miniasm

}

workflow assemble_ont_data {

    get:
    reads

    main:
    canu
    flye
    redbean
    peregrin
    marvel
    miniasm

}

workflow polish_assembly_with_illumina {

    get:
    assembly
    reads

    main:
    pilon
    ntEdit

}

workflow polish_assembly_with_pacbio {

    get:
    assembly
    reads

    main:
    racon
    quiver

}

workflow polish_assembly_with_ont {

    get:
    assembly
    reads

    main:
    medaka
    nanopolish

}

workflow scaffold_assembly_with_hic {

    get:
    reads
    assembly

    main:
    salsa
}

workflow compare_assemblies {

    get:
    assemblies
    illumina_reads

    main:
    preseq
    quast
    kat_cn_spectra
    frcbam
    busco
    blast
    blobtools
    kraken
    mash_screen
    //bandage

}

/*
 * TODO: Additional workflows and use-cases:
 * - Whole genome amplified data
 * - Trio-binning
 * /

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
        saveAs: { filename ->
            if (filename.indexOf(".csv") > 0) filename
            else null
        }

    output:
    path 'software_versions_mqc.yaml'
    path "software_versions.csv"

    script:
    // TODO nf-core: Get all tools to print their version number here
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    fastqc --version > v_fastqc.txt
    multiqc --version > v_multiqc.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

/*
 * STEP 1 - FastQC
 */
process fastqc {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/fastqc", mode: 'copy',
        saveAs: { filename -> filename.indexOf(".zip") > 0 ? "zips/$filename" : "$filename" }

    input:
    tuple val(name), path(reads)

    output:
    path "*_fastqc.{zip,html}"

    script:
    """
    fastqc --quiet --threads $task.cpus $reads
    """
}

process fastq_screen {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/fastq_screen", mode: 'copy'

    input:
    tuple val(name), path(fastq_file)

    output:
    tuple val(name), path("*_screen.{txt,html}")

    script:
    """
    sed -E 's/^(THREADS[[:blank:]]+)[[:digit:]]+/\1${task.cpus}/' \\
        ${params.fastqscreen_config_file} > fastq_screen.conf
    if [ ! -e "${params.fastqscreen_databases}" ]; then
        fastq_screen --get_genomes
    elif [ "${params.fastqscreen_databases}" != "${fastqscreen_default_databases}" ]; then
        sed -i 's#${fastqscreen_default_databases}#${params.fastqscreen_databases}#' fastq_screen.conf
    fi
    fastq_screen --conf fastq_screen.conf $fastq_file
    """
}

process kat_hist {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/kat_hist", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    path ("*_kat-hist.json")

    script:
    """
    TMP_FASTQ=${name}.fastq
    mkfifo "\${TMP_FASTQ}" && zcat ${reads} > "\${TMP_FASTQ}" &
	sleep 5
	kat hist -t ${task.cpus} -o "${name}-hist" "\${TMP_FASTQ}"
	rm "\${TMP_FASTQ}"
    """

}

process kat_gcp {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/kat_gcp", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    path ("*_kat-gcp.json")

    script:
    """
    TMP_FASTQ=${name}.fastq
    mkfifo "\${TMP_FASTQ}" && zcat ${reads} > "\${TMP_FASTQ}" &
	sleep 5
	kat gcp -t ${task.cpus} -o "${name}-gcp" "\${TMP_FASTQ}"
	rm "\${TMP_FASTQ}"
    """
}

process kat_compare_reads1v2 {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/kat_compare_r1v2", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    path ("*_kat-r1vsr2.json")

    script:
    """
	TMP_FASTQ1=$(mktemp -u --suffix "_R1.fastq")
	TMP_FASTQ2=$(mktemp -u --suffix "_R2.fastq")
	mkfifo "\${TMP_FASTQ1}" && zcat "${reads[0]}" > "\${TMP_FASTQ1}" &
	mkfifo "\${TMP_FASTQ2}" && zcat "${reads[1]}" > "\${TMP_FASTQ2}" &
	sleep 5
	kat comp -n -H 800000000 -I 80000000 -t "${task.cpus}" -o "${name}-r1vsr2" "\${TMP_FASTQ1}" "\${TMP_FASTQ2}"
	kat plot spectra-mx -i -o "${name}-r1vsr2-main.mx.spectra-mx.png" "${name}-r1vsr2-main.mx"
	rm "\${TMP_FASTQ1}" "\${TMP_FASTQ2}"
    """
}

process kat_compare_libs {
    tag "$name_a vs $name_b"
    label 'process_medium'
    publishDir "${params.outdir}/kat_compare_libs", mode: 'copy'

    input:
    tuple val(name_a), path(reads_a), val(name_b), path(reads_b)

    output:
    path ("*_kat-libs.json")

    script:
    """
	TMP_FASTQ1=$(mktemp -u --suffix "_A.fastq")
	TMP_FASTQ2=$(mktemp -u --suffix "_B.fastq")
	mkfifo "\${TMP_FASTQ1}" && zcat $reads_a > "\${TMP_FASTQ1}" &
	mkfifo "\${TMP_FASTQ2}" && zcat $reads_b > "\${TMP_FASTQ2}" &
	sleep 5
	kat comp -H 800000000 -I 80000000 -t "${task.cpus}" -o "${name_a}vs${name_b}-comp" "\${TMP_FASTQ1}" "\${TMP_FASTQ2}"
	rm "\${TMP_FASTQ1}" "\${TMP_FASTQ2}"
    """
}

process kraken {

	tag "$name"
	label 'process_high'
	publishDir "${params.outdir}/kraken_classification", mode: 'copy'

	input:
    val(sequence_type)
    tuple path(name), path(sequences)

	output:
	path("${name}.kraken*.{tsv,rpt,html}")

	script:
    sequence_opts = ''
    if (sequence_type == 'illumina_paired_reads') {
        sequence_opts = '--gzip-compressed --paired'
    } else if (sequence_type == 'pacbio_reads' || sequence_type == 'ont_reads') {
        sequence_opts = '--gzip-compressed'
    } // else if (sequence_type == 'assembly')
    """
    kraken2 --threads "${task.cpus}" --db "${params.kraken_db}" --report "${name}_kraken.rpt" ${sequence_opts} ${sequences} > "${name}_kraken.tsv"
    ktImportTaxonomy <( cut -f2,3 "${name}_kraken.tsv" ) -o "${name}_kraken_krona.html"
    """
}

process mash_screen {

	tag "$name"
	label 'process_medium'
	publishDir "${params.outdir}/mash_screen", mode: 'copy'

	input:
    tuple path(name), path(sequences)

	output:
	path("${name}_mash-screen.tsv")

	script:
    report_all = ${params.mash_screen_report_all} ? '' : '-w'
    """
    mash screen ${report_all} -p ${task.cpus} ${params.mash_screen_sketch} ${sequences} > ${name}_mash-screen.tsv
    """

}

process nanoplot {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/nanoplot", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    path ("output")

    script:
    """
    NanoPlot --bam $reads
    """
}

process fastp {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/fastp", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    tuple val(name), path("*fastp-trimmed_R{1,2}.fastq.gz")
    path ("*_fastp.json")

    script:
    """
    fastp -m -Q -L -w ${task.cpus} -i ${reads[0]} -I ${reads[1]} \\
        -o ${name}_fastp-trimmed_R1.fastq.gz \\
        -O ${name}_fastp-trimmed_R2.fastq.gz \\
        --merged_out ${name}_fastq-merged.fastq.gz \\
        --json ${name}_fastp.json
    """

}

process subtract_filter{

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/subtraction_filtered", mode 'copy'

    input:
    tuple val(name), path(reads)
    path(contaminant_genomes)

    output:
    tuple val(name), path("*_subtracted_R{1,2}.fastq.gz")

    script:
    """
    subtraction_filter () {
        local READS="\$1"
        local REFERENCE="\$2"
        bwa mem -t ${task.cpus} "\$REFERENCE" "\$READS" | samtools sort -@ ${task.cpus} -O BAM -o ${name}_sub.bam -
        samtools index ${name}_sub.bam
        samtools view -@ "${task.cpus}" -F 4 "${name}_sub.bam" | cut -f1 | sort -u -o "${name}_contaminant_aligned_reads.tsv"
        samtools view -@ "${task.cpus}" "${name}_sub.bam" | cut -f1 | sort -u -o "${name}_all_reads.tsv"
        # set difference using bash sort: sort \$1 \$2 \$2 | uniq -u # Keep unique entries to set \$1
        sort --parallel="${task.cpus}" "${name}_all_reads.tsv" "${name}_contaminant_aligned_reads.tsv" "${name}_contaminant_aligned_reads.tsv" | uniq -u > "${name}_uncontaminated_reads.tsv"
        join -t ' ' <( zcat "\${READS[0]}" | paste - - - - | sort -k1,1 ) <( sed 's/^/@/' "${name}_uncontaminated_reads.tsv" ) | tr '\t' '\n' | pigz -c > "${name}_tmp-subtracted_R1.fastq.gz" &
        join -t ' ' <( zcat "\${READS[1]}" | paste - - - - | sort -k1,1 ) <( sed 's/^/@/' "${name}_uncontaminated_reads.tsv" ) | tr '\t' '\n' | pigz -c > "${name}_tmp-subtracted_R2.fastq.gz" &
        wait
        mv "${name}_tmp-subtracted_R1.fastq.gz" "${name}_subtracted_R1.fastq.gz"
        mv "${name}_tmp-subtracted_R2.fastq.gz" "${name}_subtracted_R2.fastq.gz"
        return ( "${name}_subtracted_R1.fastq.gz" "${name}_subtracted_R2.fastq.gz" )
    }

    SEQUENCES=( $reads )
    for CONTAMINANT in ${contaminant_genomes}; do
        READS=subtraction_filter(\$SEQUENCES,\$CONTAMINANT)
    done
    """

}

process seqtk_subsample {

    tag "$name"
    label 'process_low'
    publishDir "${params.outdir}/seqtk_subsampled", mode 'copy'

    input:
    tuple val(name), path(reads)

    output:
    tuple val(name), path("${name}_subsamp_R{1,2}.fastq.gz")

    script:
    """
    seqtk sample -s"${params.seqtk_seed}" "${reads[0]}" "${params.seqtk_fraction}" | gzip -c > "${name}_subsamp_R1.fastq.gz" &
    seqtk sample -s"${params.seqtk_seed}" "${reads[1]}" "${params.seqtk_fraction}" | gzip -c > "${name}_subsamp_R2.fastq.gz"
    wait
    """
}

process bbmap_normalize {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/bbmap_normalized", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    tuple val(name), path("*_bbmap-norm_R{1,2}.fastq.gz")

    script:
    """
    bbnorm.sh t="${task.cpus}" in="${reads[0]}" in2="${reads[1]}" out="${name}_bbmap-norm_R1.fastq.gz" out2="${name}_bbmap-norm_R2.fastq.gz"
    """
}

process spades {

    tag "$name"
    label 'process_high'
    publishDir "${params.outdir}/spades", mode: 'copy'

    input:
    tuple val(name), path(reads)

    output:
    path("assembly")

    script:
    """
    R1READS=( *_R1.fastq.gz )
    R2READS=( *_R2.fastq.gz )

    CONFIG=my_dataset.yaml

    printf -v R1LIST '"%s",\n' "\${R1READS[@]}"
    printf -v R2LIST '"%s",\n' "\${R2READS[@]}"
    R1LIST=\${R1LIST%,*}
    R2LIST=\${R2LIST%,*}
    cat > \$CONFIG <<-EOF
      [
        {
          orientation: "fr",
          type: "paired-end",
          right reads: [
            \$R1LIST
          ],
          left reads: [
            \$R2LIST
          ]
        }
      ]
    EOF

    spades.py -k ${params.spades_kmer_size} --careful --dataset "\$CONFIG" -o "${PREFIX}-spades_assembly"
    """
}


process preseq {

    tag "$name"
    label 'process_medium'
    publishDir "${params.outdir}/preseq", mode: 'copy'

    input:
    tuple val(name), path(alignment)

    output:
    path("_preseq.json")

    script:
    """
    preseq c_curve -s ${params.preseq_step_size} -o ${alignment.baseName}.ccurve -H $alignment
    """
}

process quast {

	tag "${assemblies}"
    label 'process_medium'
	publishDir "${params.output_dir}/quast", mode: 'copy'

	input:
	path( assemblies )

	output:
	path( 'quast_results' )

	script:
	"""
	quast.py -t ${task.cpus} --est-ref-size ${params.estimated_genome_size} ${assemblies}
	"""

}

process kat_cnspectra {

	tag "KAT copy number spectra: ${assembly}"
    label 'process_medium'
	publishDir "${params.output_dir}/kat_cnspectra", mode: 'copy'

	input:
	path(assembly)
	tuple val(name), path(reads)

	output:
	path("${assembly.baseName}vs${name}.cncmp*")

	script:
	"""
	mkfifo ${name}.fastq && zcat ${reads} > ${name}.fastq &
	sleep 5
	kat comp ${params.kat_comp_options} -t ${task.cpus} -o ${assembly.baseName}vs${name}.cncmp ${assembly} ${name}.fastq
	# kat_distanalysis.py -o ${assembly.baseName}vs${name}.cncmp.disteval ${assembly.baseName}vs${name}.cncmp-main.mx
	"""

}

process bwa_index {

	tag "$assembly"
	label 'process_low'

	publishDir "${params.output_dir}/bwa_alignment", mode: 'copy'

	input:
	path (assembly)

	output:
    path ("${assembly}.*")

	script:
	"""
	bwa index ${assembly}
	"""
}

process bwa {

	tag "$name"
    label 'process_medium'
    publishDir "${params.output_dir}/bwa", mode: 'copy'

	input:
    tuple val(name), path(reads)
    path(assembly_indices)

	output:
    tuple path("${assembly}"), path("${assembly.baseName}.${pair_id}.bwa_alignment.bam")
	path("${assembly.baseName}.${pair_id}.bwa_alignment.bam.stats")

	script:
	def prefix = "${assembly.baseName}.bwa-aln"
    """
	bwa mem -t ${task.cpus} ${assembly} ${reads} \
		| samtools sort -@ ${task.cpus} -O BAM -o ${prefix}.bam
	samtools index ${prefix}.bam
	samtools flagstat ${prefix}.bam > ${prefix}.bam.stats
	"""
}

process frcbam {

	tag "$alignment"
	publishDir "${params.output_dir}/frcbam", mode: 'copy'

	input:
    path(alignment)

	output:
	path("${alignment.baseName}_FRC.txt")
	//path("${alignment.baseName}*.txt")

	script:
	"""
	FRC --pe-sam ${alignment} --genome-size ${params.genome_size} --output ${alignment.baseName}
	"""
}

process frc_plot {

    /*
     TODO: Replace by multiqc ?
     */

	tag "FRC plot: all alignments"
	publishDir "${params.output_dir}/frcbam", mode: 'copy'

	input:
	path(feature_counts)

	output:
	path('FRC_Curve_all_assemblies.png')

	script:
	"""
	gnuplot <<EOF
	set terminal png size 1800 1200
	set output 'FRC_Curve_all_assemblies.png'
	set title "FRC Curve" font ",14"
	set key right bottom font ",8"
	set autoscale
	set ylabel "Approximate Coverage (%)"
	set xlabel "Feature Threshold"
	files = "${feature_counts}"
	plot for [data in files] data using 1:2 with lines title data
	EOF
	"""
}

process blast {

	tag "$assembly"
    label 'process_high'
	publishDir "${params.output_dir}/blast", mode: 'copy'

	input:
	path(assembly)

	output:
	path("${assembly.baseName}.blast_alignment.{tsv,html}")
    tuple path("${assembly}"), path("${assembly.baseName}.blast_alignment.tsv")

	script:
	"""
	set_difference () {
		sort "\$1" "\$2" "\$2" | uniq -u
	}
	blastn -task megablast -query ${assembly} -db ${params.blast_db}/nt -outfmt '6 qseqid staxids bitscore std sscinames sskingdoms stitle' \
        -culling_limit 5 -num_threads ${task.cpus} -evalue 1e-25 -out ${assembly.baseName}.blast_alignment.tsv
	ktImportTaxonomy <( cat <( cut -f1,2 ${assembly.baseName}.blast_alignment.tsv | sort -u ) <( set_difference <( grep ">" ${assembly} | cut -c2- ) <(cut -c1 ${assembly.baseName}.blast_alignment.txt ) )) -o ${assembly.baseName}.blast_alignment.html
	"""

}

process blobtools {

	tag "$assembly"
    publishDir "${params.output_dir}/blobtools", mode: 'copy'

	input:
	tuple path(assembly), path(alignment), path(blasthits)

	output:
	path("${assembly.baseName}_blobtools*")

	script:
	"""
	blobtools create -i ${assembly} -b ${alignment} -t ${blasthits} \
		-o ${assembly.baseName}_blobtools --names ${params.blobtools_name_db} --nodes ${params.blobtools_node_db}
	blobtools blobplot -i ${assembly.baseName}_blobtools.blobDB.json -o ${assembly.baseName}_blobtools
	"""
}

process busco {

    /* TODO: Fix Me */

	tag "${line} -> ${assembly}"
    label 'process_medium'
	publishDir "${params.output_dir}/busco", mode: 'copy'

	input:
		tuple path(lineage), path(assembly)

	output:
		path ("run_${asm}_busco_${line}")

	script:
		def line = lineage.baseName
		"""
		source \$BUSCO_SETUP
		run_BUSCO.py -i ${assembly} -l ${lineage} -c ${task.cpus} -m genome -o ${asm}_busco_${line}
		"""
}

/*
 * STEP 2 - MultiQC
 */
process multiqc {
    publishDir "${params.outdir}/MultiQC", mode: 'copy'

    input:
    path multiqc_config from ch_multiqc_config
    // TODO nf-core: Add in log files from your new processes for MultiQC to find!
    path ('fastqc/*') from fastqc_results.collect().ifEmpty([])
    path ('software_versions/*') from software_versions_yaml.collect()
    path workflow_summary from create_workflow_summary(summary)

    output:
    path "*multiqc_report.html" into multiqc_report
    path "*_data"
    path "multiqc_plots"

    script:
    rtitle = custom_runName ? "--title \"$custom_runName\"" : ''
    rfilename = custom_runName ? "--filename " + custom_runName.replaceAll('\\W','_').replaceAll('_+','_') + "_multiqc_report" : ''
    // TODO nf-core: Specify which MultiQC modules to use with -m for a faster run time
    """
    multiqc -f $rtitle $rfilename --config $multiqc_config .
    """
}

/*
 * STEP 3 - Output Description HTML
 */
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    path output_docs from ch_output_docs

    output:
    path "results_description.html"

    script:
    """
    markdown_to_html.r $output_docs results_description.html
    """
}

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/genomeassembly] Successful: $workflow.runName"
    if (!workflow.success) {
      subject = "[nf-core/genomeassembly] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if (workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // TODO nf-core: If not using MultiQC, strip out this code (including params.maxMultiqcEmailFileSize)
    // On success try attach the multiqc report
    def mqc_report = null
    try {
        if (workflow.success) {
            mqc_report = multiqc_report.getVal()
            if (mqc_report.getClass() == ArrayList) {
                log.warn "[nf-core/genomeassembly] Found multiple reports from process 'multiqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
    } catch (all) {
        log.warn "[nf-core/genomeassembly] Could not attach MultiQC report to summary email"
    }

    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.maxMultiqcEmailFileSize.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
          if ( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/genomeassembly] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, email_address ].execute() << email_txt
          log.info "[nf-core/genomeassembly] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if (!output_d.exists()) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}"
    }

    if (workflow.success) {
        log.info "${c_purple}[nf-core/genomeassembly]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[nf-core/genomeassembly]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader(){
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/genomeassembly v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}
