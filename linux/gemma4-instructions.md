# Local Gemma 4 E4B Setup & VS Code Guide (Fedora 45 / ASUS TUF A14)

Complete reference for running **Gemma 4 E4B** safely on an **ASUS TUF A14** (AMD Ryzen 7 8845HS, NVIDIA RTX 4050 6 GB VRAM, 16 GB RAM) running **Fedora 45**, integrated with **VS Code** via **Continue**, plus safe shutdown and battery power-verification steps.

---

## 1. Hardware & Model Compatibility

### Gemma 4 VRAM Fit (6 GB RTX 4050 + 16 GB RAM)

| Model | Quantization | Weight Size | Runs On | Verdict |
| :--- | :--- | :--- | :--- | :--- |
| **Gemma 4 E2B** | `Q4_0` / `Q4_K_M` | ~2.9 GB | 100% RTX 4050 GPU | **Safest & fastest.** Leaves ~3 GB VRAM free for 32K+ context. |
| **Gemma 4 E4B** | `QAT` 4-bit (`Q4_0`) | ~4.5 – 5.1 GB | 100% RTX 4050 GPU | **Best overall choice.** Full multimodal (text, image, audio) at ~30–50 tok/s with an 8K–16K context cap. |
| **Gemma 4 12B** | `Q4_0` / `Q4_K_M` | ~6.7 GB | Hybrid (GPU + RAM) | **Slow (~5–12 tok/s).** Spills into system RAM; close browsers/IDEs first. |
| **Gemma 4 26B A4B** | `Q4_0` | ~14.4 GB | Mostly RAM | **Unsafe.** All 26B weights must reside in memory; risks Fedora OOM freeze. |
| **Gemma 4 31B** | `Q4_0` | ~17.5 GB | Exceeds RAM + VRAM | **Will not fit.** Triggers `systemd-oomd`. |

### Coding Strategy (Flutter/Dart & .NET/C#)

* **Chat, Refactoring & Code Review → `Gemma 4 E4B` (`gemma4:e4b-it-qat`):** Handles deep Flutter widget trees, Riverpod/Bloc/Dart 3 patterns, ASP.NET Core DI, complex EF Core LINQ queries, and UI screenshot-to-code.
* **Keystroke Ghost-Text Autocomplete → `Qwen 2.5 Coder 1.5B` (`qwen2.5-coder:1.5b`):** Purpose-built Fill-in-the-Middle (FIM) model (~1 GB VRAM) that delivers instant inline completions without stalling E4B.

---

## 2. Fedora 45 & NVIDIA CUDA Prerequisites

1. **Keep Hybrid GPU Mode Active:** Ensure the Ryzen 8845HS integrated Radeon 780M drives your desktop (`gnome-shell` or `kwin_wayland`) so the desktop compositor does not consume 500–800 MB of your RTX 4050's 6 GB VRAM.
2. **Verify RPM Fusion NVIDIA Drivers on Kernel 7.2:** Ensure `akmod-nvidia` and `xorg-x11-drv-nvidia-cuda` are installed and built cleanly:
   ```bash
   nvidia-smi
   ```
   * **Expected Result:** Displays `NVIDIA GeForce RTX 4050 Laptop GPU` with `5900MiB+` free VRAM and no desktop compositor processes consuming GPU memory.

---

## 3. Install Ollama & Configure Safe VRAM Defaults

By default, Ollama uses uncompressed 16-bit KV caches that can push a 5+ GB model over your 6 GB VRAM limit. Configure `systemd` environment overrides to enable Flash Attention and 8-bit quantized KV caching.

1. **Install Ollama:**
   ```bash
   curl -fsSL [https://ollama.com/install.sh](https://ollama.com/install.sh) | sh
   ```

2. **Create a systemd override for safe memory limits:**
   ```bash
   sudo systemctl edit ollama.service
   ```
   Add the following lines at the top of the editor, then save and exit:
   ```ini
   [Service]
   Environment="OLLAMA_FLASH_ATTENTION=1"
   Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
   Environment="OLLAMA_MAX_LOADED_MODELS=2"
   Environment="OLLAMA_KEEP_ALIVE=5m"
   ```
   * `OLLAMA_FLASH_ATTENTION=1` & `OLLAMA_KV_CACHE_TYPE=q8_0`: Cuts KV cache VRAM usage roughly in half so a 12K context window fits inside remaining VRAM.
   * `OLLAMA_MAX_LOADED_MODELS=2`: Allows E4B + the 1.5B autocomplete model to coexist in VRAM (change to `1` if you only use E4B).
   * `OLLAMA_KEEP_ALIVE=5m`: Unloads models from VRAM automatically after 5 minutes of inactivity.

3. **Reload and restart Ollama:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart ollama
   ```

4. **Verify installation and environment:**
   ```bash
   ollama --version
   systemctl show ollama --property=Environment
   ```

---

## 4. Download Models & Create Custom Coding Modelfile

Lock the context window to **12,288 tokens** (`num_ctx 12288`) and set a low temperature (`0.2`) so Gemma 4 E4B never overflows into system RAM while generating deterministic code.

1. **Pull Gemma 4 E4B (QAT 4-bit) and Qwen 2.5 Coder 1.5B:**
   ```bash
   ollama pull gemma4:e4b-it-qat
   ollama pull qwen2.5-coder:1.5b
   ```

2. **Create and build the custom coding Modelfile:**
   ```bash
   cat << 'EOF' > ~/Modelfile.gemma4-code
   FROM gemma4:e4b-it-qat
   PARAMETER num_ctx 12288
   PARAMETER temperature 0.2
   PARAMETER top_p 0.95
   PARAMETER top_k 64
   SYSTEM "You are an expert software engineer. Write clean, idiomatic, production-ready code with concise explanations."
   EOF

   ollama create gemma4-e4b-code -f ~/Modelfile.gemma4-code
   ```

3. **Verify 100% GPU offloading:**
   ```bash
   ollama run gemma4-e4b-code "Reply with OK"
   ollama ps
   ```
   * **Expected Result:** `ollama ps` shows `gemma4-e4b-code` at `100% GPU` (or `90%+ GPU`) using ~5.3–5.6 GB VRAM.

---

## 5. VS Code Integration with Continue

1. **Install the Extension:**
   * Open VS Code (`Ctrl+Shift+X`), search for **`Continue`** (`Continue - open-source AI code agent`), and click **Install**.
   * Skip any cloud sign-in prompt and select **Local Config**.

2. **Configure `~/.continue/config.yaml`:**
   ```bash
   mkdir -p ~/.continue
   code ~/.continue/config.yaml
   ```
   Paste the following configuration:
   ```yaml
   name: Local Gemma 4 E4B
   version: 1.0.0
   schema: v1

   models:
     - name: Gemma 4 E4B (Chat & Review)
       provider: ollama
       model: gemma4-e4b-code
       apiBase: http://localhost:11434
       roles:
         - chat
         - edit
         - apply
       capabilities:
         - image_input
       defaultCompletionOptions:
         contextLength: 12288
         temperature: 0.2
         maxTokens: 4096

     - name: Qwen 2.5 Coder 1.5B (Autocomplete)
       provider: ollama
       model: qwen2.5-coder:1.5b
       apiBase: http://localhost:11434
       roles:
         - autocomplete
       autocompleteOptions:
         debounceDelay: 300
         maxPromptTokens: 1024
         multilineCompletions: auto
         onlyMyCode: true

   context:
     - provider: code
     - provider: diff
     - provider: file
     - provider: folder
     - provider: terminal
     - provider: problems

   prompts:
     - name: review
       description: Thorough code review for bugs, edge cases, and performance
       invokable: true
       prompt: |
         Review the provided code or git diff. Focus strictly on:
         1. Logic bugs, null-safety issues, and async/concurrency hazards.
         2. Performance bottlenecks and unnecessary allocations.
         3. Security flaws or missing input validation.
         Provide concrete, copy-pasteable fixes rather than generic style advice.
   ```

3. **Reload Config in VS Code:**
   * Press `Ctrl+Shift+P` → run **`Continue: Reload Config`**.
   * Select **`Gemma 4 E4B (Chat & Review)`** in the Continue sidebar dropdown.

---

## 6. Daily Workflows & Troubleshooting

### VS Code Shortcuts

| Feature | Shortcut / Command | Usage |
| :--- | :--- | :--- |
| **Chat & Debugging** | `Ctrl+L` | Highlight code and press `Ctrl+L`, or reference context with `@File`, `@Folder`, `@Terminal`, or `@Problems`. |
| **Inline Code Edit** | `Ctrl+I` | Highlight code in the editor, press `Ctrl+I`, describe the change, and accept the inline diff. |
| **Autocomplete** | `Tab` / `Esc` | Pause typing for 300 ms for grey ghost-text suggestions; press `Tab` to accept or `Esc` to dismiss. |
| **Code Review** | `/review` in Chat | Run `/review @Git Diff` to inspect uncommitted changes across your repo, or highlight code and run `/review`. |
| **UI Screenshot-to-Code** | Drag image into `Ctrl+L` | Paste or drag a UI wireframe/screenshot into chat to generate Flutter/UI code via Gemma 4's vision encoder. |

### Fixing `"The file write operation failed"` in Continue

When Continue is set to **Agent** mode, 4B quantized models can fail structured JSON tool-calling for file writes and fall back to printing code in chat. To avoid this:

1. **Use Inline Edit (`Ctrl+I`) or Chat + Apply:** Switch Continue's bottom-left mode selector from **Agent** to **Chat**, then click the **Apply** (`Play`) icon in the top-right corner of any generated code block to merge it directly into your active file.
2. **Keep `tool_use` omitted and `maxTokens: 4096`:** The `config.yaml` in Section 5 omits `tool_use` so Continue uses its native diff/apply engine instead of agentic file writes, while `maxTokens: 4096` prevents multi-file edits from truncating.
3. **Reference exact workspace paths:** Always attach files via `@Program.cs` (rather than typing subfolder paths manually) so Continue passes the exact relative path.

---

## 7. Exiting Ollama & Returning System to Normal Idle

Closing a terminal window or typing `/bye` does **not** stop the background `ollama` service or unload models from VRAM. Follow these steps when finished coding with AI:

1. **Exit any interactive terminal chat session:**
   * Type `/bye` and press `Enter` (or press `Ctrl+D`).

2. **Unload models from RTX 4050 VRAM:**
   ```bash
   ollama ps
   ollama stop gemma4-e4b-code
   ollama stop qwen2.5-coder:1.5b
   ```
   * *Verification:* `ollama ps` returns an empty table.

3. **Pause Continue Autocomplete in VS Code (prevents background wake-ups):**
   * Click the **Continue** icon in the bottom-right VS Code status bar so it switches from a checkmark to a cancel symbol (or press `Ctrl+K` then `Ctrl+A`).
   * *(Optional permanent setting)* Open VS Code Settings (`Ctrl+,`), search `Continue: Enable Tab Autocomplete`, and uncheck it.

4. **Stop the Ollama background daemon:**
   ```bash
   sudo systemctl stop ollama
   ```
   * *Verification:* `systemctl is-active ollama` outputs `inactive`.

5. **Optional — Prevent Ollama from auto-starting on boot:**
   ```bash
   sudo systemctl disable ollama   # Keep off at boot
   sudo systemctl start ollama     # Start manually when needed
   ```

---

## 8. Verifying RTX 4050 Deep Sleep (`D3cold`) on Battery

> **Important:** Do **not** run `nvidia-smi` to verify idle battery state—querying NVML briefly wakes the RTX 4050 out of deep sleep and causes it to draw ~10W. Read the Linux kernel `sysfs` and `/proc` interfaces directly instead (wait 10–15 seconds after stopping Ollama and closing GPU apps).

*(If your GPU PCIe address differs from `0000:01:00.0`, locate it with `lspci | grep -i nvidia`.)*

1. **Check PCIe Runtime Power Status:**
   ```bash
   cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
   ```
   * **Expected Result:** `suspended` (`active` means a process is still keeping the GPU awake).

2. **Check ACPI Device Power State:**
   ```bash
   cat /sys/bus/pci/devices/0000:01:00.0/power_state
   ```
   * **Expected Result:** `D3cold` (deepest power-off state, vs. `D0` when awake).

3. **Check NVIDIA Runtime D3 (RTD3) & VRAM Power:**
   ```bash
   cat /proc/driver/nvidia/gpus/0000:01:00.0/power
   ```
   * **Expected Result:** `Runtime D3 status: Enabled (fine-grained)` and `Video Memory: Off`.