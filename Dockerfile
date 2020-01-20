FROM nfcore/base:1.7
LABEL authors="Mahesh Binzer-Panchal" \
      description="Docker image containing all requirements for nf-core/genomeassembly pipeline"

COPY environment.yml /
RUN conda env create -f /environment.yml && conda clean -a
ENV PATH /opt/conda/envs/nf-core-genomeassembly-1.0dev/bin:$PATH
