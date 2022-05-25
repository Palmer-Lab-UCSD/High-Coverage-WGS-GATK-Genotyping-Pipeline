#!/bin/bash

#### read in declared HPC environment variables
software=${software}
dir_path=${dir_path}
reference_genome=${reference_genome}
sample_name_list=${sample_name_list}
intervals=${intervals}
known_sites=${known_sites}

#### variables initialization
bam_dir=${dir_path}/bams
indelRealign_dir=${dir_path}/indelRealign
BQSR_dir=${dir_path}/BQSR
## !!!!!!!!!!!!!!!!!!!!
## each array job only process one sample
## !!!!!!!!!!!!!!!!!!!!
sample_fastqs=$(head -n ${PBS_ARRAYID} ${sample_name_list} | tail -n 1)
sample_prefix=$(echo ${sample_fastqs} | cut -f 1 -d ' ')
bam_file=${indelRealign_dir}/${sample_prefix}_indelrealigned.bam

#### extract software locations from argument file
java=$(awk 'BEGIN {count = 0} {if ($1 == "Java") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})
GATK=$(awk 'BEGIN {count = 0} {if ($1 == "GATK") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})

if [ ${java} = "ERROR" ] || [ ${GATK} = "ERROR" ] || [ ! -f ${java} ] || [ ! -f ${GATK} ]; then
	echo "Error: software_location"
	exit 1
fi

cd ${HOME}

################ GATK to do BQSR ################
echo "-----------   GATK to do BQSR   -----------"
START=$(date +%s)
module load R

echo -e "\n-----run BaseRecalibrator recal table file: ${bam_file} > ${BQSR_dir}/${sample_prefix}.recal1.table-----"
${java} -Xmx50G \
	-jar ${GATK} BaseRecalibrator \
	-R ${reference_genome} \
	--known-sites ${known_sites} \
	-I ${bam_file} \
	--intervals ${intervals} \
	-O ${BQSR_dir}/${sample_prefix}.recal1.table

echo -e "\n-----run ApplyBQSR file: ${bam_file} > ${BQSR_dir}/${sample_prefix}_recal.bam-----"
${java} -Xmx50G \
	-jar ${GATK} ApplyBQSR \
	-R ${reference_genome} \
	--bqsr-recal-file ${BQSR_dir}/${sample_prefix}.recal1.table\
	--intervals ${intervals} \
	-I ${bam_file} \
	-O ${BQSR_dir}/${sample_prefix}_recal.bam

echo -e "\n-----run BaseRecalibrator recal table file: ${BQSR_dir}/${sample_prefix}_recal.bam > ${BQSR_dir}/${sample_prefix}.recal2.table-----"   
${java} -Xmx50G \
	-jar ${GATK} BaseRecalibrator \
	-R ${reference_genome} \
	--known-sites ${known_sites} \
	--intervals ${intervals} \
	-I ${BQSR_dir}/${sample_prefix}_recal.bam \
	-O ${BQSR_dir}/${sample_prefix}.recal2.table

echo -e "\n-----run AnalyzeCovariates file: ${BQSR_dir}/${sample_prefix}.recal1.table > ${BQSR_dir}/${sample_prefix}.AnalyzeCovariates.pdf-----"   
${java} -Xmx50G \
	-jar ${GATK} AnalyzeCovariates \
	-before ${BQSR_dir}/${sample_prefix}.recal1.table \
	-after ${BQSR_dir}/${sample_prefix}.recal2.table \
	-plots ${BQSR_dir}/${sample_prefix}.AnalyzeCovariates.pdf

while [ "$(jobs -rp | wc -l)" -gt 0 ]; do
	sleep 60
done
END=$(date +%s)
echo "BQSR GATK Time elapsed: $(( $END - $START )) seconds"