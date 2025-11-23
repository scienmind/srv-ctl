FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    coreutils \
    util-linux \
    cryptsetup \
    lvm2 \
    dosfstools \
    ntfs-3g \
    exfat-fuse \
    exfatprogs \
    sudo \
    curl \
    git \
    shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Install bats (Bash Automated Testing System)
RUN curl -sSL https://github.com/bats-core/bats-core/archive/v1.10.0.tar.gz | tar -xz && \
    cd bats-core-1.10.0 && \
    ./install.sh /usr/local && \
    cd .. && \
    rm -rf bats-core-1.10.0

# Create test directory
WORKDIR /srv-ctl

# Copy project files
COPY . .

# Setup test config for validation
RUN cp tests/fixtures/config.local.test config.local

# Make test scripts executable
RUN chmod +x tests/run-tests.sh \
    tests/integration/*.sh \
    tests/fixtures/*.sh \
    tests/e2e/*.sh \
    srv-ctl.sh

# Set entrypoint to run tests
ENTRYPOINT ["/srv-ctl/tests/run-tests.sh"]

# Default to running all tests (including integration)
CMD ["--all"]
