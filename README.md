# Easy ComfyUI Setup (Windows)

Automated Windows setup for [ComfyUI](https://github.com/Comfy-Org/ComfyUI) using `Setup_ComfyUI.ps1`.  
The script handles CUDA-aware dependency installation, environment setup, and creates helper batch files for daily use.

## Features

- Detects CUDA version from `nvidia-smi` automatically:
  - **12.6**
  - **12.8**
  - **13.x**
- Installs missing prerequisites with prompts:
  - **Git** (via `winget`)
  - **uv** (via `winget`)
- Clones ComfyUI:
  - Latest version (default)
  - Or a specific tag (for example `0.0.2` or `v0.18.3`)
- Creates a Python **3.12** virtual environment with `uv venv`.
- Installs pinned GPU packages:
  - `torch==2.10.0`
  - `torchvision==0.25.0`
  - `torchaudio==2.10.0`
- Installs `requirements.txt` and `manager_requirements.txt`.
- Installs `triton-windows<3.7`.
- Installs attention backends based on CUDA support:
  - SageAttention 2 (CUDA 12.8 / 13.x)
  - FlashAttention 2 (CUDA 13.x)
- Generates scripts inside the `ComfyUI` folder:
  - `start.bat`
  - `update_latest.bat`
  - `update_stable.bat`
  - `switch_comfyui_version.bat`
  - `reinstall_torchcuda_triton_sageattn_flashattn.bat`

## CUDA Compatibility

| CUDA version | Torch index URL | SageAttention 2 | FlashAttention 2 |
| --- | --- | --- | --- |
| 12.6 | `https://download.pytorch.org/whl/cu126` | No | No |
| 12.8 | `https://download.pytorch.org/whl/cu128` | Yes | No |
| 13.x | `https://download.pytorch.org/whl/cu130` | Yes | Yes |

If CUDA is not detected or not supported, installation will not proceed.

## Requirements

- Windows
- NVIDIA GPU with CUDA version 12.6, 12.8 or 13.x.
- `winget` available (used to install Git/uv if needed)
- Internet connection

## How to Use

1. Clone this repository (or download Setup_ComfyUI.ps1 only)
2. Open **PowerShell** in the repository folder.
3. If needed, allow script execution just for this PowerShell session:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   ```
4. Run the setup script:
   ```powershell
   .\Setup_ComfyUI.ps1
   ```
5. Follow prompts:
   - Install missing prerequisites (if needed)
   - Choose ComfyUI version tag (or leave blank for latest)
   - Select default attention backend (if available)
6. After setup completes, go to the generated `ComfyUI` folder and start:
   ```powershell
   .\start.bat
   ```

## Generated Batch Scripts

| Script | Purpose |
| --- | --- |
| `start.bat` | Activates `.venv` and launches ComfyUI with `--enable-manager` and selected attention argument. |
| `update_latest.bat` | Pulls latest from `origin master`, then reinstalls requirements. |
| `update_stable.bat` | Checks out latest `v*` tag, then reinstalls requirements. |
| `switch_comfyui_version.bat` | Prompts for a version tag and switches ComfyUI to that tag, then reinstalls requirements. |
| `reinstall_torchcuda_triton_sageattn_flashattn.bat` | Re-detects CUDA and force-reinstalls Torch/Triton/attention packages. |