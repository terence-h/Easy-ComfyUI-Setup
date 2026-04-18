#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

cd "$(dirname "$(readlink -f "$0")")"

# ============================================================
# Helpers
# ============================================================

err()  { printf '[X] %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*"; }
info() { printf '[i] %s\n' "$*"; }
ok()   { printf '[\xe2\x9c\x93] %s\n' "$*"; }

die() { err "$*"; exit 1; }

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

exit_unsupported_cuda() {
    err "$*"
    read -r -p "Please upgrade CUDA to 12.6, 12.8, or 13.x and press Enter to exit: " _ || true
    exit 1
}

read_number_selection() {
    local prompt="$1"; shift
    local valid=("$@")
    local selection v
    while true; do
        read -r -p "$prompt: " selection || true
        selection="$(trim "$selection")"
        for v in "${valid[@]}"; do
            if [[ "$selection" == "$v" ]]; then
                printf '%s' "$selection"
                return 0
            fi
        done
        warn "Invalid choice. Enter one of: $(IFS=','; echo "${valid[*]}")."
    done
}

read_yes_no() {
    local prompt="$1"
    local default_yes="${2:-0}"
    local default_label
    if [[ "$default_yes" == "1" ]]; then default_label="Y"; else default_label="N"; fi
    local raw
    while true; do
        read -r -p "$prompt Enter Y or N (default $default_label): " raw || true
        raw="$(trim "$raw")"
        if [[ -z "$raw" ]]; then
            printf '%s' "$default_yes"
            return 0
        fi
        case "$raw" in
            [Yy]) printf '1'; return 0 ;;
            [Nn]) printf '0'; return 0 ;;
        esac
        warn "Invalid choice. Enter Y or N."
    done
}

read_valid_linux_folder_name() {
    local prompt="$1"
    local default_value="${2:-ComfyUI}"
    local raw name
    while true; do
        read -r -p "$prompt: " raw || true
        if [[ -z "$(trim "$raw")" ]]; then
            printf '%s' "$default_value"
            return 0
        fi
        name="$(trim "$raw")"
        if [[ "$name" == "." || "$name" == ".." ]]; then
            warn "Invalid folder name. '.' and '..' are not allowed."
            continue
        fi
        if [[ "$name" == */* ]]; then
            warn "Invalid folder name. '/' is not allowed."
            continue
        fi
        if [[ "$name" == -* ]]; then
            warn "Invalid folder name. It cannot start with '-'."
            continue
        fi
        if [[ ${#name} -gt 255 ]]; then
            warn "Invalid folder name. Maximum length is 255 characters."
            continue
        fi
        printf '%s' "$name"
        return 0
    done
}

read_optional_absolute_linux_path() {
    local prompt="$1"
    local raw path
    while true; do
        read -r -p "$prompt: " raw || true
        path="$(trim "$raw")"
        if [[ -z "$path" ]]; then
            printf ''
            return 0
        fi
        if [[ "${path:0:1}" != "/" ]]; then
            warn "Please enter an absolute Linux path (for example /opt/ComfyUI_Models)."
            continue
        fi
        if [[ -e "$path" && ! -d "$path" ]]; then
            warn "'$path' exists but is not a directory."
            continue
        fi
        printf '%s' "$path"
        return 0
    done
}

normalize_version_tag() {
    local v="$1"
    case "$v" in
        v*|V*) v="${v:1}" ;;
    esac
    printf 'v%s' "$v"
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
    if command -v dnf     >/dev/null 2>&1; then echo "dnf"; return; fi
    if command -v pacman  >/dev/null 2>&1; then echo "pacman"; return; fi
    if command -v zypper  >/dev/null 2>&1; then echo "zypper"; return; fi
    echo ""
}

git_install_command() {
    case "$1" in
        apt)    echo "sudo apt-get update && sudo apt-get install -y git" ;;
        dnf)    echo "sudo dnf install -y git" ;;
        pacman) echo "sudo pacman -S --noconfirm git" ;;
        zypper) echo "sudo zypper install -y git" ;;
        *)      echo "" ;;
    esac
}

# ============================================================
# Banner & CUDA detection
# ============================================================

printf '=== Easy ComfyUI Setup v1.0.4 ===\n'
printf -- '--- Part 1: Detecting CUDA Version ---\n'

if ! command -v nvidia-smi >/dev/null 2>&1; then
    exit_unsupported_cuda "nvidia-smi was not found. CUDA version could not be detected."
fi

nvidia_smi_output="$(nvidia-smi 2>/dev/null || true)"
if [[ -z "$nvidia_smi_output" ]]; then
    exit_unsupported_cuda "Failed to run nvidia-smi to detect CUDA version."
fi

if [[ ! "$nvidia_smi_output" =~ CUDA[[:space:]]+Version:[[:space:]]*([0-9]+(\.[0-9]+)?) ]]; then
    exit_unsupported_cuda "Could not parse CUDA version from nvidia-smi output."
fi
detected_cuda_version="${BASH_REMATCH[1]}"
info "Detected CUDA version: $detected_cuda_version"

torch_index_url=""
cuda_install_label=""
install_sage_attention=0
install_flash_attention=0

case "$detected_cuda_version" in
    "12.6")
        torch_index_url="https://download.pytorch.org/whl/cu126"
        cuda_install_label="12.6"
        warn "CUDA 12.6 detected: FlashAttention 2 and SageAttention 2 will not be installed."
        ;;
    "12.8")
        torch_index_url="https://download.pytorch.org/whl/cu128"
        cuda_install_label="12.8"
        install_sage_attention=1
        warn "CUDA 12.8 detected: FlashAttention 2 will not be installed."
        ;;
    13|13.*)
        torch_index_url="https://download.pytorch.org/whl/cu130"
        cuda_install_label="13.x"
        install_sage_attention=1
        install_flash_attention=1
        ;;
    *)
        exit_unsupported_cuda "Unsupported CUDA version '$detected_cuda_version'."
        ;;
esac

# ============================================================
# Prerequisites
# ============================================================

printf -- '--- Part 2: Checking/Installing Prerequisites ---\n'

if command -v git >/dev/null 2>&1; then
    ok "Git is already installed."
else
    warn "Git was not found."
    pkg_mgr="$(detect_package_manager)"
    cmd_str="$(git_install_command "$pkg_mgr")"
    if [[ -n "$cmd_str" ]]; then
        info "Detected package manager: $pkg_mgr"
        info "Run the following command to install Git, then re-run this script:"
        printf '    %s\n' "$cmd_str"
    else
        info "Could not detect a supported package manager (apt, dnf, pacman, zypper)."
        info "Install Git using your distribution's package manager, then re-run this script."
    fi
    die "Git is required. Setup will exit."
fi

if command -v uv >/dev/null 2>&1; then
    ok "uv is already installed."
else
    warn "uv was not found."
    printf '1. Yes - install uv via the official installer (curl https://astral.sh/uv/install.sh | sh)\n'
    printf '2. No - do not install (setup will exit)\n'
    uv_choice="$(read_number_selection "Install uv now? Enter 1 or 2" 1 2)"
    if [[ "$uv_choice" != "1" ]]; then
        die "You chose not to install uv. Setup will exit."
    fi
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        die "uv installation failed."
    fi
    for candidate_bin in "$HOME/.local/bin" "${XDG_BIN_HOME:-}" "${CARGO_HOME:-$HOME/.cargo}/bin"; do
        if [[ -n "$candidate_bin" && -d "$candidate_bin" && ":$PATH:" != *":$candidate_bin:"* ]]; then
            export PATH="$candidate_bin:$PATH"
        fi
    done
    if ! command -v uv >/dev/null 2>&1; then
        die "uv is still not available after installation. Open a new shell and re-run this script."
    fi
    ok "uv installed successfully."
fi

# ============================================================
# Clone repository
# ============================================================

printf -- '--- Part 3: Cloning Repository ---\n'
comfy_folder_name="$(read_valid_linux_folder_name "Enter destination folder name for ComfyUI (leave blank for 'ComfyUI')")"
comfy_folder_path="./$comfy_folder_name"

if [[ -e "$comfy_folder_path" ]]; then
    die "'$comfy_folder_path' already exists. Remove or rename it before running this script."
fi

repo_url="https://github.com/Comfy-Org/ComfyUI.git"
read -r -p "Enter ComfyUI version tag (e.g. 0.0.2 or v0.18.3). Leave blank for latest. See https://github.com/Comfy-Org/ComfyUI/tags for versions available.: " version_input || true
version_input="$(trim "$version_input")"

if [[ -z "$version_input" ]]; then
    if ! git clone "$repo_url" "$comfy_folder_name"; then
        die "Failed to clone repository."
    fi
else
    target_tag="$(normalize_version_tag "$version_input")"
    if ! remote_tags="$(git ls-remote --tags "$repo_url")"; then
        die "Failed to query remote tags from '$repo_url'."
    fi
    bs_dot='\.'
    escaped_tag="${target_tag//./$bs_dot}"
    if ! grep -E "refs/tags/${escaped_tag}(\^\{\})?\$" <<<"$remote_tags" >/dev/null; then
        die "No matching version found for '$target_tag' in the repository."
    fi
    if ! git clone --branch "$target_tag" --single-branch "$repo_url" "$comfy_folder_name"; then
        die "Failed to clone repository at tag '$target_tag'."
    fi
fi

cd "$comfy_folder_path"

# ============================================================
# Virtual environment + dependencies
# ============================================================

printf -- '--- Part 4: Setting Up Virtual Environment ---\n'
uv venv --python 3.12 || die "Failed to create virtual environment."

printf -- '--- Part 5: Installing Heavy Dependencies (Torch/CUDA %s) ---\n' "$cuda_install_label"
uv pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 --index-url "$torch_index_url" \
    || die "Failed to install torch packages for CUDA $cuda_install_label."

printf -- '--- Part 6: Installing Requirements ---\n'
uv pip install -r requirements.txt || die "Failed to install requirements.txt."

if [[ -f manager_requirements.txt ]]; then
    uv pip install -r manager_requirements.txt || die "Failed to install manager_requirements.txt."
fi

printf -- '--- Part 7: Installing Triton and CUDA-Specific Attention Packages ---\n'
uv pip install -U triton || die "Failed to install triton."

flash_attention_installed=0
sage_attention_installed=0

if [[ "$install_sage_attention" == "1" ]]; then
    if uv pip install sageattention; then
        sage_attention_installed=1
    else
        die "Failed to install SageAttention 2."
    fi
fi

if [[ "$install_flash_attention" == "1" ]]; then
    info "Installing FlashAttention 2 (this may compile from source and take several minutes)..."
    if uv pip install flash-attn --no-build-isolation; then
        flash_attention_installed=1
    else
        die "Failed to install FlashAttention 2."
    fi
fi

# ============================================================
# Attention backend selection
# ============================================================

default_attention_arg=""
if [[ "$flash_attention_installed" == "1" || "$sage_attention_installed" == "1" ]]; then
    printf -- '--- Part 8: Selecting Default Attention Backend ---\n'
    keys=()
    labels=()
    args=()
    keys+=("1");   labels+=("PyTorch attention (Recommended)"); args+=("")
    if [[ "$flash_attention_installed" == "1" ]]; then
        keys+=("$((${#keys[@]} + 1))"); labels+=("FlashAttention"); args+=("--use-flash-attention")
    fi
    if [[ "$sage_attention_installed" == "1" ]]; then
        info "SageAttention can be manually enabled per workflow by using ComfyUI-KJNodes's Patch Sage Attention KJ node."
        info "It is recommended to use PyTorch attention by default and patch SageAttention when you need it"
        keys+=("$((${#keys[@]} + 1))"); labels+=("SageAttention"); args+=("--use-sage-attention")
    fi
    for i in "${!keys[@]}"; do
        printf '%s. %s\n' "${keys[$i]}" "${labels[$i]}"
    done
    selected_key="$(read_number_selection "Select default attention backend" "${keys[@]}")"
    for i in "${!keys[@]}"; do
        if [[ "${keys[$i]}" == "$selected_key" ]]; then
            default_attention_arg="${args[$i]}"
            break
        fi
    done
fi

disable_dynamic_vram="$(read_yes_no "Disable dynamic VRAM?")"

info "Recommended for multiple ComfyUI installations: use a shared output directory so installs can save generated output at a centralised location."
output_dir_arg_path="$(read_optional_absolute_linux_path "Enter output directory for generated items (e.g. /opt/ComfyUI_Output). Leave blank to keep default")"
info "Recommended for multiple ComfyUI installations: use a shared input directory so installs can access all the uploaded files."
input_dir_arg_path="$(read_optional_absolute_linux_path "Enter input directory for input items (images, videos, audio, etc.) (e.g. /opt/ComfyUI_Input). Leave blank to keep default")"

start_args_string=""
[[ -n "$default_attention_arg" ]] && start_args_string+=" $default_attention_arg"
[[ "$disable_dynamic_vram" == "1" ]] && start_args_string+=" --disable-dynamic-vram"
[[ -n "$output_dir_arg_path" ]] && start_args_string+=" --output-directory \"$output_dir_arg_path\""
[[ -n "$input_dir_arg_path" ]] && start_args_string+=" --input-directory \"$input_dir_arg_path\""

# ============================================================
# Generated scripts
# ============================================================

printf -- '--- Part 9: Creating Launch & Update Shell Scripts ---\n'

# 1. start.sh
cat > start.sh <<EOF
#!/usr/bin/env bash
set -e
cd "\$(dirname "\$(readlink -f "\$0")")"
source .venv/bin/activate
python main.py --enable-manager$start_args_string
# --output-directory "/opt/ComfyUI_Output"
# --input-directory "/opt/ComfyUI_Input"
# --use-sage-attention
# --use-flash-attention
# --disable-dynamic-vram
# --front-end-version Comfy-Org/ComfyUI_frontend@1.39.19
EOF
chmod +x start.sh

# 2. update_latest.sh
cat > update_latest.sh <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$(readlink -f "$0")")"
git pull origin master
source .venv/bin/activate
uv pip install -r requirements.txt
[ -f manager_requirements.txt ] && uv pip install -r manager_requirements.txt
read -r -p "Press Enter to close..." _
EOF
chmod +x update_latest.sh

# 3. update_stable.sh
cat > update_stable.sh <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$(readlink -f "$0")")"
git fetch --tags
LATEST_TAG="$(git tag --list 'v*' --sort=-v:refname | head -n 1)"
if [ -z "$LATEST_TAG" ]; then
    echo "No v* tags found."
    exit 0
fi
echo "Latest tag is: $LATEST_TAG"
git checkout "$LATEST_TAG"
source .venv/bin/activate
uv pip install -r requirements.txt
[ -f manager_requirements.txt ] && uv pip install -r manager_requirements.txt
read -r -p "Press Enter to close..." _
EOF
chmod +x update_stable.sh

# 4. switch_comfyui_version.sh
cat > switch_comfyui_version.sh <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$(readlink -f "$0")")"
read -r -p "Enter ComfyUI version (e.g. 0.0.1 or v0.18.3): " VERSION_INPUT
if [ -z "$VERSION_INPUT" ]; then
    echo "No version entered."
    exit 0
fi
case "$VERSION_INPUT" in
    v*|V*) VERSION="${VERSION_INPUT:1}" ;;
    *)     VERSION="$VERSION_INPUT" ;;
esac
echo "Checking out version: v$VERSION"
git fetch --tags
if ! git checkout "v$VERSION"; then
    echo "Failed to checkout v$VERSION. Make sure the tag exists."
    read -r -p "Press Enter to close..." _
    exit 1
fi
source .venv/bin/activate
uv pip install -r requirements.txt
[ -f manager_requirements.txt ] && uv pip install -r manager_requirements.txt
echo
echo "Successfully switched to ComfyUI v$VERSION"
read -r -p "Press Enter to close..." _
EOF
chmod +x switch_comfyui_version.sh

# 5. reinstall_torchcuda_triton_sageattn_flashattn.sh
cat > reinstall_torchcuda_triton_sageattn_flashattn.sh <<'EOF'
#!/usr/bin/env bash
set -e
cd "$(dirname "$(readlink -f "$0")")"

if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "[X] nvidia-smi was not found. CUDA version could not be detected."
    echo "Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script."
    read -r -p "Press Enter to close..." _
    exit 1
fi

NVIDIA_OUT="$(nvidia-smi 2>/dev/null || true)"
if [[ ! "$NVIDIA_OUT" =~ CUDA[[:space:]]+Version:[[:space:]]*([0-9]+(\.[0-9]+)?) ]]; then
    echo "[X] Could not parse CUDA version from nvidia-smi output."
    echo "Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script."
    read -r -p "Press Enter to close..." _
    exit 1
fi
CUDA_VERSION="${BASH_REMATCH[1]}"
echo "[i] Detected CUDA version: $CUDA_VERSION"

TORCH_INDEX_URL=""
INSTALL_SAGE=0
INSTALL_FLASH=0
case "$CUDA_VERSION" in
    "12.6")
        TORCH_INDEX_URL="https://download.pytorch.org/whl/cu126"
        echo "[!] CUDA 12.6 detected: FlashAttention 2 and SageAttention 2 are not available and will be skipped."
        ;;
    "12.8")
        TORCH_INDEX_URL="https://download.pytorch.org/whl/cu128"
        INSTALL_SAGE=1
        echo "[!] CUDA 12.8 detected: FlashAttention 2 is not available and will be skipped."
        ;;
    13|13.*)
        TORCH_INDEX_URL="https://download.pytorch.org/whl/cu130"
        INSTALL_SAGE=1
        INSTALL_FLASH=1
        ;;
    *)
        echo "[X] Unsupported CUDA version \"$CUDA_VERSION\"."
        echo "Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script."
        read -r -p "Press Enter to close..." _
        exit 1
        ;;
esac

source .venv/bin/activate

fail() { echo "[X] Dependency installation failed."; read -r -p "Press Enter to close..." _; exit 1; }

uv pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 \
    --index-url "$TORCH_INDEX_URL" --upgrade --force-reinstall --no-deps || fail

uv pip install -U triton --upgrade --force-reinstall --no-deps || fail

if [[ "$INSTALL_SAGE" == "1" ]]; then
    uv pip install sageattention --upgrade --force-reinstall --no-deps || fail
fi

if [[ "$INSTALL_FLASH" == "1" ]]; then
    uv pip install flash-attn --no-build-isolation --upgrade --force-reinstall --no-deps || fail
fi

printf '[\xe2\x9c\x93] Reinstall completed.\n'
read -r -p "Press Enter to close..." _
EOF
chmod +x reinstall_torchcuda_triton_sageattn_flashattn.sh

ok "All scripts created successfully."

# ============================================================
# Optional shared model search path
# ============================================================

printf -- '--- Part 10: Optional Shared Model Search Path ---\n'
info "Recommended for multiple ComfyUI installations: use a shared model directory so installs can reuse one model library and avoid duplicate models."

extra_model_base_path="$(read_optional_absolute_linux_path "Enter extra model search path (e.g. /opt/ComfyUI_Models). Leave blank to skip")"

if [[ -n "$extra_model_base_path" ]]; then
    required_subfolders=(
        checkpoints text_encoders clip clip_vision configs controlnet diffusers
        diffusion_models unet embeddings gligen hypernetworks ipadapter
        latent_upscale_models loras model_patches photomaker style_models
        upscale_models vae vae_approx audio_encoders LLM onnx sams
        ultralytics ultralytics/bbox ultralytics/segm
    )
    if ! mkdir -p "$extra_model_base_path"; then
        die "Failed to create or access '$extra_model_base_path'."
    fi
    for sub in "${required_subfolders[@]}"; do
        if ! mkdir -p "$extra_model_base_path/$sub"; then
            die "Failed to create required model directory '$extra_model_base_path/$sub'."
        fi
    done

    resolved_base="$(readlink -f "$extra_model_base_path")"
    yaml_base="${resolved_base//\'/\'\'}"
    cat > extra_model_paths.yaml <<EOF
comfyui:
    base_path: '$yaml_base'
    is_default: true
    checkpoints: checkpoints
    text_encoders: |
        text_encoders
        clip
    clip_vision: clip_vision
    configs: configs
    controlnet: controlnet
    diffusers: diffusers
    diffusion_models: |
        diffusion_models
        unet
    embeddings: embeddings
    gligen: gligen
    hypernetworks: hypernetworks
    ipadapter: ipadapter
    latent_upscale_models: latent_upscale_models
    loras: loras
    model_patches: model_patches
    photomaker: photomaker
    style_models: style_models
    upscale_models: upscale_models
    vae: vae
    vae_approx: vae_approx
    audio_encoders: audio_encoders
    LLM: LLM
    onnx: onnx
    sams: sams
    ultralytics: ultralytics
    ultralytics_bbox: ultralytics/bbox
    ultralytics_segm: ultralytics/segm
EOF
    if [[ ! -f extra_model_paths.yaml ]]; then
        die "Failed to create extra_model_paths.yaml in '$comfy_folder_name'."
    fi
    ok "Created extra_model_paths.yaml using shared model path '$resolved_base'."
else
    info "Skipped extra model search path setup."
fi

printf -- '--- Setup Complete! ---\n'
printf "All scripts (start.sh, update_latest.sh, update_stable.sh, switch_comfyui_version.sh, reinstall_torchcuda_triton_sageattn_flashattn.sh) have been created in the '%s' folder. Run ./start.sh to start ComfyUI.\n" "$comfy_folder_name"
