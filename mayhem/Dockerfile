# syntax=docker/dockerfile:1.7
#
# Commit image for CRoaring: builds ON the org C/C++ base (ghcr.io/savantenvs/base), full repo incl. .git in /mayhem.
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t croaring-commit:test .
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# The test suite pulls cmocka through CPM (cmake/CPM.cmake downloads CPM, CPM clones cmocka). Pre-seed both
# at a fixed, $HOME-independent path so the air-gapped PATCH re-run of build.sh resolves them locally:
# CPM 0.42.0 at $CPM_SOURCE_CACHE/cpm/ (CMake skips the download when the SHA256 already matches) and
# cmocka pinned by commit (tag cmocka-2.0.0).
USER root
RUN mkdir -p /opt/toolchains/cpm/cpm \
 && curl -fsSL -o /opt/toolchains/cpm/cpm/CPM_0.42.0.cmake \
      https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.42.0/CPM.cmake \
 && echo "2020b4fc42dba44817983e06342e682ecfc3d2f484a581f11cc5731fbe4dce8a  /opt/toolchains/cpm/cpm/CPM_0.42.0.cmake" | sha256sum -c - \
 && git clone -q https://gitlab.com/cmocka/cmocka.git /opt/toolchains/cpm/cmocka-src \
 && git -C /opt/toolchains/cpm/cmocka-src checkout -q 1131a62907287aa9951e22ae93b2e8425fa2de19 \
 && chown -R 2000:2000 /opt/toolchains/cpm
USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.fix="d60ba3f447341a088bc8041277f6017f65787261" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
