########## Toolchain (Rust) image ##########
############################################
FROM debian:bookworm-slim AS toolchain

ARG DEBIAN_FRONTEND=noninteractive

# Add .cargo/bin to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Install system prerequisites
RUN <<INSTALL_SYSTEM_PREREQUISITES
apt update -y -q
apt install -y -q build-essential \
  curl \
  cmake \
  clang \
  git \
  libgmp3-dev \
  libssl-dev \
  llvm \
  lld \
  pkg-config
  apt clean
  rm -rf /var/lib/apt/lists/*
INSTALL_SYSTEM_PREREQUISITES

RUN <<INSTALL_RUST_AND_CARGO_LIBRARIES
curl https://sh.rustup.rs -sSf | sh -s -- --default-toolchain stable -y
cargo install toml-cli
cargo install sccache
INSTALL_RUST_AND_CARGO_LIBRARIES


##########     Source image      ###########
############################################
FROM toolchain as source

# Clone given release tag or branch of this repo
ARG REPO=https://github.com/0LNetworkCommunity/libra-framework.git
ARG BRANCH=release-6.9.0-rc.8

# Add target binaries to PATH
ENV SOURCE_PATH="/root/libra-framework" \
  PATH="/root/libra/target/release:${PATH}"

WORKDIR /root/libra-framework

RUN <<PULL_SOURCE_CODE
echo "Checking out '${BRANCH}' from '${REPO}' ..."
git clone --branch ${BRANCH} --depth 1 ${REPO} ${SOURCE_PATH}
echo "Commit hash: $(git rev-parse HEAD)"
PULL_SOURCE_CODE

##########     Builder image      ##########
############################################
FROM source as builder

# Build 0L binaries
RUN RUSTC_WRAPPER=sccache cargo build --release \
    -p libra \
    -p libra-genesis-tools \
    -p libra-txs \
    -p diem-db-tool


##########   Production image     ##########
############################################
FROM debian:bookworm-slim AS prod
ARG UID=1000
ARG GID=1000
ARG USERNAME="ubuntu"

# We don't persist this env var in production image as we don't have the source files
ARG SOURCE_PATH="/root/libra-framework"
ARG OL_BINS_PATH="/opt/libra-framework"

# Add 0L binaries to PATH
ENV PATH="${OL_BINS_PATH}:${PATH}"

# Install system prerequisites
RUN <<INSTALL_PROD_SYSTEM_PREREQUISITES
apt update
apt install -y libssl-dev
groupadd --gid ${GID} "${USERNAME}"
useradd --home-dir "/home/${USERNAME}" --create-home \
  --uid ${UID} --gid ${GID} --shell /bin/bash --skel /dev/null "${USERNAME}"
chown --recursive "${USERNAME}" "${OL_BINS_PATH}"
apt clean
rm -rf /var/lib/apt/lists/*
INSTALL_PROD_SYSTEM_PREREQUISITES

COPY --from=builder [ \
    "${SOURCE_PATH}/target/release/libra", \
    "${SOURCE_PATH}/target/release/libra-genesis-tools", \
    "${SOURCE_PATH}/target/release/libra-txs", \
    "${SOURCE_PATH}/target/release/diem-db-tool", \
    "${OL_BINS_PATH}/" \
]
RUN rm -rf /root

USER "${USERNAME}"
WORKDIR "/home/${USERNAME}"
