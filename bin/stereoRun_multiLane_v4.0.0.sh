#!/bin/bash

if [[ $# -lt 12 ]];then
    echo
    echo "usage: sh $0 -m maskFile -1 read1 -2 read2 -g indexedGenome -a annotationFile -o outDir -i image -t threads -s visualSif
    -m stereochip mask file
    -1 fastq file path of read1, if there are more than one fastq file, please separate them with comma, e.g:lane1_read_1.fq.gz,lane2_read_1.fq.gz
    -2 fastq file path of read2, if there are more than one fastq file, please separate them with comma, e.g:lane1_read_2.fq.gz,lane2_read_2.fq.gz
    -g genome that has been indexed by star
    -a annotation file in gff or gtf format, the file must contain gene and exon annotation, and the
    -o output directory path
    -i image directory path, must contains SN*.tar.gz and SN*.json file generated by ImageQC software, not requested
    -t thread number will be used to run this pipeline
    -s sif format file of the visual softwares
    -p parameters for semi-auto-re-registration"
    echo
    exit
fi

threads=8

while [[ -n "$1" ]]
do
    case "$1" in
        -m) maskFile="$2"
            shift ;;
        -1) read1="$2"
            shift ;;
        -2) read2="$2"
            shift ;;
        -g) genome="$2"
            shift ;;
        -a) annotation="$2"
            shift ;;
        -o) outDir="$2"
            shift ;;
        -i) image="$2"
            shift ;;
        -t) threads="$2"
            shift ;;
        -s) visualSif="$2"
            shift ;;
        -p) parameters="$2"
            shift ;;
    esac
        shift
done

#software check
if [ `command -v singularity` ]
then
    singularityPath=`command -v singularity`
    echo `date` " singularity check: pass and path is ${singularityPath}"
else
    echo `date` " singularity check: singularity does not exits, please verify that you have installed singularity and exported it to system PATH variable"
    exit
fi

if [[ -n $visualSif ]]
then
    echo `date` " visualSif check: file exists and path is ${visualSif}"
else
    echo `date` " visualSif check: file does not exists, please verify that your visualSif file in the current directory or the path given by the option -s is correct."
fi

if [[ ! -d $outDir ]];then
    mkdir -p $outDir
fi

#basic information get
maskname=$(basename $maskFile)
SNid=${maskname%%.*}

maskdir=$(dirname $maskFile)
annodir=$(dirname $annotation)
imagdir=$(dirname $image)

#create result path
##result path
result_00mapping=${outDir}/00.mapping
result_01merge=${outDir}/01.merge
result_02count=${outDir}/02.count
result_03register=${outDir}/03.register
result_04tissuecut=${outDir}/04.tissuecut
result_05spatialcluster=${outDir}/05.spatialcluster
result_06saturation=${outDir}/06.saturation
result_07report=${outDir}/07.report
arr_result=( $result_00mapping $result_01merge $result_02count $result_03register $result_04tissuecut $result_05spatialcluster $result_06saturation $result_07report )
for each in "${arr_result[@]}";
do
    if [[ ! -d $each ]];then
        mkdir -p $each
    fi
done


#barcode mapping and star alignment.
echo `date` " barcode mapping, adapter filter and RNA alignment start......"
read1Lines=(`echo $read1 | tr ',' ' '`)
read2Lines=(`echo $read2 | tr ',' ' '`)
fqbases=()
starBams=()
bcStat=()
bcLogFinalOut=()
bcReadsCounts=()
fqNumber=`echo ${#read1Lines[@]}`

if [[ $parameters ]]
then
    echo `date` " manualParameterForRegistration check: parameter exists and parameter is ${parameters}"
    barcodeReadsCounts=${result_00mapping}/${SNid}.barcodeReadsCount.txt
    geneExp=${result_02alignment}/GetExp/barcode_gene_exp.txt
    
    imageQC=$(find ${image} -maxdepth 1 -name ${SNid}*.json | head -1)
    image4register=$(find ${image} -maxdepth 1 -name *.tar.gz | head -1)

    echo `date` " manual(semi-auto) registration start......"
    export SINGULARITY_BIND=$outDir
    singularity exec ${visualSif} manualRegister \
        -i ${result_03register} \
        $patameters && \
    
    echo `date` " tissueCut start......."
    export SINGULARITY_BIND=$outDir,$annodir,$image

    singularity exec ${visualSif} tissuecut \
        --dnbfile ${barcodeReadsCount} \
        -i ${geneExp} \
        -o ${result_04tissuecut} \
        -s ${result_03register}/7_result \
        -t tissue \
        --platform T10 \
        --snId ${SNid} 

else
    ulimit -c 100000000000
    for i in $(seq 0 `expr $fqNumber - 1`)
    do
        fqname=$(basename ${read1Lines[i]})
        fqdir=$(dirname ${read1Lines[i]})
        fqbase=${fqname%%.*}
        fqbases[i]=$fqbase
        bcPara=${result_00mapping}/${fqbase}.bcPara
        barcodeReadsCount=${result_00mapping}/${fqbase}.barcodeReadsCount.txt #"0.barcodeReadsCount.txt" in wdl
        echo "in=${maskFile}" > $bcPara
        echo "in1=${read1Lines[i]}" >> $bcPara
        echo "in2=${read2Lines[i]}" >> $bcPara
        echo "encodeRule=ACTG" >> $bcPara
        echo "action=4" >> $bcPara
        echo "barcodeReadsCount=${barcodeReadsCount}" >> $bcPara
        echo "platform=T10" >> $bcPara
        echo "out=${fqbase}" >> $bcPara
        echo "barcodeStart=0" >> $bcPara
        echo "barcodeLen=25" >> $bcPara
        echo "umiStart=25" >> $bcPara
        echo "umiLen=10" >> $bcPara
        echo "umiRead=1" >> $bcPara
        echo "mismatch=1" >> $bcPara
        echo "useF14" >> $bcPara
        echo "bcNum=638759403" >> $bcPara
        export SINGULARITY_BIND=$outDir,$fqdir,$maskdir
        echo " export SINGULARITY_BIND=$outDir,$fqdir,$maskdir "
        echo  " ~~~ mapping - $fqname ~~~"
        singularity exec ${visualSif} mapping \
            --outSAMattributes spatial \
            --outSAMtype BAM SortedByCoordinate \
            --genomeDir ${genome} \
            --runThreadN ${threads} \
            --outFileNamePrefix ${result_00mapping}/${fqbase}. \
            --sysShell /bin/bash \
            --stParaFile ${bcPara} \
            --readNameSeparator \" \" \
            --limitBAMsortRAM 63168332971 \
            --limitOutSJcollapsed 10000000 \
            --limitIObufferSize=280000000 \
            --outBAMsortingBinsN 50 \
            > ${result_00mapping}/${fqbase}_barcodeMap.stat &&\

        starBam=${result_00mapping}/${fqbase}.Aligned.sortedByCoord.out.bam
        starBams[i]=$starBam
        bcStat[i]=${result_00mapping}/${fqbase}_barcodeMap.stat
        bcFinalOut[i]=${result_00mapping}/${fqbase}.Log.final.out
        bcReadsCounts[i]=$barcodeReadsCount
    done

    bcReadsCountsStr=$( IFS=','; echo "${bcReadsCounts[*]}" )
    starBamsStr=$( IFS=','; echo "${starBams[*]}" )
    bcFinalOutStr=$( IFS=','; echo "${bcFinalOut[*]}" )
    bcStatStr=$( IFS=','; echo "${bcStat[*]}" )
    #merge barcode reads count file
    echo `date` " merge barcode reads count tables start......"
    export SINGULARITY_BIND=$outDir
    barcodeReadsCounts=${result_01merge}/${SNid}.barcodeReadsCount.txt
    singularity exec ${visualSif} merge \
        --in $bcReadsCountsStr \
        --out $barcodeReadsCounts \
        --action 2 &&\

    #annotation and deduplication
    echo `date` " annotation and deduplication start......"
    export SINGULARITY_BIND=$outDir,$annodir
    geneExp=${result_02count}/${SNid}.raw.gef
    saturationFile=${result_02count}/${SNid}_raw_barcode_gene_exp.txt
    singularity exec ${visualSif} count \
        -i ${starBamsStr} \
        -o ${result_02count}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam \
        -a ${annotation} \
        -s ${result_02count}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam.summary.stat \
        -e ${geneExp} \
        --sat_file ${saturationFile} \
        --umi_on \
        --save_lq \
        --save_dup \
        -c ${threads} \
        -m 128 &&\

    if [[ -n $image ]]
    then
        #firstly do registration, then cut the gene expression matrix based on the repistration result
        echo `date` " registration and tissueCut start......."
        export SINGULARITY_BIND=$outDir,$annodir,$image
        imageQC=$(find ${image} -maxdepth 1 -name ${SNid}*.json | head -1)
        image4register=$(find ${image} -maxdepth 1 -name *.tar.gz | head -1)
        echo "register parameter $imageQC ; $image4register ; $geneExp"
        singularity exec ${visualSif} register \
            -i ${image4register} \
            -c ${imageQC} \
            -v ${geneExp} \
            -o ${result_03register} &&\
        echo `date` "   tissuecut start......."
            singularity exec ${visualSif} tissueCut \
                --dnbfile ${barcodeReadsCount} \
                -i ${geneExp} \
                -o ${result_04tissuecut} \
                -s ${result_03register}/7_result \
                -t tissue \
                --platform T10 \
                --snId ${SNid} &&\
        echo `date` " tissueCut finish"
    else
        #cut the gene expression matrix directly
        echo `date` " there is no image, tissueCut start......."
        singularity exec ${visualSif} tissuecut \
            --dnbfile ${barcodeReadsCounts} \
            -i ${geneExp} \
            -o ${result_04tissuecut} \
            -t tissue \
            --platform T10 \
            --snId ${SNid} &&\
        echo `date` " tissueCut finish"
    fi
fi

#spatialCluster
echo `date` "   spatialCluster start......." 
singularity exec ${visualSif} spatialCluster \
    -i ${result_04tissuecut}/${SNid}.tissue.gef \
    -o ${result_05spatialcluster}/${SNid}.spatial.cluster.h5ad \
    -s 200 &&\

#saturation
echo `date` " saturation start ......"
singularity exec ${visualSif} saturation \
    -i ${saturationFile} \
    --tissue ${result_04tissuecut}/${SNid}.tissue.gef \
    -o ${result_06saturation} \
    --bcstat ${bcStat} \
    --summary ${result_02count}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam.summary.stat &&\


#generate report file in json format
echo `date` " report generation start......"
export SINGULARITY_BIND=$outDir
if [[ -n ${result_04tissuecut}/tissue_fig/${SNid}.ssDNA.rpi ]] && [[ -e ${result_04tissuecut}/tissue_fig/${SNid}.ssDNA.rpi ]];
then
    singularity exec ${visualSif} report \
        -m ${bcStatStr} \
        -a ${bcFinalOutStr} \
        -g ${result_02count}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam.summary.stat \
        -l ${result_04tissuecut}/tissuecut.stat \
        -n ${result_04tissuecut}/${SNid}.gef \
        -d ${result_05spatialcluster}/${SNid}.spatial.cluster.h5ad \
        -t ${result_06saturation}/plot_200x200_saturation.png \
        -b ${result_04tissuecut}/tissue_fig/scatter_200x200_MID_gene_counts.png \
        -v ${result_04tissuecut}/tissue_fig/violin_200x200_MID_gene.png \
        -i ${result_04tissuecut}/tissue_fig/${SNid}.ssDNA.rpi \
        -o ${result_07report} \
        -r standard_version \
        --pipelineVersion SAW_v4.0.0 \
        -s ${SNid} &&\
    echo `date` " report finish "
else
    singularity exec ${visualSif} report \
        -m ${bcStatStr} \
        -a ${bcFinalOutStr} \
        -g ${result_02count}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam.summary.stat \
        -l ${result_04tissuecut}/tissuecut.stat \
        -n ${result_04tissuecut}/${SNid}.gef \
        -d ${result_05spatialcluster}/${SNid}.spatial.cluster.h5ad \
        -t ${result_06saturation}/plot_200x200_saturation.png \
        -b ${result_04tissuecut}/tissue_fig/scatter_200x200_MID_gene_counts.png \
        -v ${result_04tissuecut}/tissue_fig/violin_200x200_MID_gene.png \
        -o ${result_07report} \
        -r standard_version \
        --pipelineVersion SAW_v4.0.0 \
        -s ${SNid} &&\
    echo `date` " report finish "
fi

echo `date` " all done "
