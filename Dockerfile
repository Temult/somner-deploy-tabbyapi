# syntax=docker/dockerfile:1
# ==============================================================================
# Dockerfile for TabbyAPI
# ==============================================================================
#
# SUMMARY:
# This is a multi-stage Dockerfile designed to create a secure, minimal, and
# reproducible production environment for the TabbyAPI application.
#
# STAGE 0 (builder): Compiles all Python dependencies into a self-contained
# "wheelhouse". This allows the final stage to install everything without
# needing network access, which is faster and more secure.
#
# STAGE 1 (runtime): A minimal image that copies artifacts from the builder
# stage. It sets up the user, application code, and services to run.
#
# ARCHITECTURAL NOTE FOR AI:
# The key design choice here is the separation of the application code from
# persistent data. The application is installed in `/opt/tabbyapi-src`, while
# persistent data (like models) is expected to be in `/workspace`, which is
# mounted as a volume on platforms like RunPod. This avoids the "shadowed
# directory" problem where a volume mount hides the underlying application code.
#
################################################################################
# STAGE 0: The Builder
################################################################################
# AI-NOTE: The ARGs defined here control the versions of all major components.
ARG CUDA_VERSION="12.8.0"
ARG PYTHON_VERSION="3.11"
ARG TORCH_VERSION="2.7.1+cu128"
ARG TORCHVISION_VERSION="0.22.1+cu128"
ARG TORCHAUDIO_VERSION="2.7.1+cu128"
ARG FLASH_VERSION="2.8.0.post2"

# Start from the NVIDIA CUDA development image, which includes the full CUDA toolkit.
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu22.04 AS builder

# Redeclare ARGs to make them available in this build stage.
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION
ARG FLASH_VERSION

# Set environment variables for non-interactive setup and CUDA architecture.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC \
    TORCH_CUDA_ARCH_LIST="8.6" \
    CUDA_HOME=/usr/local/cuda \
    PATH="/usr/local/cuda/bin:${PATH}"

# Install base system dependencies and a specific Python version from the deadsnakes PPA.
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

# --- Application Source Preparation ---
# Goal: Clone the TabbyAPI repository and apply necessary patches to make it
# compatible with our specific environment (e.g., using exllamav3).
WORKDIR /workspace
RUN git clone --depth 1 --branch main https://github.com/theroyallab/TabbyAPI.git
WORKDIR /workspace/TabbyAPI
RUN set -eux; \
    # RATIONALE: Patch the source to use exllamav3 instead of the default exllamav2.
    sed -i 's/from backends.exllamav2.model import ExllamaV2Container/from backends.exllamav3.model import ExllamaV3Container/' common/model.py && \
    sed -i 's/new_container = await ExllamaV2Container.create(/new_container = await ExllamaV3Container.create(/' common/model.py && \
    if [ -f backends/exllamav2/version.py ]; then \
        sed -i 's/raise SystemExit(("Exllamav2 is not installed.\\n" + install_message))/pass/' backends/exllamav2/version.py; \
    fi && \
    # RATIONALE: The original pyproject.toml has brittle, hardcoded URLs for its optional
    # dependencies. We remove them entirely to ensure our build is stable and reproducible.
    awk ' \
      BEGIN {inblock=0} \
      /^\[project.optional-dependencies\]/ {inblock=1; next} \
      /^\[/ {if(inblock){inblock=0} } \
      !inblock \
    ' pyproject.toml > pyproject.toml.tmp && mv pyproject.toml.tmp pyproject.toml && \
    # RATIONALE: We add back a clean, dynamically generated [cu128] extra that uses
    # the specific Torch versions defined in our ARGs.
    printf '\n[project.optional-dependencies]\ncu128 = [\n    "torch==%s",\n    "torchvision==%s",\n    "torchaudio==%s",\n]\n' \
        "${TORCH_VERSION}" "${TORCHVISION_VERSION}" "${TORCHAUDIO_VERSION}" >> pyproject.toml

# --- Wheelhouse Creation ---
# Goal: Create a complete, self-contained set of Python wheels for all dependencies.
# This allows for a fully offline installation in the final runtime stage.
RUN --mount=type=cache,target=/root/.cache/pip \
    set -eux; \
    # 1. Install pip-tools for dependency resolution.
    python3.11 -m pip install --no-cache-dir pip-tools; \
    # 2. Define the top-level requirements for the project.
    { \
        echo "torch==${TORCH_VERSION}"; \
        echo "torchvision==${TORCHVISION_VERSION}"; \
        echo "torchaudio==${TORCHAUDIO_VERSION}"; \
        echo "flash-attn==${FLASH_VERSION}"; \
        echo "exllamav3 @ git+https://github.com/turboderp-org/exllamav3.git"; \
        echo "/workspace/TabbyAPI"; \
    } > /tmp/requirements.in && \
    # 3. Pre-install torch to satisfy dependencies for other packages during resolution.
    python3.11 -m pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        "torch==${TORCH_VERSION}" && \
    # 4. Use pip-compile to generate a fully-pinned requirements.txt file.
    python3.11 -m piptools compile \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        --output-file /tmp/requirements.txt \
        /tmp/requirements.in && \
    # 5. Download and build all dependencies into wheels and store them in /wheels.
    python3.11 -m pip wheel --wheel-dir=/wheels \
         --extra-index-url https://download.pytorch.org/whl/cu128 \
         -r /tmp/requirements.txt && \
    # 6. Clean up the pre-installed packages from the builder stage.
    python3.11 -m pip uninstall -y torch torchvision torchaudio

################################################################################
# STAGE 1: The Runtime
################################################################################
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu22.04

# Redeclare ARGs needed in this stage.
ARG CADDY_VERSION="2.7.6"

# Set environment variables.
ENV DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

# Install minimal OS packages, Python, Tailscale, and create the non-root user.
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
    # Create a non-root user for security.
    groupadd --gid 1000 somneruser && \
    useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home somneruser && \
    rm -rf /var/lib/apt/lists/*

# Copy build artifacts from the builder stage.
COPY --from=builder /wheels /wheels
COPY --from=builder /workspace/TabbyAPI /workspace/TabbyAPI

# Install the application and its dependencies correctly.
RUN \
    set -eux; \
    # STEP 1: Move the application source code to a safe, non-volume location (/opt).
    # RATIONALE: This prevents the app code from being hidden by a volume mounted at /workspace on RunPod.
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
    # STEP 5: Clean up the wheelhouse to keep the final image small.
    rm -rf /wheels

# Configure the application environment by copying in config files.
# The WORKDIR is set first to ensure the files are copied to the correct location.
WORKDIR /opt/tabbyapi-src
COPY Caddyfile /etc/caddy/Caddyfile
COPY config.yml api_tokens.yml ./
COPY start_services.sh /usr/local/bin/start_services.sh
RUN dos2unix /usr/local/bin/start_services.sh && chmod +x /usr/local/bin/start_services.sh

# Install and configure Caddy webserver.
RUN curl -fsSL https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz \
        | tar -xz -C /usr/local/bin caddy && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/caddy

# --- Final Runtime Configuration ---
# Switch to the non-root user for security.
USER somneruser
# Set the final working directory for the running application.
WORKDIR /opt/tabbyapi-src
# Set standard XDG environment variables.
ENV XDG_CONFIG_HOME=/home/somneruser/.config \
    XDG_DATA_HOME=/home/somneruser/.local/share

# Define runtime behavior
HEALTHCHECK --interval=1m --timeout=15s --start-period=10m --retries=3 \
  CMD curl --fail http://127.0.0.1:5000/health || exit 1

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/start_services.sh"]