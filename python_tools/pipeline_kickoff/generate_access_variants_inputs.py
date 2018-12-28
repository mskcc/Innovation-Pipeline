import os
import re
import logging
import argparse
import ruamel.yaml

import pandas as pd

from ..constants import (
    ACCESS_VARIANTS_RUN_FILES_PATH,
    ACCESS_VARIANTS_RUN_PARAMS_PATH,
    ACCESS_VARIANTS_RUN_PARAMS_DELLY_PATH
)


##########
# Pipeline Inputs generation for the ACCESS-Variants pipeline
#
# Todo:
# - better way to ensure proper sort order of samples
# - combine this with create_ scripts
# - singularity
#
# Usage:
#
# generate_access_variants_inputs \
# -pn \
# Variant_Calling_Project \
# -o \
# inputs.yaml \
# -dn /home/patelju1/projects/Juber/HiSeq/5500-FF-new/run-5500-FF/FinalBams/DA-ret-004-pl-T01-IGO-05500-FF-18_bc427_Pool-05500-FF-Tube3-1_L000_mrg_cl_aln_srt_MD_IR_FX_BR.bam \
# -p \
# ./test_pairs.tsv \
# -tb \
# ~/PROJECT_tumor_bams/duplex_bams \
# -nb \
# ~/PROJECT_normal_bams/duplex_bams \
# -sb \
# ~/PROJECT_normal_bams/simplex_bams \
# -cbd \
# ~/ACCESSv1-VAL-20180003_curated_bams \
# -cbs \
# ~/ACCESSv1-VAL-20180003_curated_bams_simplex
# -m


# Regex for finding bam files
BAM_REGEX = re.compile('.*\.bam')
# Delimiter for printing logs
DELIMITER = '\n' + '*' * 20 + '\n'
# Delimiter for inputs file sections
INPUTS_FILE_DELIMITER = '\n\n' + '# ' + '--' * 30 + '\n\n'

logging.basicConfig(
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%m/%d/%Y %I:%M:%S %p',
        level=logging.DEBUG)
logger = logging.getLogger('access_variants_pipeline_kickoff')


def parse_arguments():
    """
    Parse arguments for Variant calling pipeline inputs generation

    :return: argparse.ArgumentParser object
    """
    parser = argparse.ArgumentParser(usage='Generate inputs for either the snps_and_indels.cwl or ACCESS_variants.cwl \
                                           workflow.')

    parser.add_argument(
        '-o',
        '--output_file_name',
        help='Filename for yaml file to be used as pipeline inputs',
        required=True
    )

    parser.add_argument(
        '-pn',
        '--project_name',
        help='Project name for this run',
        required=True
    )

    parser.add_argument(
        '-sv',
        '--structural_variants',
        help='Whether to include SV calling. (This will include the Delly params in the inputs file. \
            Inputs should be paired with full ACCESS_variants.cwl workflow.',
        required=False
    )

    parser.add_argument(
        '-m',
        '--matched_mode',
        action='store_true',
        help='Create inputs from matched T/N pairs (True), or use default Normal (False)',
        required=False
    )

    parser.add_argument(
        '-p',
        '--pairing_file_path',
        help='tsv file with tumor sample IDs mapped to normal sample IDs',
        required=False
    )

    parser.add_argument(
        '-dn',
        '--default_normal_path',
        help='Normal used in unmatched mode, or in matched mode if no matching normal found for tumor sample',
        required=True
    )

    parser.add_argument(
        '-tb',
        '--tumor_bams_directory',
        help='Directory that contains all tumor bams to be used in variant calling',
        required=True
    )

    parser.add_argument(
        '-nb',
        '--normal_bams_directory',
        help='Directory that contains all normal bams to be used in variant calling and genotyping '
                                                               '(if using matched mode, otherwise only used for genotyping)',
        required=False
    )

    parser.add_argument(
        '-sb',
        '--simplex_bams_directory',
        help='Directory that contains additional simplex bams to be used for genotyping',
        required=True
    )

    # Note: For ACCESS, we will often genotype from the same folders of curated bams
    parser.add_argument(
        '-cbd',
        '--curated_bams_duplex_directory',
        help='Directory that contains additional duplex curated bams to be used for genotyping',
        required=True
    )

    parser.add_argument(
        '-cbs',
        '--curated_bams_simplex_directory',
        help='Directory that contains additional simplex curated bams to be used for genotyping',
        required=True
    )

    args = parser.parse_args()

    # Pairing file is required in matched mode
    if args.matched_mode and args.pairing_file_path is None:
        parser.error('--matched_mode requires --pairing_file_path')

    # Normal bams folder is required in matched mode
    if args.matched_mode and args.normal_bams_directory is None:
        parser.error('--matched_mode requires --normal_bams_directory')

    return args


def validate_pairing_file(pairing_file, tumor_samples, normal_samples):
    """
    Validate T/N pairs

    1. We allow normal_id to be blank in pairing file
    2. If normal_id is not blank, and id is not found in `normal_samples`, raise error
    3. Tumor ID can never be blank
    4. Tumor ID must be found in tumor_samples
    5. If both are found, continue

    :param pairing_file:
    :param tumor_samples:
    :param normal_samples:
    :return:
    """
    for i, tn_pair in pairing_file.iterrows():
        tumor_id = tn_pair['tumor_id']
        normal_id = tn_pair['normal_id']
        assert tumor_id

        # Find the path to the bam that contains this tumor sample ID
        tumor_sample = filter(lambda t: tumor_id in t, tumor_samples)
        assert len(tumor_sample) == 1

        if normal_id and normal_id != '':
            normal_sample = filter(lambda n: normal_id in n, normal_samples)
            assert len(normal_sample) == 1


def parse_tumor_normal_pairing(pairing_file, tumor_samples, normal_samples, default_normal_path, matched=True):
    """
    Build tumor-normal pairs from pairing file and tumor / normal bam directories.

    Default to `default_normal_path` if matched normal not found.

    :param path:
    :return:
    """
    ordered_tumor_samples = []
    ordered_normal_samples = []
    ordered_fillout_samples = []
    # This flag will prevent us from trying to genotype the default normal more than once
    default_added_for_genotyping = False

    for i, tn_pair in pairing_file.iterrows():
        tumor_id = tn_pair['tumor_id']
        normal_id = tn_pair['normal_id']

        # Find the path to the bam that contains this tumor sample ID
        # (after pairing file validation this should return exactly 1 result)
        tumor_sample = filter(lambda t: tumor_id in t, tumor_samples)[0]

        # Use default normal for all tumor samples
        # Matched normal will still be used for genotyping (if found)
        if not matched:
            ordered_tumor_samples.append(tumor_sample)
            ordered_normal_samples.append(default_normal_path)
            ordered_fillout_samples.append(tumor_sample)

            normal_sample = filter(lambda n: normal_id in n, normal_samples)
            if len(normal_sample) == 1:
                normal_sample = normal_sample[0]
                ordered_fillout_samples.append(normal_sample)

        # Leaving the normal ID blank will cause the default normal to be used
        # Only tumor is used for genotyping
        elif normal_id == '':
            ordered_tumor_samples.append(tumor_sample)
            ordered_normal_samples.append(default_normal_path)
            ordered_fillout_samples.append(tumor_sample)

            if not default_added_for_genotyping:
                ordered_fillout_samples.append(default_normal_path)
                default_added_for_genotyping = True

        # Use the matching normal bam that contains this normal sample ID
        # Both samples are added for genotyping
        elif any(normal_id in n for n in normal_samples):
            normal_sample = filter(lambda n: normal_id in n, normal_samples)[0]
            ordered_tumor_samples.append(tumor_sample)
            ordered_normal_samples.append(normal_sample)
            ordered_fillout_samples.append(tumor_sample)
            ordered_fillout_samples.append(normal_sample)

        else:
            # normal_id is in pairing file, but bam isn't found
            raise Exception('Missing paired normal for tumor sample {}'.format(tumor_sample))

    return ordered_tumor_samples, ordered_normal_samples, ordered_fillout_samples


def create_inputs_file(args):
    """
    Create the inputs.yaml file for the ACCESS Variant calling pipeline (modules 3 + 4)

    :param args: argparse.ArgumentParser object
    """
    fh = open(args.output_file_name, 'w')

    tumor_bam_paths = find_bams_in_directory(args.tumor_bams_directory)
    simplex_bam_paths = find_bams_in_directory(args.simplex_bams_directory)
    curated_bam_duplex_paths = find_bams_in_directory(args.curated_bams_duplex_directory)
    curated_bam_simplex_paths = find_bams_in_directory(args.curated_bams_simplex_directory)

    # Normal bams paths are either from the bams directory, or repeating the default normal
    if args.normal_bams_directory:
        normal_bam_paths = find_bams_in_directory(args.normal_bams_directory)
    else:
        normal_bam_paths = [args.default_normal_path] * len(tumor_bam_paths)

    write_yaml_bams(
        fh,
        args,
        tumor_bam_paths,
        normal_bam_paths,
        simplex_bam_paths,
        curated_bam_duplex_paths,
        curated_bam_simplex_paths,
    )

    include_file_resources(fh, ACCESS_VARIANTS_RUN_FILES_PATH)
    include_run_params(fh, ACCESS_VARIANTS_RUN_PARAMS_PATH)
    if args.structural_variants:
        include_run_params_delly(fh, ACCESS_VARIANTS_RUN_PARAMS_DELLY_PATH)
    fh.write(INPUTS_FILE_DELIMITER)
    fh.write('project_name: {}'.format(args.project_name))
    include_version_info(fh)
    fh.close()


def write_yaml_bams(
        fh,
        args,
        tumor_bam_paths,
        normal_bam_paths,
        simplex_bam_paths,
        curated_bam_duplex_paths,
        curated_bam_simplex_paths
    ):
    """
    Write the lists of tumor and normal bams to the inputs file

    :param fh: inputs file file handle
    :param args: argparse.ArgumentParser object with bam directory attribute
    :return:
    """

    # Use the pairing function to pair samples in matched mode
    if args.matched_mode:
        pairing_file = pd.read_csv(args.pairing_file_path, sep='\t', header='infer').fillna('')
        validate_pairing_file(pairing_file, tumor_bam_paths, normal_bam_paths)

        ordered_tumor_samples, ordered_normal_samples, ordered_tn_genotyping_samples = parse_tumor_normal_pairing(
            pairing_file,
            tumor_bam_paths,
            normal_bam_paths,
            args.default_normal_path,
            matched=args.matched_mode
        )

    # In unmatched mode, the sample pairing is much simpler (just use the supplied default normal)
    else:
        ordered_tumor_samples = tumor_bam_paths
        ordered_normal_samples = [args.default_normal_path] * len(tumor_bam_paths)
        # Only add the default normal once
        ordered_tn_genotyping_samples = ordered_tumor_samples + [ordered_normal_samples[0]]

    tumor_bams = create_yaml_file_objects(ordered_tumor_samples)
    normal_bams = create_yaml_file_objects(ordered_normal_samples)
    simplex_genotyping_bams = create_yaml_file_objects(simplex_bam_paths)
    curated_duplex_genotyping_bams = create_yaml_file_objects(curated_bam_duplex_paths)
    curated_simplex_genotyping_bams = create_yaml_file_objects(curated_bam_simplex_paths)

    if args.matched_mode:
        # Use pairing file for sample IDs
        tumor_sample_ids = [t for t in pairing_file['tumor_id']]
        # Todo: Better way of doing this
        normal_sample_ids = [n if n else extract_sample_id_from_bam_path(args.default_normal_path) for n in pairing_file['normal_id']]
    else:
        # Use default normal for normal sample IDs
        tumor_sample_ids = [extract_sample_id_from_bam_path(b) for b in tumor_bam_paths]
        # Todo: Better way of doing this
        normal_sample_ids = [extract_sample_id_from_bam_path(args.default_normal_path)] * len(tumor_sample_ids)


    # Also genotype the T/N samples that were initially used for variant calling
    tn_genotyping_bams = create_yaml_file_objects(ordered_tn_genotyping_samples)
    genotyping_bams = tn_genotyping_bams + simplex_genotyping_bams + curated_duplex_genotyping_bams + curated_simplex_genotyping_bams

    simplex_genotyping_ids = [extract_sample_id_from_bam_path(b['path']) + '-SIMPLEX' for b in simplex_genotyping_bams]
    curated_duplex_genotyping_ids = [extract_sample_id_from_bam_path(b['path']) + '-CURATED' for b in curated_duplex_genotyping_bams]
    curated_simplex_genotyping_ids = [extract_sample_id_from_bam_path(b['path']) + '-CURATED-SIMPLEX' for b in curated_simplex_genotyping_bams]

    # Note: This list must be sorted in the same order as tn_genotyping_bams
    # Todo: Better way of doing this
    merged_tn_sample_ids = [extract_sample_id_from_bam_path(b['path']) for b in tn_genotyping_bams]

    genotyping_bams_ids = {
        'genotyping_bams_ids': merged_tn_sample_ids +
                               simplex_genotyping_ids +
                               curated_duplex_genotyping_ids +
                               curated_simplex_genotyping_ids
    }

    tumor_bam_paths = {'tumor_bams': tumor_bams}
    normal_bam_paths = {'normal_bams': normal_bams}
    tumor_sample_ids = {'tumor_sample_names': tumor_sample_ids}
    normal_sample_ids = {'normal_sample_names': normal_sample_ids}
    genotyping_bams_paths = {'genotyping_bams': genotyping_bams}

    # Write them to the inputs yaml file
    fh.write(ruamel.yaml.dump(tumor_bam_paths))
    fh.write(ruamel.yaml.dump(normal_bam_paths))
    fh.write(ruamel.yaml.dump(tumor_sample_ids))
    fh.write(ruamel.yaml.dump(normal_sample_ids))
    fh.write(ruamel.yaml.dump(genotyping_bams_paths))
    fh.write(ruamel.yaml.dump(genotyping_bams_ids))


def extract_sample_id_from_bam_path(bam_path):
    """
    ACCESS-specific bams will have their sample IDs followed by _cl_aln...

    :param path:
    :return:
    """
    return bam_path.split('/')[-1].split('_cl_aln')[0]


def include_file_resources(fh, file_resources_path):
    """
    Write the paths to the resource files that the pipeline needs into the inputs yaml file.

    :param: fh File Handle to the inputs file for the pipeline
    :param: file_resources_path String representing full path to our resources file
    """
    with open(file_resources_path, 'r') as stream:
        file_resources = ruamel.yaml.round_trip_load(stream)

    fh.write(INPUTS_FILE_DELIMITER + ruamel.yaml.round_trip_dump(file_resources))


def include_run_params(fh, run_params_path):
    """
    Load and write our default run parameters to the pipeline inputs file

    :param fh: File Handle to the pipeline inputs yaml file
    :param run_params_path:  String representing full path to the file with our default tool parameters for this run
    """
    with open(run_params_path, 'r') as stream:
        other_params = ruamel.yaml.round_trip_load(stream)

    fh.write(INPUTS_FILE_DELIMITER + ruamel.yaml.round_trip_dump(other_params))


def include_run_params_delly(fh, run_params_delly_path):
    """
    Load and write our default run parameters to the pipeline inputs file

    :param fh: File Handle to the pipeline inputs yaml file
    :param run_params_path:  String representing full path to the file with our default tool parameters for this run
    """
    with open(run_params_delly_path, 'r') as stream:
        run_params_delly = ruamel.yaml.round_trip_load(stream)

    fh.write(INPUTS_FILE_DELIMITER + ruamel.yaml.round_trip_dump(run_params_delly))


def include_version_info(fh):
    """
    Todo: Include indentifier to indicate if commit == tag
    """
    import version
    fh.write(INPUTS_FILE_DELIMITER)
    fh.write('version: {} \n'.format(version.most_recent_tag))
    fh.write('# Pipeline Run Version Information: \n')
    fh.write('# Version: {} \n'.format(version.version))
    fh.write('# Short Version: {} \n'.format(version.short_version))
    fh.write('# Most Recent Tag: {} \n'.format(version.most_recent_tag))
    fh.write('# Dirty? {} \n'.format(str(version.dirty)))


def find_bams_in_directory(dir):
    """
    Filter to just bam files found in `dir`

    :param dir: string - directory to be searched
    :return:
    """
    files_found = os.listdir(dir)
    bams_found = [os.path.join(dir, f) for f in files_found if BAM_REGEX.match(f)]
    return bams_found


def create_yaml_file_objects(bam_paths):
    """
    Turn a list of paths into a list of cwl-compatible and ruamel-compatible file objects.

    Additionally, sort the files in lexicographical order.

    :param bam_names: file basenames
    :param folder: file folder
    :return:
    """
    return [{'class': 'File', 'path': b} for b in bam_paths]


def main():
    args = parse_arguments()
    create_inputs_file(args)


if __name__ == '__main__':
    main()
