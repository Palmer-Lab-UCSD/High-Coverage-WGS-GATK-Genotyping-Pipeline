#!/bin/bash

#### read in declared HPC environment variables
software=${software}
dir_path=${dir_path}
reference_genome=${reference_genome}
sample_name_list=${sample_name_list}
interval_list=${interval_list}

#### variables initialization
BQSR_dir=${dir_path}/BQSR
vcf_dir=${dir_path}/vcfs

## !!!!!!!!!!!!!!!!!!!!
## each array job only process one sample
## !!!!!!!!!!!!!!!!!!!!
sample_fastqs=$(head -n ${PBS_ARRAYID} ${sample_name_list} | tail -n 1)
sample_prefix=$(echo ${sample_fastqs} | cut -f 1 -d ' ')
bam_file=${BQSR_dir}/${sample_prefix}_recal.bam

#### extract software locations from argument file
java=$(awk 'BEGIN {count = 0} {if ($1 == "Java") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})
GATK=$(awk 'BEGIN {count = 0} {if ($1 == "GATK") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})
bcftools=$(awk 'BEGIN {count = 0} {if ($1 == "Bcftools") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})
picard=$(awk 'BEGIN {count = 0} {if ($1 == "Picard") {print $3; exit 0;} else count += 1} END {if (count == NR) {print "ERROR"}}' ${software})

if [ ${java} = "ERROR" ] || [ ${GATK} = "ERROR" ]  || [ ${bcftools} = "ERROR" ]  || [ ${picard} = "ERROR" ] || [ ! -f ${java} ] || [ ! -f ${GATK} ] || [ ! -f ${bcftools} ] || [ ! -f ${picard} ]; then
	echo "Error: software_location"
	exit 1
fi

cd ${HOME}

################ Variants filtering ################
echo "-----------   Variants filtering   -----------"
START=$(date +%s)

for interval in ${interval_list[@]}
do 
	echo -e "\n-----run file: SNPs: ${vcf_dir}/${interval}_SNPs.vcf.gz-----"
	${java} -Xmx50G \
		-jar ${GATK} SelectVariants \
		-V ${vcf_dir}/${interval}.vcf.gz \
		-select-type SNP \
		-O ${vcf_dir}/${interval}_SNPs.vcf.gz

	${bcftools} query \
		-f "%CHROM\t%POS\t%QUAL\t%INFO/QD\t%INFO/SOR\t%INFO/FS\t%INFO/MQ\t%INFO/MQRankSum\t%INFO/ReadPosRankSum\t\n" \
		${vcf_dir}/${interval}_SNPs.vcf.gz > ${vcf_dir}/${interval}_SNPs

	${java} -Xmx50G \
		-jar ${GATK} VariantFiltration \
		-V ${vcf_dir}/${interval}_SNPs.vcf.gz \
		-filter "QD < 5.0" --filter-name "QD5" \
		-filter "QUAL < 30.0" --filter-name "QUAL30" \
		-filter "SOR > 3.0" --filter-name "SOR3" \
		-filter "FS > 60.0" --filter-name "FS60" \
		-filter "MQ < 40.0" --filter-name "MQ40" \
		-filter "MQRankSum < -12.5" --filter-name "MQRankSum-12.5" \
		-filter "ReadPosRankSum < -8.0" --filter-name "ReadPosRankSum-8" \
		-O ${vcf_dir}/${interval}_SNPs_temp.vcf.gz

	${java} -Xmx50G \
		-jar ${GATK} SelectVariants \
		-V ${vcf_dir}/${interval}_SNPs_temp.vcf.gz \
		--exclude-filtered true \
		-O ${vcf_dir}/${interval}_SNPs_filtered.vcf.gz

	echo -e "\n-----run file: Indels: ${vcf_dir}/${interval}_Indels.vcf.gz-----"
	${java} -Xmx50G \
		-jar ${GATK} SelectVariants \
		-V ${vcf_dir}/${interval}.vcf.gz \
		-select-type INDEL \
		-O ${vcf_dir}/${interval}_Indels.vcf.gz
			
	${bcftools} query \
		-f "%CHROM\t%POS\t%QUAL\t%INFO/QD\t%INFO/FS\t%INFO/ReadPosRankSum\t\n" \
		${vcf_dir}/${interval}_Indels.vcf.gz > ${vcf_dir}/per_chr/${interval}_Indels

	${java} -Xmx50G \
		-jar ${GATK} VariantFiltration \
		-V ${vcf_dir}/${interval}_Indels.vcf.gz \
		-filter "QD < 5.0" --filter-name "QD5" \
		-filter "QUAL < 30.0" --filter-name "QUAL30" \
		-filter "FS > 200.0" --filter-name "FS200" \
		-filter "ReadPosRankSum < -20.0" --filter-name "ReadPosRankSum-20" \
		-O ${vcf_dir}/${interval}_Indels_temp.vcf.gz

	${java} -Xmx50G \
		-jar ${GATK} SelectVariants \
		-V ${vcf_dir}/${interval}_Indels_temp.vcf.gz \
		--exclude-filtered true \
		-O ${vcf_dir}/${interval}_Indels_filtered.vcf.gz
done

while [ "$(jobs -rp | wc -l)" -gt 0 ]; do
	sleep 60
done

ls ${vcf_dir}/*_filtered.vcf.gz > ${vcf_dir}/filtered.list 

${java} -Xmx50G \
	-jar ${picard} MergeVcfs  \
	-INPUT ${vcf_dir}/filtered.list \
	-OUTPUT ${vcf_dir}/final.vcf.gz

rm ${vcf_dir}/*_SNPs_*
rm ${vcf_dir}/*_Indels_*

while [ "$(jobs -rp | wc -l)" -gt 0 ]; do
   sleep 60
done

END=$(date +%s)
echo "Variants filtering time elapsed: $(( $END - $START )) seconds"
