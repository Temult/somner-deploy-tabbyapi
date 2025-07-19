> **⚠️ WARNING: You are on the `dev/experimental-backend` development branch.**
>
> This branch contains experimental changes and may be unstable. It uses the development branch of **ExllamaV3**, which has different hardware requirements than the stable `main` branch.
>
> **CRITICAL: ExllamaV3 requires an NVIDIA GPU with Ampere architecture or newer (e.g., RTX 30xx, RTX 40xx, A4000+, A100). Pre-Ampere GPUs (e.g., Turing, Volta, Tesla T4, RTX 20xx) are NOT supported on this branch.**
>
> For stable, broader hardware support, please use the `main` branch.

===========================================

# TabbyAPI-Somner

A production-ready containerized deployment of [TabbyAPI](https://github.com/theroyallab/TabbyAPI) optimized for secure, remote local or air-gapped environments with [ExllamaV3](https://github.com/turboderp-org/exllamav3) acceleration and mesh networking capabilities.

## 🚀 Modern Technology Stack

- **[TabbyAPI](https://github.com/theroyallab/TabbyAPI)** - Enhanced with [ExllamaV3 (dev branch)](https://github.com/turboderp-org/exllamav3) inference backend for optimal throughput
- **[CUDA 12.8.0](https://developer.nvidia.com/cuda-downloads)** - Latest [NVIDIA](https://www.nvidia.com/) driver compatibility with optimized binaries
- **[PyTorch 2.7.1+cu128](https://pytorch.org/)** - Current [PyTorch](https://pytorch.org/) ecosystem with CUDA 12.8 acceleration
- **[Flash Attention](https://github.com/Dao-AILab/flash-attention)** - Memory-efficient attention mechanism (included as a dependency of ExllamaV3)
- **[Python 3.11](https://www.python.org/)** - Modern Python runtime with performance improvements
- **[Caddy 2.7.6](https://caddyserver.com/)** - Zero-config HTTPS reverse proxy with automatic reloading
- **[Tailscale](https://tailscale.com/)** - Built-in mesh networking for secure remote access

## 🔒 Privacy-First Security Design

- **No Request Logging** - Disabled prompt logging, generation params, and request history
- **No Traceback Exposure** - Server errors don't leak internal information
- **Reduced Attack Surface** - Minimal dependencies, non-root execution, capability-based security
- **Air-Gap Ready** - Pre-built dependency wheelhouse eliminates external network requirements
- **Mesh Network Security** - Encrypted [Tailscale](https://tailscale.com/) tunnels without port forwarding

## 📦 Quick Start

### Prerequisites

1.  **Install [Tailscale](https://tailscale.com/)** on your client device.
2.  **Get your Tailscale auth key** from [https://login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys).

### Deploy with Docker

```bash
# Pull the development image
# Replace 'yourusername/somner:dev1' with the correct image name if you built it yourself
docker pull yourusername/somner:dev1

# On your host machine, create a directory for your models
mkdir -p ./models

# Run the container (see First-Time Configuration below before running)
docker run -d \
  --name tabbyapi-somner-dev \
  --gpus all \
  -v ./models:/workspace/models \
  -e TAILSCALE_AUTHKEY=your-auth-key-here \
  -p 80:80 \
  yourusername/somner:dev1
```

---

## ⚙️ First-Time Configuration: Setting Your Model

When you first launch the container, it will likely fail to start with a "model not found" error in the logs. **This is expected.** The container is immutable and doesn't know which model you want to use from your persistent volume.

You must create a `config.yml` file on your persistent `/workspace` volume to tell the server which model to load.

**1. Connect to Your Volume:**
Open a terminal to your RunPod volume (or use `docker exec -it <container_name> /bin/bash` if running locally).

**2. Copy the Sample Configuration:**
The container includes a sample config. Run this command to copy it to your persistent volume where you can safely edit it:

```bash
cp /opt/tabbyapi-src/config_sample.yml /workspace/config.yml
```

**3. Edit Your New `config.yml`:**
Open the file you just created and set the `model_name` to match the directory of the model you have downloaded.

```bash
# Open the file for editing
nano /workspace/config.yml
```

**Example:**
```yaml
model:
  model_dir: /workspace/models
  # Change this to your model's folder name
  model_name: L3.3-70B-Sample-Model-Name 
```

**4. Mount Your Configuration (Important!):**
In your RunPod template (or your `docker run` command), you must map your new config file into the container. This overrides the default config.

Add this volume mount:
*   **Host Path:** `/workspace/config.yml`
*   **Container Path:** `/opt/tabbyapi-src/config.yml`

**5. Restart the Pod:**
Save your changes and restart the pod. It will now find your configuration and load the correct model.

#### Why This Approach?
This method follows the best practice of separating **configuration** (your settings) from the **container** (the application). Your `config.yml` on the persistent volume is your "single source of truth." You can now change models anytime by just editing this file and restarting the pod, without ever needing to rebuild the container image.

---

- ## 🔒 Network Configuration (Tailscale ACLs)

To allow your devices to securely connect to the container, you must configure your Tailscale network's Access Control Lists (ACLs). This project includes a recommended sample file to make this easy.

**One-Time Setup:**

1.  **Find the Sample File:** In this repository, locate the file named `tailscale-acl.json.sample`.
2.  **Edit and Apply:** Follow the instructions in the sample file to apply the ACLs to your Tailscale admin console. This only needs to be done once.

#### API Access

Once running, the container provides:
- **Local Access**: `http://localhost:80`
- **Mesh Network Access**: `http://<containers-tailscale-ip>:80/v1` (via [Tailscale](https://tailscale.com/))
- **[OpenAI-Compatible API](https://platform.openai.com/docs/api-reference)**: Drop-in replacement for [OpenAI API](https://platform.openai.com/docs/api-reference) endpoints

## 🔧 Advanced Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TAILSCALE_AUTHKEY` | [Tailscale](https://tailscale.com/) authentication key | Required |

### Custom Configuration Example

This `docker run` command shows how to mount your models, your new persistent `config.yml`, and your `api_tokens.yml`.

```bash
docker run -d \
  --name tabbyapi-somner-dev \
  --gpus all \
  -v "$(pwd)/models":/workspace/models \
  -v "$(pwd)/config.yml":/opt/tabbyapi-src/config.yml \
  -v "$(pwd)/api_tokens.yml":/opt/tabbyapi-src/api_tokens.yml \
  -e TAILSCALE_AUTHKEY=your-auth-key-here \
  yourusername/somner:dev1
```

### Model Configuration
Edit your persistent `/workspace/config.yml` file to customize:
- Maximum sequence length
- Cache settings (`cache_mode`)
- GPU memory allocation (`gpu_split_auto`)
- Sampling parameters

## 🌐 Deployment Scenarios

### Local Development
```bash
docker run --gpus all -p 80:80 -v ./models:/workspace/models -v ./config.yml:/opt/tabbyapi-src/config.yml yourusername/somner:dev1
```

### Remote/Cloud Deployment
```bash
docker run --gpus all -e TAILSCALE_AUTHKEY=your-key -v /path/to/models:/workspace/models -v /path/to/config.yml:/opt/tabbyapi-src/config.yml yourusername/somner:dev1
```

### Air-Gapped Environment
The container includes all dependencies and requires no internet access after deployment.

## 📊 Performance Features

- **[ExllamaV3](https://github.com/turboderp-org/exllamav3) Backend** - Optimized inference performance
- **[Flash Attention](https://github.com/Dao-AILab/flash-attention)** - Memory-efficient attention computation
- **Automatic GPU Splitting** - Multi-GPU support with automatic memory allocation
- **FP16 Caching** - Reduced memory footprint with maintained precision
- **Tensor Parallelism** - Distributed computation across multiple GPUs

## 🛡️ Security Features

- **Non-Root Execution** - All services run as unprivileged user
- **Capability-Based Security** - Minimal system capabilities
- **No External Dependencies** - All packages pre-built during image creation
- **Encrypted Mesh Networking** - [Tailscale](https://tailscale.com/) [WireGuard](https://www.wireguard.com/) tunnels
- **Request Isolation** - No persistent request logging or history

## 📋 System Requirements

- **GPU**: NVIDIA GPU with **Ampere architecture or newer** is required.
  - **Supported Architectures**: Ampere, Hopper (e.g., RTX 30-series, RTX 40-series, A100, H100).
  - **Unsupported Architectures**: Turing, Volta, Pascal (e.g., RTX 20-series, Titan V, Tesla T4, V100, P100).
  - **AI-NOTE**: This is a key difference from the `main` branch. The `main` branch uses ExllamaV2, which can fall back to using `xformers` for compatibility with pre-Ampere GPUs. ExllamaV3 (used in this branch) drops this backward compatibility in favor of performance on modern hardware and therefore does not support pre-Ampere GPUs.
- **Memory**: 8GB+ system RAM, 16GB+ VRAM recommended for 70B models.
- **Storage**: 10GB+ for container, plus additional space for models.
- **Network**: [Tailscale](https://tailscale.com/) account for optional mesh networking.

## 🔍 Health Monitoring

The container includes built-in health checks:
- API endpoint availability
- Service process monitoring
- GPU memory status
- Network connectivity

## 📄 License

This project builds upon [TabbyAPI](https://github.com/theroyallab/TabbyAPI) and related open-source projects. Please respect the licenses of all included components.

## 🤝 Contributing

Contributions are welcome! Please submit issues and pull requests for:
- Performance optimizations
- Security enhancements
- Documentation improvements
