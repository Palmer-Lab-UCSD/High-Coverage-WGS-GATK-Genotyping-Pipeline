#!/bin/bash

#### read in declared HPC environment variables
software=${software}
dir_path=${dir_path}
reference_genome=${reference_genome}
sample_name_list=${sample_name_list}
interval=${interval}

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

if [ ${java} = "ERROR" ] || [ ${GATK} = "ERROR" ] || [ ! -f ${java} ] || [ ! -f ${GATK} ]; then
	echo "Error: software_location"
	exit 1
fi

cd ${HOME}

################ GATK to do Variant Calling ################
echo "-----------   GATK to do Variant Calling   -----------"
START=$(date +%s)

echo -e "\n-----run file: ${interval} > ${vcf_dir}/${interval}.vcf.gz-----"
${java} -Xmx50G \
	-jar ${GATK} HaplotypeCaller  \
	-R ${reference_genome} \
	-I ${bam_file} \
	-L ${interval} \
	-O ${vcf_dir}/${interval}.vcf.gz

while [ "$(jobs -rp | wc -l)" -gt 0 ]; do
   sleep 60
done
END=$(date +%s)
echo "Variant Calling GATK Time elapsed: $(( $END - $START )) seconds"