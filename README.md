⚠️ **Project Status: Prototype/Pre-Alpha**

This is an experimental prototype in pre-alpha development. Somner-deploy-tabbyapi is a proof-of-concept implementation exploring secure, air-gapped LLM deployment patterns. While functional, it should be considered unstable and subject to significant changes. Do NOT consider it fully secure at this time.

===========================================

# TabbyAPI-Somner

A production-ready containerized deployment of [TabbyAPI](https://github.com/theroyallab/TabbyAPI) optimized for secure, remote local or air-gapped environments with [ExllamaV3](https://github.com/turboderp-org/exllamav3) acceleration and mesh networking capabilities.

## 🚀 Modern Technology Stack

- **[TabbyAPI](https://github.com/theroyallab/TabbyAPI)** - Enhanced with [ExllamaV3](https://github.com/turboderp-org/exllamav3) inference backend for optimal throughput
- **[CUDA 12.8.0](https://developer.nvidia.com/cuda-downloads)** - Latest [NVIDIA](https://www.nvidia.com/) driver compatibility with optimized binaries
- **[PyTorch 2.7.1+cu128](https://pytorch.org/)** - Current [PyTorch](https://pytorch.org/) ecosystem with CUDA 12.8 acceleration
- **[Flash Attention 2.8.0](https://github.com/Dao-AILab/flash-attention)** - Memory-efficient attention mechanism for larger context windows
- **[Python 3.11](https://www.python.org/)** - Modern Python runtime with performance improvements
- **[Caddy 2.7.6](https://caddyserver.com/)** - Zero-config HTTPS reverse proxy with automatic reloading
- **[Tailscale](https://tailscale.com/)** - Built-in mesh networking for secure remote access
- **[ExllamaV3](https://github.com/turboderp-org/exllamav3)** - Latest generation inference backend

## 🔒 Privacy-First Security Design

- **No Request Logging** - Disabled prompt logging, generation params, and request history
- **No Traceback Exposure** - Server errors don't leak internal information
- **Reduced Attack Surface** - Minimal dependencies, non-root execution, capability-based security
- **Air-Gap Ready** - Pre-built dependency wheelhouse eliminates external network requirements
- **Mesh Network Security** - Encrypted [Tailscale](https://tailscale.com/) tunnels without port forwarding

## 📦 Quick Start

### Prerequisites

1. **Install [Tailscale](https://tailscale.com/)** on your client device:
   ```bash
   # macOS
   brew install tailscale
   
   # Ubuntu/Debian
   curl -fsSL https://tailscale.com/install.sh | sh
   
   # Windows: Download from https://tailscale.com/download
   ```

2. **Get your Tailscale auth key** from [https://login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)

### Deploy with [Docker](https://www.docker.com/)

```bash
# Pull the image
docker pull yourusername/tabbyapi-Somner:latest

# Create model directory
mkdir -p ./models

# Run the container
docker run -d \
  --name tabbyapi-Somner \
  --gpus all \
  -v ./models:/workspace/model \
  -e TAILSCALE_AUTHKEY=your-auth-key-here \
  -p 80:80 \
  yourusername/tabbyapi-Somner:latest
```

### Configuration

Place your model files in the `./models` directory. The container will automatically detect and load compatible models.

#### Model Support
- **[ExllamaV3](https://github.com/turboderp-org/exllamav3)** quantized models (recommended)
- **[GGUF](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)** models
- **[Safetensors](https://github.com/huggingface/safetensors)** models

- ## 🔒 Network Configuration (Tailscale ACLs)

To allow your devices to securely connect to the container, you must configure your Tailscale network's Access Control Lists (ACLs). This project includes a recommended sample file to make this easy.

**One-Time Setup:**

1.  **Find the Sample File:** In this repository, locate the file named `tailscale-acl.json.sample`.

2.  **Edit the File:** Open the file and find the `tagOwners` section. Replace `"autogroup:admin"` with your own Tailscale login email if you prefer, for example: `["your-email@example.com"]`.

3.  **Apply the ACLs:**
    *   Navigate to your [**Tailscale ACL settings page**](https://login.tailscale.com/admin/acls).
    *   Delete the entire contents of the policy editor.
    *   Copy the entire contents of your edited `tailscale-acl.json.sample` file and paste it into the editor.
    *   Click "Save".

Your network is now configured. This only needs to be done once.

#### API Access

Once running, the container provides:
- **Local Access**: `http://localhost:80`
- **Mesh Network Access**: `http://runpod-Somner.tailnet-name.ts.net` (via [Tailscale](https://tailscale.com/))
- **[OpenAI-Compatible API](https://platform.openai.com/docs/api-reference)**: Drop-in replacement for [OpenAI API](https://platform.openai.com/docs/api-reference) endpoints

## 🔧 Advanced Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TAILSCALE_AUTHKEY` | [Tailscale](https://tailscale.com/) authentication key | Required |
| `DEBUG_KEY` | Debug mode activation key | Disabled |

### Custom Configuration

Mount your own config files:

```bash
docker run -d \
  --name tabbyapi-Somner \
  --gpus all \
  -v "$(pwd)/models":/workspace/model \
  -v ./config.yml:/opt/tabbyapi-src/config.yml \
  -v ./api_tokens.yml:/opt/tabbyapi-src/api_tokens.yml \
  -e TAILSCALE_AUTHKEY=your-auth-key-here \
  yourusername/tabbyapi-Somner:latest
```

### Model Configuration

Edit `config.yml` to customize:
- Maximum sequence length
- Cache settings
- GPU memory allocation
- Sampling parameters

## 🌐 Deployment Scenarios

### Local Development
```bash
docker run --gpus all -p 80:80 -v ./models:/workspace/model tabbyapi-Somner
```

### Remote/Cloud Deployment
```bash
docker run --gpus all -e TAILSCALE_AUTHKEY=your-key -v ./models:/workspace/model tabbyapi-Somner
```

### Air-Gapped Environment
The container includes all dependencies and requires no internet access after deployment.

## 📊 Performance Features

- **[ExllamaV3](https://github.com/turboderp-org/exllamav3) Backend** - Optimized inference performance
- **[Flash Attention 2.8](https://github.com/Dao-AILab/flash-attention)** - Memory-efficient attention computation
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

- **GPU**: [NVIDIA](https://www.nvidia.com/) GPU with [CUDA 12.8](https://developer.nvidia.com/cuda-downloads) support
- **Memory**: 8GB+ system RAM, 4GB+ VRAM (varies by model)
- **Storage**: 10GB+ for container, additional space for models
- **Network**: [Tailscale](https://tailscale.com/) account for mesh networking

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
