#!/usr/bin/env cwl-runner

class: CommandLineTool
cwlVersion: v1.0
baseCommand: ["sh", "build_samplesheet.sh"]

requirements:
  InlineJavascriptRequirement: {}
  InitialWorkDirRequirement:
    listing:
      - entryname: build_samplesheet.sh
        entry: |-
          echo "FCID,Lane,SampleID,SampleRef,Index,Description,Control,Recipe,Operator,SampleProject,DnaInputNg,CaptureInputNg,LibraryVolume,PatientID,IgoID"
          echo "${
            return inputs.samples.map(function(x) { 
              return ["", x["Lane"], x["SampleID"], x["SampleRef"], x["Index"], x["Description"],
              x["Control"], x["Recipe"], x["Operator"], x["SampleProject"], x["DnaInputNg"] || "",
              x["CaptureInputNg"] || "", x["LibraryVolume"] || "", x["PatientID"], x["IgoID"]].join(",")
            }).join("\n");
          }"
inputs:
  samples:
    type:
      type: array
      items:
        type: record
        fields:
          Lane:
            type: int
          SampleID:
            type: string
          SampleRef:
            type: string
          Index:
            type: string
          Description:
            type: string
          Control:
            type: string
          Recipe:
            type: string
          Operator:
            type: string
          SampleProject:
            type: string
          DnaInputNg:
            type: float?
          CaptureInputNg:
            type: float?
          LibraryVolume:
            type: float?
          PatientID:
            type: string
          IgoID:
            type: string

outputs:
  out:
    type: stdout
stdout: sample_sheet.csv
