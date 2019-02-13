cwlVersion: v1.0

class: Workflow

requirements:
  MultipleInputFeatureRequirement: {}
  ScatterFeatureRequirement: {}
  SubworkflowFeatureRequirement: {}
  InlineJavascriptRequirement: {}
  StepInputExpressionRequirement: {}
  SchemaDefRequirement:
    types:
      - $import: ../resources/run_params/schemas/vcf2maf.yaml
      - $import: ../resources/run_params/schemas/gbcms_params.yaml
      - $import: ../resources/run_params/schemas/access_filters.yaml

inputs:

  tmp_dir: Directory
  vcf2maf_params: ../resources/run_params/schemas/vcf2maf.yaml#vcf2maf_params
  gbcms_params: ../resources/run_params/schemas/gbcms_params.yaml#gbcms_params
  access_filters_params: ../resources/run_params/schemas/access_filters.yaml#access_filters__params

  hotspots: File
  combine_vcf: File
  tumor_sample_name: string
  normal_sample_name: string
  matched_normal_sample_name: string

  genotyping_bams_ids: string[]
  genotyping_bams:
    type: File[]
    secondaryFiles:
      - ^.bai

  hotspot_list: File

  exac_filter:
    type: File
    secondaryFiles:
      - .tbi

  ref_fasta:
    type: File
    secondaryFiles: [.fai]

outputs:

  maf:
    type: File
    outputSource: vcf2maf/output

  hotspots_filtered_maf:
    type: File
    outputSource: tag_hotspots/hotspot_tagged_maf

  fillout_maf:
    type: File
    outputSource: fillout/fillout_out

  final_filtered_maf:
    type: File
    outputSource: access_filters/filtered_maf

steps:

  vcf2maf:
    run: ../cwl_tools/vcf2maf/vcf2maf.cwl
    in:
      vcf2maf_params: vcf2maf_params
      input_vcf: combine_vcf
      tmp_dir: tmp_dir

      # Todo: are these right?
      vcf_tumor_id: tumor_sample_name
      vcf_normal_id: normal_sample_name
      tumor_id: tumor_sample_name
      normal_id: normal_sample_name
      ref_fasta: ref_fasta
      filter_vcf: exac_filter

      species:
        valueFrom: $(inputs.vcf2maf_params.species)
      ncbi_build:
        valueFrom: $(inputs.vcf2maf_params.ncbi_build)
      maf_center:
        valueFrom: $(inputs.vcf2maf_params.maf_center)
      max_filter_ac:
        valueFrom: $(inputs.vcf2maf_params.max_filter_ac)
      min_hom_vaf:
        valueFrom: $(inputs.vcf2maf_params.min_hom_vaf)
      vep_path:
        valueFrom: $(inputs.vcf2maf_params.vep_path)
      vep_data:
        valueFrom: $(inputs.vcf2maf_params.vep_data)
      vep_forks:
        valueFrom: $(inputs.vcf2maf_params.vep_forks)
      retain_info:
        valueFrom: $(inputs.vcf2maf_params.retain_info)
      buffer_size:
        valueFrom: $(inputs.vcf2maf_params.buffer_size)
      custom_enst:
        valueFrom: $(inputs.vcf2maf_params.custom_enst)

      output_maf:
        valueFrom: $(inputs.tumor_id + '.' + inputs.normal_id + '.combined-variants.vep.maf')
    out: [output]

  tag_hotspots:
    run: ../cwl_tools/hotspots/tag_hotspots.cwl
    in:
      input_maf: vcf2maf/output
      input_hotspot: hotspots
      output_maf:
        valueFrom: $(inputs.input_maf.basename.replace('.maf', '_taggedHotspots.maf'))
    out:
      [hotspot_tagged_maf]

  fillout:
    run: ../cwl_tools/gbcms/gbcms.cwl
    in:
      gbcms_params: gbcms_params
      maf: tag_hotspots/hotspot_tagged_maf
      genotyping_bams_ids: genotyping_bams_ids
      genotyping_bams: genotyping_bams
      ref_fasta: ref_fasta
      output:
        valueFrom: $(inputs.maf.basename.replace('.maf', '_fillout.maf'))
      omaf:
        valueFrom: $(inputs.gbcms_params.omaf)
      filter_duplicate:
        valueFrom: $(inputs.gbcms_params.filter_duplicate)
      thread:
        valueFrom: $(inputs.gbcms_params.thread)
      maq:
        valueFrom: $(inputs.gbcms_params.maq)
      fragment_count:
        valueFrom: $(inputs.gbcms_params.fragment_count)
    out: [fillout_out]

  access_filters:
    run: ../cwl_tools/python/ACCESS_filters.cwl
    in:
      access_filters_params: access_filters_params
      anno_maf: tag_hotspots/hotspot_tagged_maf
      fillout_maf: fillout/fillout_out
      tumor_samplename: tumor_sample_name
      normal_samplename: matched_normal_sample_name

      tumor_detect_alt_thres:
        valueFrom: $(inputs.access_filters_params.tumor_detect_alt_thres)
      curated_detect_alt_thres:
        valueFrom: $(inputs.access_filters_params.curated_detect_alt_thres)
      DS_tumor_detect_alt_thres:
        valueFrom: $(inputs.access_filters_params.DS_tumor_detect_alt_thres)
      DS_curated_detect_alt_thres:
        valueFrom: $(inputs.access_filters_params.DS_curated_detect_alt_thres)
      normal_TD_min:
        valueFrom: $(inputs.access_filters_params.normal_TD_min)
      normal_vaf_germline_thres:
        valueFrom: $(inputs.access_filters_params.normal_vaf_germline_thres)
      tumor_TD_min:
        valueFrom: $(inputs.access_filters_params.tumor_TD_min)
      tumor_vaf_germline_thres:
        valueFrom: $(inputs.access_filters_params.tumor_vaf_germline_thres)
      tier_one_alt_min:
        valueFrom: $(inputs.access_filters_params.tier_one_alt_min)
      tier_two_alt_min:
        valueFrom: $(inputs.access_filters_params.tier_two_alt_min)
      min_n_curated_samples_alt_detected:
        valueFrom: $(inputs.access_filters_params.min_n_curated_samples_alt_detected)
      tn_ratio_thres:
        valueFrom: $(inputs.access_filters_params.tn_ratio_thres)
    out: [filtered_maf]
