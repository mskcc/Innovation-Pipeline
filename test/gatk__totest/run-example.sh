#!/bin/bash

# Usage:

output_dir=$1

DD=$(date +%d)
MM=$(date +%m)
project="test_gatk_indelrealignment_$MM-$DD"
output_directory=`python -c "import os;print(os.path.abspath('${output_dir}'))"`

# Run test pipeline
../../pipeline-runner.sh \
    ${project} \
    ../../cwl_tools/gatk/IndelRealignment.cwl \
    inputs.yaml \
    ${output_directory} \
    singleMachine
