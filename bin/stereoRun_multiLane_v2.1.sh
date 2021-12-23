#!/bin/bash

if [[ $# -lt 12 ]];then
#if [[ $# -lt 12 ]];then
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
result_02alignment=${outDir}/02.alignment
result_00fq=${outDir}/00.fq
if [[ ! -d $result_02alignment ]];then
    mkdir -p $result_02alignment
fi
if [[ ! -d $result_00fq ]];then
    mkdir -p $result_00fq
fi


maskname=$(basename $maskFile)
SNid=${maskname%%.*}
maskdir=$(dirname $maskFile)
annodir=$(dirname $annotation)

#barcode mapping and star alignment.
echo `date` " barcode mapping, adapter filter and RNA alignment start......"
read1Lines=(`echo $read1 | tr ',' ' '`)
read2Lines=(`echo $read2 | tr ',' ' '`)
fqbases=()
starBams=()
bcReadsCounts=()
fqNumber=`echo ${#read1Lines[@]}`



if [[ $parameters ]]
then
    echo `date` " manualParameterForRegistration check: parameter exists and parameter is ${parameters}"
    #merge barcode reads count file
    echo `date` " merge barcode reads count tables start......"
    export SINGULARITY_BIND=$outDir
    barcodeReadsCounts=${result_00fq}/${SNid}.barcodeReadsCount.txt
    singularity exec ${visualSif} semiautoregister \
        -i ${result_02alignment}/GetExp/registration \
        $patameters &&
else
    ulimit -c 100000000000
    for i in $(seq 0 `expr $fqNumber - 1`)
    do
        fqname=$(basename ${read1Lines[i]})
        fqdir=$(dirname ${read1Lines[i]})
        export SINGULARITY_BIND=$outDir,$genome,$fqdir
        fqbase=${fqname%%.*}
        fqbases[i]=$fqbase
        bcPara=${result_02alignment}/${fqbase}.bcPara
        barcodeReadsCount=${result_00fq}/${fqbase}.barcodeReadsCount.txt
        echo "in=${maskFile}" > $bcPara
        echo "in1=${read1Lines[i]}" >> $bcPara
        echo "in2=${read2Lines[i]}" >> $bcPara
        echo "encodeRule=ACTG" >> $bcPara
        echo "out=${fqbase}" >> $bcPara
        echo "action=4" >> $bcPara
        echo "barcodeReadsCount=${barcodeReadsCount}" >> $bcPara
        echo "platform=T10" >> $bcPara
        echo "barcodeStart=0" >> $bcPara
        echo "barcodeLen=25" >> $bcPara
        echo "umiStart=25" >> $bcPara
        echo "umiLen=10" >> $bcPara
        echo "umiRead=1" >> $bcPara
        echo "mismatch=1" >> $bcPara

	echo  " ~~~ mapping - $fqname ~~~"
        singularity exec ${visualSif} mapping \
            --outSAMattributes spatial \
            --outSAMtype BAM SortedByCoordinate \
            --genomeDir ${genome} \
            --runThreadN ${threads} \
            --outFileNamePrefix ${result_02alignment}/${fqbase}. \
            --sysShell /bin/bash \
            --stParaFile ${bcPara} \
            --readNameSeparator \" \" \
            --limitBAMsortRAM 38582880124 \
            --limitOutSJcollapsed 10000000 \
            --limitIObufferSize=280000000 \
            > ${result_00fq}/${fqbase}_barcodeMap.stat &&\
            
        starBam=${result_02alignment}/${fqbase}.Aligned.sortedByCoord.out.bam
        starBams[i]=$starBam
        bcReadsCounts[i]=$barcodeReadsCount
    done

    bcReadsCountsStr=$( IFS=','; echo "${bcReadsCounts[*]}" )
    starBamsStr=$( IFS=','; echo "${starBams[*]}" )

    #merge barcode reads count file
    echo `date` " merge barcode reads count tables start......"
    export SINGULARITY_BIND=$outDir
    barcodeReadsCounts=${result_00fq}/${SNid}.barcodeReadsCount.txt
    singularity exec ${visualSif} merge \
        -i $bcReadsCountsStr \
        --out $barcodeReadsCounts \
        --action 2 &&\

    #annotation and deduplication
    echo `date` " annotation and deduplication start......"
    export SINGULARITY_BIND=$outDir,$annodir
    mkdir -p ${result_02alignment}/GetExp
    geneExp=${result_02alignment}/GetExp/barcode_gene_exp.txt
    saturationFile=${result_02alignment}/GetExp/raw_barcode_gene_exp.txt
    singularity exec ${visualSif} count \
        -i ${starBamsStr} \
        -o ${result_02alignment}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam \
        -a ${annotation} \
        -s ${result_02alignment}/${SNid}.Aligned.sortedByCoord.out.merge.q10.dedup.target.bam.summary.stat \
        -e ${geneExp} \
        --sat_file ${saturationFile} \
        --umi_on \
        --save_lq \
        --save_dup \
        -c ${threads} &&\

    tissueCutResult=${result_02alignment}/GetExp/tissueCut

    if [[ -n $image ]]
    then
        #firstly do registration, then cut the gene expression matrix based on the repistration result
        echo `date` " registration and tissueCut start......."
        export SINGULARITY_BIND=$outDir,$annodir,$image
        regResult=${result_02alignment}/GetExp/registration
        imageQC=$(find ${image} -maxdepth 1 -name ${SNid}*.json | head -1)
        image4register=$(find ${image} -maxdepth 1 -name *.tar.gz | head -1)
        echo "register parameter $imageQC ; $image4register ; $geneExp"
        singularity exec ${visualSif} register \
            -i ${image4register} \
            -c ${imageQC} \
            -v ${geneExp} \
            -o ${regResult} &&\
        singularity exec ${visualSif} tissuecut \
            --dnbfile ${barcodeReadsCount} \
            -i ${geneExp} \
            -o ${tissueCutResult} \
            -s ${regResult}/7_result \
            -t tissue \
            --snId ${SNid}
    else
        #cut the gene expression matrix directly
        echo `date` " there is no image, tissueCut start......."
        singularity exec ${visualSif} tissuecut \
            --dnbfile ${barcodeReadsCounts} \
            -i ${geneExp} \
            -o ${tissueCutResult} \
            -t tissue \
            --snId ${SNid}
    fi
fi
#saturationi
echo `date` " saturation start ......"
singularity exec ${visualSif} saturation \
    -i ${saturationFile} \
	--tissue ${tissueCutResult}/segmentation/${SNid}.tissue.gem.gz \
	-o ${result_02alignment} &&\
mv ${result_02alignment}/*saturation.png ${outDir}

#cellcluster
echo `date` " cellcluster start ......"
singularity exec ${visualSif} cellcluster cellCluster \
    -i ${tissueCutResult}/segmentation/${SNid}.tissue.gem.gz \
    -o ${outDir}/cell_cluster.h5ad \
    --binSize 200 &&\

visualGem=${tissueCutResult}/segmentation/${SNid}.gem.gz
#generate gef format file that can be loaded by the stereomap system
echo `date` " transfer gem format matrix to gef start......"
singularity exec ${visualSif} gem2gef \
    -i $visualGem \
    -o $outDir \
    -t $threads \
    -m $threads \
    -b '1,5,10,15,20,50,80,100,150,200'  &&\

mv $visualGem $outDir/
#generate report file in json format
echo `date` " report generation start......"
singularity exec ${visualSif} jsonreport \
    -p $outdir \
    -o $outdir &&\
singularity exec ${visualSif} report \
    -r $outDir \
    -s $SNid
