# TabbyAPI-Somner

A production-ready containerized deployment of TabbyAPI optimized for secure, air-gapped environments with ExllamaV3 acceleration and mesh networking capabilities.

## 🚀 Modern Technology Stack

- **TabbyAPI** - Enhanced with ExllamaV3 inference backend for optimal throughput
- **CUDA 12.8.0** - Latest NVIDIA driver compatibility with optimized binaries
- **PyTorch 2.7.1+cu128** - Current PyTorch ecosystem with CUDA 12.8 acceleration
- **Flash Attention 2.8.0** - Memory-efficient attention mechanism for larger context windows
- **Python 3.11** - Modern Python runtime with performance improvements
- **Caddy 2.7.6** - Zero-config HTTPS reverse proxy with automatic reloading
- **Tailscale** - Built-in mesh networking for secure remote access
- **ExllamaV3** - Latest generation inference backend

## 🔒 Privacy-First Security Design

- **No Request Logging** - Disabled prompt logging, generation params, and request history
- **No Traceback Exposure** - Server errors don't leak internal information
- **Reduced Attack Surface** - Minimal dependencies, non-root execution, capability-based security
- **Air-Gap Ready** - Pre-built dependency wheelhouse eliminates external network requirements
- **Mesh Network Security** - Encrypted Tailscale tunnels without port forwarding

## 📦 Quick Start

### Prerequisites

1. **Install Tailscale** on your client device:
   ```bash
   # macOS
   brew install tailscale
   
   # Ubuntu/Debian
   curl -fsSL https://tailscale.com/install.sh | sh
   
   # Windows: Download from https://tailscale.com/download
   ```

2. **Get your Tailscale auth key** from [https://login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)

### Deploy with Docker

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
- **ExllamaV2/V3** quantized models (recommended)
- **GGUF** models
- **Safetensors** models

#### API Access

Once running, the container provides:
- **Local Access**: `http://localhost:80`
- **Mesh Network Access**: `http://runpod-Somner.tailnet-name.ts.net` (via Tailscale)
- **OpenAI-Compatible API**: Drop-in replacement for OpenAI API endpoints

## 🔧 Advanced Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TAILSCALE_AUTHKEY` | Tailscale authentication key | Required |
| `DEBUG_KEY` | Debug mode activation key | Disabled |

### Custom Configuration

Mount your own config files:

```bash
docker run -d \
  --name tabbyapi-Somner \
  --gpus all \
  -v ./models:/workspace/model \
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

- **ExllamaV3 Backend** - Optimized inference performance
- **Flash Attention 2.8** - Memory-efficient attention computation
- **Automatic GPU Splitting** - Multi-GPU support with automatic memory allocation
- **FP16 Caching** - Reduced memory footprint with maintained precision
- **Tensor Parallelism** - Distributed computation across multiple GPUs

## 🛡️ Security Features

- **Non-Root Execution** - All services run as unprivileged user
- **Capability-Based Security** - Minimal system capabilities
- **No External Dependencies** - All packages pre-built during image creation
- **Encrypted Mesh Networking** - Tailscale WireGuard tunnels
- **Request Isolation** - No persistent request logging or history

## 📋 System Requirements

- **GPU**: NVIDIA GPU with CUDA 12.8 support
- **Memory**: 8GB+ system RAM, 4GB+ VRAM (varies by model)
- **Storage**: 10GB+ for container, additional space for models
- **Network**: Tailscale account for mesh networking

## 🔍 Health Monitoring

The container includes built-in health checks:
- API endpoint availability
- Service process monitoring
- GPU memory status
- Network connectivity

## 📄 License

This project builds upon TabbyAPI and related open-source projects. Please respect the licenses of all included components.

## 🤝 Contributing

Contributions are welcome! Please submit issues and pull requests for:
- Performance optimizations
- Additional model format support
- Security enhancements
- Documentation improvements
