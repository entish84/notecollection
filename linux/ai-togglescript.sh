mkdir -p ~/.local/bin

cat << 'EOF' > ~/.local/bin/ai-toggle
#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-$(basename "$0")}"
ARG="${2:-}"

# Auto-detect NVIDIA discrete GPU PCIe bus ID (e.g., 0000:01:00.0)
find_nvidia_pci() {
  for dev in /sys/bus/pci/devices/*; do
    if [[ -f "$dev/vendor" && -f "$dev/class" ]]; then
      vendor=$(<"$dev/vendor")
      class=$(<"$dev/class")
      if [[ "$vendor" == "0x10de" && "$class" == 0x03* ]]; then
        basename "$dev"
        return 0
      fi
    fi
  done
  return 1
}

GPU_PCI=$(find_nvidia_pci || true)

print_gpu_status() {
  echo "=== Ollama Service ==="
  if systemctl is-active --quiet ollama; then
    echo "Service : active"
    ollama ps || true
  else
    echo "Service : inactive"
  fi

  echo ""
  echo "=== RTX 4050 Power State (sysfs — no GPU wake) ==="
  if [[ -z "$GPU_PCI" ]]; then
    echo "NVIDIA GPU PCIe device not found."
    return
  fi

  SYS_DEV="/sys/bus/pci/devices/$GPU_PCI"
  PROC_PWR="/proc/driver/nvidia/gpus/$GPU_PCI/power"

  RUNTIME_STATUS=$(cat "$SYS_DEV/power/runtime_status" 2>/dev/null || echo "unknown")
  POWER_STATE=$(cat "$SYS_DEV/power_state" 2>/dev/null || echo "unknown")

  echo "PCI Slot       : $GPU_PCI"
  echo "Runtime Status : $RUNTIME_STATUS  (target: suspended)"
  echo "ACPI State     : $POWER_STATE  (target: D3cold)"

  if [[ -r "$PROC_PWR" ]]; then
    grep -E "Runtime D3 status|Video Memory:" "$PROC_PWR" | sed 's/^/Driver         : /'
  fi
}

case "$CMD" in
  ai-on|on)
    echo "Starting Ollama service..."
    sudo systemctl start ollama
    for _ in {1..10}; do
      if curl -sf http://localhost:11434/api/tags >/dev/null; then
        break
      fi
      sleep 0.5
    done
    echo "Ollama is active at http://localhost:11434"

    if [[ "$ARG" == "--warm" ]]; then
      echo "Preloading gemma4-e4b-code into VRAM..."
      ollama run gemma4-e4b-code "" >/dev/null
      ollama ps
    fi
    ;;

  ai-off|off)
    if systemctl is-active --quiet ollama; then
      echo "Unloading active models from VRAM..."
      mapfile -t RUNNING_MODELS < <(ollama ps 2>/dev/null | awk 'NR>1 {print $1}')
      if [[ ${#RUNNING_MODELS[@]} -gt 0 ]]; then
        for model in "${RUNNING_MODELS[@]}"; do
          echo "  Stopping $model..."
          ollama stop "$model" || true
        done
      else
        echo "  No models currently loaded."
      fi

      echo "Stopping Ollama service..."
      sudo systemctl stop ollama
    else
      echo "Ollama service is already inactive."
    fi

    if [[ -n "$GPU_PCI" ]]; then
      echo -n "Waiting for RTX 4050 to enter D3cold sleep"
      for _ in {1..20}; do
        STATE=$(cat "/sys/bus/pci/devices/$GPU_PCI/power_state" 2>/dev/null || echo "")
        if [[ "$STATE" == "D3cold" ]]; then
          echo " done."
          break
        fi
        echo -n "."
        sleep 1
      done
      echo ""
    fi

    print_gpu_status
    ;;

  gpu-status|status)
    print_gpu_status
    ;;

  *)
    echo "Usage: ai-on [--warm] | ai-off | gpu-status"
    exit 1
    ;;
esac
EOF

chmod +x ~/.local/bin/ai-toggle
ln -sf ~/.local/bin/ai-toggle ~/.local/bin/ai-on
ln -sf ~/.local/bin/ai-toggle ~/.local/bin/ai-off
ln -sf ~/.local/bin/ai-toggle ~/.local/bin/gpu-status