# syntax=docker/dockerfile:1
###############################################################################
# Stage 0 – builder: build every wheel we’ll ever need (no network in Stage 1)
###############################################################################
ARG CUDA_VERSION="12.8.0"
ARG PYTHON_VERSION="3.11"
ARG TORCH_VERSION="2.7.1+cu128"
ARG TORCHVISION_VERSION="0.22.1+cu128"
ARG TORCHAUDIO_VERSION="2.7.1+cu128"
ARG FLASH_VERSION="2.8.0.post2"

FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04 AS builder

# Redeclare ARGs to make them available in this stage
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION
ARG FLASH_VERSION

ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC \
    TORCH_CUDA_ARCH_LIST="8.6" \
    CUDA_HOME=/usr/local/cuda \
    PATH="/usr/local/cuda/bin:${PATH}"

# Install system dependencies and Python
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common \
                       ca-certificates git ninja-build && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3.11-dev python3.11-venv python3.11-distutils python3-pip && \
    ln -sf /usr/local/cuda-12.8 /usr/local/cuda && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    python3.11 -m pip install --no-cache-dir --upgrade pip setuptools wheel && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /wheels

# Clone and patch TabbyAPI
WORKDIR /workspace
RUN git clone --depth 1 --branch main https://github.com/theroyallab/TabbyAPI.git
WORKDIR /workspace/TabbyAPI
RUN set -eux; \
    sed -i 's/from backends.exllamav2.model import ExllamaV2Container/from backends.exllamav3.model import ExllamaV3Container/' common/model.py && \
    sed -i 's/new_container = await ExllamaV2Container.create(/new_container = await ExllamaV3Container.create(/' common/model.py && \
    if [ -f backends/exllamav2/version.py ]; then \
        sed -i 's/raise SystemExit(("Exllamav2 is not installed.\\n" + install_message))/pass/' backends/exllamav2/version.py; \
    fi && \
    awk ' \
      BEGIN {inblock=0} \
      /^\[project.optional-dependencies\]/ {inblock=1; next} \
      /^\[/ {if(inblock){inblock=0} } \
      !inblock \
    ' pyproject.toml > pyproject.toml.tmp && mv pyproject.toml.tmp pyproject.toml && \
    printf '\n[project.optional-dependencies]\ncu128 = [\n    "torch==%s",\n    "torchvision==%s",\n    "torchaudio==%s",\n]\n' \
        "${TORCH_VERSION}" "${TORCHVISION_VERSION}" "${TORCHAUDIO_VERSION}" >> pyproject.toml

# Create the complete offline wheelhouse
RUN --mount=type=cache,target=/root/.cache/pip \
    set -eux; \
    python3.11 -m pip install --no-cache-dir pip-tools; \
    { \
        echo "torch==${TORCH_VERSION}"; \
        echo "torchvision==${TORCHVISION_VERSION}"; \
        echo "torchaudio==${TORCHAUDIO_VERSION}"; \
        echo "flash-attn==${FLASH_VERSION}"; \
        echo "exllamav3 @ git+https://github.com/turboderp-org/exllamav3.git"; \
        echo "/workspace/TabbyAPI"; \
    } > /tmp/requirements.in && \
    python3.11 -m pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        "torch==${TORCH_VERSION}" && \
    python3.11 -m piptools compile \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        --output-file /tmp/requirements.txt \
        /tmp/requirements.in && \
    python3.11 -m pip wheel --wheel-dir=/wheels \
         --extra-index-url https://download.pytorch.org/whl/cu128 \
         -r /tmp/requirements.txt && \
    python3.11 -m pip uninstall -y torch torchvision torchaudio

###############################################################################
# Stage 1 – runtime: A clean, minimal production stage.
###############################################################################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

# Redeclare ARGs to make them available in this stage
ARG CADDY_VERSION="2.7.6"

ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Install minimal OS packages, Python, and create the non-root user
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        software-properties-common iproute2 curl gnupg ca-certificates \
        dos2unix gosu libcap2-bin && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3.11 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11 && \
    ln -sf /usr/bin/python3.11 /usr/bin/python3 && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg \
         | gpg --dearmor -o /usr/share/keyrings/tailscale-archive-keyring.gpg && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list \
         | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y --no-install-recommends tailscale && \
    groupadd --gid 1000 somneruser && \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home somneruser && \
    rm -rf /var/lib/apt/lists/*

# Copy artifacts from the builder stage
COPY --from=builder /wheels /wheels
COPY --from=builder /workspace/TabbyAPI /workspace/TabbyAPI

# Install the application and its dependencies correctly
RUN \
    set -eux; \
    # STEP 1: Move the application source code to a safe, non-volume location (/opt).
    mv /workspace/TabbyAPI /opt/tabbyapi-src && \
    \
    # STEP 2: Install all heavyweight dependencies from the pre-built wheels.
    python3.11 -m pip install --no-index --find-links=/wheels \
        torch torchvision torchaudio flash-attn exllamav3 && \
    \
    # STEP 3: Install TabbyAPI itself from its new source directory in /opt.
    python3.11 -m pip install --no-cache-dir /opt/tabbyapi-src[cu128] && \
    \
    # STEP 4: Grant ownership of the app directory to the runtime user for logs/etc.
    chown -R somneruser:somneruser /opt/tabbyapi-src && \
    \
    # STEP 5: Clean up the wheelhouse to keep the image small.
    rm -rf /wheels

# Configure the application environment
WORKDIR /opt/tabbyapi-src
COPY Caddyfile /etc/caddy/Caddyfile
COPY config.yml api_tokens.yml ./
COPY start_services.sh /usr/local/bin/start_services.sh
RUN dos2unix /usr/local/bin/start_services.sh && chmod +x /usr/local/bin/start_services.sh

# Install Caddy webserver
RUN curl -fsSL https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz \
        | tar -xz -C /usr/local/bin caddy && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/caddy

# Switch to the non-root user and set the final working directory
USER somneruser
WORKDIR /opt/tabbyapi-src
ENV XDG_CONFIG_HOME=/home/somneruser/.config \
    XDG_DATA_HOME=/home/somneruser/.local/share

# Define runtime behavior
HEALTHCHECK --interval=1m --timeout=15s --start-period=10m --retries=3 \
  CMD curl --fail http://127.0.0.1:5000/v1/health || exit 1

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/start_services.sh"]