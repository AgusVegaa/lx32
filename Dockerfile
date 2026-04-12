# syntax=docker/dockerfile:1.7
# ── STAGE 1: LLVM BUILDER ──────────────────────────────────────
FROM ubuntu:24.04 AS llvm-builder
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build gcc g++ clang lld git python3 curl ca-certificates ccache \
    && rm -rf /var/lib/apt/lists/*
ARG LLVM_REPO=https://github.com/Axel84727/llvm-project-lx32.git
ARG LLVM_REF=main
ARG LLVM_JOBS=4
ARG LLVM_BUILD_TARGETS="llc llvm-mc llvm-objcopy"
ENV CCACHE_DIR=/root/.cache/ccache \
    CCACHE_BASEDIR=/llvm-src/llvm \
    CCACHE_COMPILERCHECK=content \
    CCACHE_NOHASHDIR=true
RUN set -eux; \
    for i in 1 2 3; do \
      rm -rf /llvm-src; \
      mkdir -p /llvm-src; \
      git -C /llvm-src init -q; \
      git -C /llvm-src remote add origin "${LLVM_REPO}"; \
      if git -C /llvm-src fetch --depth=1 origin "${LLVM_REF}"; then \
        git -C /llvm-src checkout --detach -q FETCH_HEAD; \
        break; \
      fi; \
      if [ "$i" -eq 3 ]; then exit 1; fi; \
      sleep 2; \
    done
# Copy only backend sources needed for LLVM target build so test/docs changes
# do not invalidate the expensive toolchain layer.
COPY tools/lx32_backend/CMakeLists.txt /llvm-src/llvm/lib/Target/LX32/CMakeLists.txt
COPY tools/lx32_backend/TableGen /llvm-src/llvm/lib/Target/LX32/TableGen
COPY tools/lx32_backend/TargetInfo /llvm-src/llvm/lib/Target/LX32/TargetInfo
COPY tools/lx32_backend/MCTargetDesc /llvm-src/llvm/lib/Target/LX32/MCTargetDesc
COPY tools/lx32_backend/AsmParser /llvm-src/llvm/lib/Target/LX32/AsmParser
COPY tools/lx32_backend/core /llvm-src/llvm/lib/Target/LX32/core
RUN --mount=type=cache,id=lx32-ccache,target=/root/.cache/ccache,sharing=locked \
    ccache -z \
    && cmake -S /llvm-src/llvm -B /llvm-build -G Ninja \
    -DLLVM_TARGETS_TO_BUILD="LX32" \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_LINKER=lld \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    && ninja -C /llvm-build llvm-tblgen \
    && cd /llvm-src/llvm/lib/Target/LX32/TableGen \
    && LLVM_TBLGEN=/llvm-build/bin/llvm-tblgen LLVM_INCLUDE_DIR=/llvm-src/llvm/include bash ./compile_td.sh \
    && ninja -C /llvm-build -j"${LLVM_JOBS}" ${LLVM_BUILD_TARGETS} \
    && ccache -s

ARG BACKEND_COMMIT=unknown
RUN printf '%s\n' "${BACKEND_COMMIT}" > /llvm-build/LX32_BACKEND_COMMIT

# ── STAGE 2: RUNTIME ───────────────────────────────────────────
FROM ubuntu:24.04 AS runtime
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    verilator yosys coq make git curl gcc g++ python3 python3-pip \
    clang lld \
    python3-setuptools bison flex libreadline-dev gawk tcl-dev libffi-dev \
    graphviz xdot pkg-config zlib1g-dev z3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install click --break-system-packages
RUN git clone https://github.com/YosysHQ/sby.git /tmp/sby && cd /tmp/sby && make install && rm -rf /tmp/sby
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# COPIAS DESDE LA ETAPA 1 (Asegúrate de que 'llvm-builder' esté escrito igual arriba)
COPY --from=llvm-builder /llvm-build/bin/llvm-mc /usr/local/bin/
COPY --from=llvm-builder /llvm-build/bin/llvm-objcopy /usr/local/bin/
COPY --from=llvm-builder /llvm-build/lib /usr/local/lib/lx32-llvm/
COPY --from=llvm-builder /llvm-build/bin/llc /usr/local/bin/
COPY --from=llvm-builder /llvm-build/LX32_BACKEND_COMMIT /usr/local/share/LX32_BACKEND_COMMIT
RUN ln -sf /usr/bin/ld.lld /usr/local/bin/ld.lld
ENV LD_LIBRARY_PATH="/usr/local/lib/lx32-llvm:${LD_LIBRARY_PATH}"
ENV LLVM_DIR="/usr/local"
ENV LX32_LLVM_BIN="/usr/local/bin"
ENV LX32_CLANG="/usr/bin/clang"
WORKDIR /workspace
CMD ["/bin/bash"]
