########## Toolchain (Rust) image ##########
############################################
FROM ubuntu:20.04 AS toolchain

ARG DEBIAN_FRONTEND=noninteractive

# Add .cargo/bin to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Install system prerequisites
RUN apt-get update -y -q && apt-get install -y -q \
  build-essential \
  curl \
  cmake \
  clang \
  git \
  libgmp3-dev \
  libssl-dev \
  llvm \
  lld \
  pkg-config \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain stable -y

# Install cargo libraries
RUN cargo install toml-cli
RUN cargo install sccache


##########     Source image      ###########
############################################
FROM toolchain as source

# Clone given release tag or branch of this repo
ARG REPO=https://github.com/0LNetworkCommunity/libra.git
ARG BRANCH=main

# Add target binaries to PATH
ENV SOURCE_PATH="/root/libra" \
  PATH="/root/libra/target/release:${PATH}"

WORKDIR /root/libra

# Fixme(nourspace): depending where these tools are hosted, we might not need to pull
RUN echo "Checking out '${BRANCH}' from '${REPO}' ..." \
  && git clone --branch ${BRANCH} --depth 1 ${REPO} ${SOURCE_PATH} \
  && echo "Commit hash: $(git rev-parse HEAD)"


##########     Builder image      ##########
############################################
FROM source as builder

# Build 0L binaries
RUN RUSTC_WRAPPER=sccache make bins


##########   Production image     ##########
############################################
# Todo(nourspace): find a smaller base image
# build the Rust binaries using the x86_64-unknown-linux-musl target instead of the  default
# x86_64-unknown-linux-gnu target, since Alpine Linux uses musl-libc instead of glibc for its C
FROM ubuntu:20.04 AS prod

# We don't persist this env var in production image as we don't have the source files
ARG SOURCE_PATH="/root/libra"
ARG OL_BINS_PATH="/opt/0L"

# Add 0L binaries to PATH
ENV PATH="${OL_BINS_PATH}:${PATH}"

# Install system prerequisites
RUN apt-get update && apt-get install -y \
  curl \
  libssl1.1 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*
ARG USERNAME="0loperator"
# Copy binaries from builder
COPY --link --from=builder "${SOURCE_PATH}/target/release/tower" "${OL_BINS_PATH}/tower"
COPY --link --from=builder "${SOURCE_PATH}/target/release/diem-node" "${OL_BINS_PATH}/diem-node"
COPY --link --from=builder "${SOURCE_PATH}/target/release/db-restore" "${OL_BINS_PATH}/db-restore"
COPY --link --from=builder "${SOURCE_PATH}/target/release/db-backup" "${OL_BINS_PATH}/db-backup"
COPY --link --from=builder "${SOURCE_PATH}/target/release/db-backup-verify" "${OL_BINS_PATH}/db-backup-verify"
COPY --link --from=builder "${SOURCE_PATH}/target/release/ol" "${OL_BINS_PATH}/ol"
COPY --link --from=builder "${SOURCE_PATH}/target/release/txs" "${OL_BINS_PATH}/txs"
COPY --link --from=builder "${SOURCE_PATH}/target/release/onboard" "${OL_BINS_PATH}/onboard"
RUN rm -rf /root

RUN groupadd --gid 9999 "${USERNAME}" \
  && useradd --home-dir "/home/${USERNAME}" --create-home \
  --uid 9999 --gid 9999 --shell /bin/bash --skel /dev/null "${USERNAME}" \
  && chown --recursive "${USERNAME}" "${OL_BINS_PATH}"

USER "${USERNAME}"
WORKDIR "/home/${USERNAME}"
