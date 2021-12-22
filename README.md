# SAW(Stereo-seq Analysis Workflow)
Workflow of analyzing Stereo-Seq transcriptome data

## System Requirements
### Hardware

Stereo-seq Analysis Workflow (SAW) run on Linux systems that meet these minimum requirements:
* 8-core Intel or AMD processor (24 cores recommended)
* 128GB RAM (256GB recommended)
* 1TB free disk space
* 64-bit CentOS/RedHat 7.8 or Ubuntu 20.04

### Software

* singularity
* SAW

#### Install singularity
```
https://sylabs.io/guides/3.8/admin-guide/installation.html

On Red Hat Enterprise Linux or CentOS install the following dependencies:
$ sudo yum update -y && \
     sudo yum groupinstall -y 'Development Tools' && \
     sudo yum install -y \
     openssl-devel \
     libuuid-devel \
     libseccomp-devel \
     wget \
     squashfs-tools \
     cryptsetup

On Ubuntu or Debian install the following dependencies:
$ sudo apt-get update && sudo apt-get install -y \
    build-essential \
    uuid-dev \
    libgpgme-dev \
    squashfs-tools \
    libseccomp-dev \
    wget \
    pkg-config \
    git \
    cryptsetup-bin

Install Go
$ export VERSION=1.14.12 OS=linux ARCH=amd64 && \
    wget https://dl.google.com/go/go$VERSION.$OS-$ARCH.tar.gz && \
    sudo tar -C /usr/local -xzvf go$VERSION.$OS-$ARCH.tar.gz && \
    rm go$VERSION.$OS-$ARCH.tar.gz

$ echo 'export GOPATH=${HOME}/go' >> ~/.bashrc && \
    echo 'export PATH=/usr/local/go/bin:${PATH}:${GOPATH}/bin' >> ~/.bashrc && \
    source ~/.bashrc

Install singularity on CentOS without compile
$ yum install -y singularity
```
#### Get SAW image from dockerHub
```
singularity build SAW_v2.1.0.sif docker://stomics/saw:02.1.0 
```

## Run
### Preparation
```
Before running the Stereo-seq Analysis Workflow, you should prepare the indexed reference as follow:
singularity exec SAW_v2.1.0.sif mapping --runMode genomeGenerate \
    --genomeDir reference/STAR_SJ100 \
    --genomeFastaFiles reference/genome.fa \
    --sjdbGTFfile reference/genes.gtf \
    --sjdbOverhang 99 \
    --runThreadN 12
Then you should get the mask file from our website through the slide number(SN)
```

### Usage
#### stereoRun_singleLane.sh
```
usage: sh stereoRun_singleLane.sh -m maskFile -1 read1 -2 read2 -g indexedGenome -a annotationFile -o outDir -i image -t threads -s visualSif
    -m stereochip mask file
    -1 fastq file path of read1
    -2 fastq file path of read2
    -g genome that has been indexed by star
    -a annotation file in gff or gtf format, the file must contain gene and exon annotation, and also the transript annotation
    -o output directory path
    -i image directory path, must contains SN*.tar.gz and SN*.json file generated by ImageQC software, not required
    -t thread number will be used to run this pipeline
    -s docker image that packed analysis softwares
    -p formatted string for re-start registration, not required
```
#### stereoRun_multiLane.sh
```
usage: sh stereoRun_multiLane.sh -m maskFile -1 read1 -2 read2 -g indexedGenome -a annotationFile -o outDir -i image -t threads -s visualSif
    -m stereochip mask file
    -1 fastq file path of read1, if there are more than one fastq file, please separate them with comma, e.g:lane1_read_1.fq.gz,lane2_read_1.fq.gz
    -2 fastq file path of read2, if there are more than one fastq file, please separate them with comma, e.g:lane1_read_2.fq.gz,lane2_read_2.fq.gz
    -g genome that has been indexed by star
    -a annotation file in gff or gtf format, the file must contain gene and exon annotation, and the 
    -o output directory path
    -i image directory path, must contains SN*.tar.gz and SN*.json file generated by ImageQC software, not required
    -t thread number will be used to run this pipeline
    -s docker image that packed analysis softwares
    -p formatted string for re-start registration, not required
```
### Running example
#### stereoRun_singleLane.sh
```
If only one lane sequencing data was given, run the stereoRun.sh script as follows:
when tissue image was not given:
sh stereoRun_singleLane.sh \
    -m SN.h5 \
    -1 lane_read_1.fq.gz \
    -2 lane_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir
when tissue image was given
sh stereoRun_singleLane.sh \
    -m SN.h5 \
    -1 lane_read_1.fq.gz \
    -2 lane_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir \
    -i image_dir_path
when tissue image was given and auto-semi-register parameters was given
sh stereoRun_singleLane.sh \
    -m SN.h5 \
    -1 lane_read_1.fq.gz \
    -2 lane_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir \
    -i image_dir_path \
    -p parameters_for_re-registrater
```
#### stereoRun_multiLane.sh
```
If more than one lane sequencing data was given, run the stereoRun_multiLane.sh script as follows:
when tissue image was not given:
sh stereoRun_multiLane.sh \
    -m SN.h5 \
    -1 lane1_read_1.fq.gz,lane2_read_1.fq.gz \
    -2 lane1_read_2.fq.gz,lane2_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir
when tissue image was given
sh stereoRun_multiLane.sh \
    -m SN.h5 \
    -1 lane1_read_1.fq.gz,lane2_read_1.fq.gz \
    -2 lane1_read_2.fq.gz,lane2_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir \
    -i image_dir_path
when tissue image was given and auto-semi-register parameters was given
sh stereoRun_multiLane.sh \
    -m SN.h5 \
    -1 lane1_read_1.fq.gz,lane2_read_1.fq.gz \
    -2 lane1_read_2.fq.gz,lane2_read_2.fq.gz \
    -g reference/STAR_SJ100 \
    -a reference/genes.gtf \
    -s SAW_v2.1.0.sif \
    -o outDir \
    -i image_dir_path \
    -p parameters_for_re-registrater
```
