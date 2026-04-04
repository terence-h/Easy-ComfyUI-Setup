Set-Location -Path $PSScriptRoot

function Refresh-PathEnvironment {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Read-NumberSelection {
    param(
        [string]$Prompt,
        [string[]]$ValidChoices
    )

    while ($true) {
        $selection = (Read-Host $Prompt).Trim()
        if ($ValidChoices -contains $selection) {
            return $selection
        }

        Write-Host "[!] Invalid choice. Enter one of: $($ValidChoices -join ', ')." -ForegroundColor Yellow
    }
}

function Read-ValidWindowsFolderName {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "ComfyUI"
    )

    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    $reservedNamePattern = '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'

    while ($true) {
        $rawInput = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($rawInput)) {
            return $DefaultValue
        }

        $folderName = $rawInput.Trim()

        if ($folderName -eq "." -or $folderName -eq "..") {
            Write-Host "[!] Invalid folder name. '.' and '..' are not allowed." -ForegroundColor Yellow
            continue
        }

        if ($folderName.EndsWith(" ") -or $folderName.EndsWith(".")) {
            Write-Host "[!] Invalid folder name. It cannot end with a space or period." -ForegroundColor Yellow
            continue
        }

        if ($folderName.Length -gt 255) {
            Write-Host "[!] Invalid folder name. Maximum length is 255 characters." -ForegroundColor Yellow
            continue
        }

        if ($folderName.IndexOfAny($invalidChars) -ge 0) {
            Write-Host "[!] Invalid folder name. It contains characters not allowed on Windows." -ForegroundColor Yellow
            continue
        }

        if ($folderName -match $reservedNamePattern) {
            Write-Host "[!] Invalid folder name. Reserved Windows names are not allowed (e.g. CON, PRN, AUX, NUL, COM1-9, LPT1-9)." -ForegroundColor Yellow
            continue
        }

        return $folderName
    }
}

function Exit-UnsupportedCuda {
    param(
        [string]$Reason
    )

    Write-Host "[X] $Reason" -ForegroundColor Red
    Read-Host "Please upgrade CUDA to 12.6, 12.8, or 13.x and press Enter to exit"
    exit 1
}

Write-Host "=== Easy ComfyUI Setup v1.0.2 ===" -ForegroundColor Cyan
Write-Host "--- Part 1: Detecting CUDA Version ---" -ForegroundColor Cyan

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    Exit-UnsupportedCuda -Reason "nvidia-smi was not found. CUDA version could not be detected."
}

$nvidiaSmiOutput = & nvidia-smi 2>$null
if ($LASTEXITCODE -ne 0 -or -not $nvidiaSmiOutput) {
    Exit-UnsupportedCuda -Reason "Failed to run nvidia-smi to detect CUDA version."
}

$cudaVersionMatch = $nvidiaSmiOutput | Select-String -Pattern "CUDA Version:\s*([0-9]+(?:\.[0-9]+)?)" | Select-Object -First 1
if (-not $cudaVersionMatch) {
    Exit-UnsupportedCuda -Reason "Could not parse CUDA version from nvidia-smi output."
}

$detectedCudaVersion = $cudaVersionMatch.Matches[0].Groups[1].Value
Write-Host "[i] Detected CUDA version: $detectedCudaVersion" -ForegroundColor Green

$torchIndexUrl = $null
$cudaInstallLabel = $null
$installSageAttention = $false
$installFlashAttention = $false
$sageAttentionWheelUrl = $null
$sageAttentionWheelUrlCu128 = "https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu128torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
$sageAttentionWheelUrlCu130 = "https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
$flashAttentionWheelUrl = "https://huggingface.co/ussoewwin/Flash-Attention-2_for_Windows/resolve/main/flash_attn-2.8.3%2Bcu130torch2.10.0cxx11abiTRUE-cp312-cp312-win_amd64.whl"

if ($detectedCudaVersion -eq "12.6") {
    $torchIndexUrl = "https://download.pytorch.org/whl/cu126"
    $cudaInstallLabel = "12.6"
    Write-Host "[!] CUDA 12.6 detected: FlashAttention 2 and SageAttention 2 will not be installed." -ForegroundColor Yellow
} elseif ($detectedCudaVersion -eq "12.8") {
    $torchIndexUrl = "https://download.pytorch.org/whl/cu128"
    $cudaInstallLabel = "12.8"
    $installSageAttention = $true
    $sageAttentionWheelUrl = $sageAttentionWheelUrlCu128
    Write-Host "[!] CUDA 12.8 detected: FlashAttention 2 will not be installed." -ForegroundColor Yellow
} elseif ($detectedCudaVersion -like "13.*" -or $detectedCudaVersion -eq "13") {
    $torchIndexUrl = "https://download.pytorch.org/whl/cu130"
    $cudaInstallLabel = "13.x"
    $installSageAttention = $true
    $installFlashAttention = $true
    $sageAttentionWheelUrl = $sageAttentionWheelUrlCu130
} else {
    Exit-UnsupportedCuda -Reason "Unsupported CUDA version '$detectedCudaVersion'."
}

Write-Host "--- Part 2: Checking/Installing Prerequisites ---" -ForegroundColor Cyan

if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host "[√] Git is already installed." -ForegroundColor Green
} else {
    Write-Host "[!] Git was not found." -ForegroundColor Yellow
    Write-Host "1. Yes - install Git via Winget"
    Write-Host "2. No - do not install (setup will exit)"
    $gitInstallChoice = Read-NumberSelection -Prompt "Install Git now? Enter 1 or 2" -ValidChoices @("1", "2")

    if ($gitInstallChoice -eq "1") {
        winget install --id Git.Git -e --source winget
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[X] Git installation failed." -ForegroundColor Red
            exit 1
        }

        Refresh-PathEnvironment
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Host "[X] Git is still not available after installation." -ForegroundColor Red
            exit 1
        }

        Write-Host "[√] Git installed successfully." -ForegroundColor Green
    } else {
        Write-Host "[X] You chose not to install Git. Setup will exit." -ForegroundColor Red
        exit 1
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-Host "[√] uv is already installed." -ForegroundColor Green
} else {
    Write-Host "[!] uv was not found." -ForegroundColor Yellow
    Write-Host "1. Yes - install uv via Winget"
    Write-Host "2. No - do not install (setup will exit)"
    $uvInstallChoice = Read-NumberSelection -Prompt "Install uv now? Enter 1 or 2" -ValidChoices @("1", "2")

    if ($uvInstallChoice -eq "1") {
        winget install --id astral-sh.uv -e --source winget
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[X] uv installation failed." -ForegroundColor Red
            exit 1
        }

        Refresh-PathEnvironment
        if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
            Write-Host "[X] uv is still not available after installation." -ForegroundColor Red
            exit 1
        }

        Write-Host "[√] uv installed successfully." -ForegroundColor Green
    } else {
        Write-Host "[X] You chose not to install uv. Setup will exit." -ForegroundColor Red
        exit 1
    }
}

Refresh-PathEnvironment

Write-Host "--- Part 3: Cloning Repository ---" -ForegroundColor Cyan
$comfyUiFolderName = Read-ValidWindowsFolderName -Prompt "Enter destination folder name for ComfyUI (leave blank for 'ComfyUI')"
$comfyUiFolderPath = Join-Path -Path "." -ChildPath $comfyUiFolderName

if (Test-Path $comfyUiFolderPath) {
    Write-Host "[X] '$comfyUiFolderPath' already exists. Remove or rename it before running this script." -ForegroundColor Red
    exit 1
}

$repoUrl = "https://github.com/Comfy-Org/ComfyUI.git"
$versionInput = Read-Host "Enter ComfyUI version tag (e.g. 0.0.2 or v0.18.3). Leave blank for latest. See https://github.com/Comfy-Org/ComfyUI/tags for versions available."
$versionInput = $versionInput.Trim()

if ([string]::IsNullOrWhiteSpace($versionInput)) {
    git clone $repoUrl $comfyUiFolderName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to clone repository." -ForegroundColor Red
        exit 1
    }
} else {
    $normalizedVersion = $versionInput
    if ($normalizedVersion.StartsWith("v", [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalizedVersion = $normalizedVersion.Substring(1)
    }

    $targetTag = "v$normalizedVersion"
    $remoteTags = git ls-remote --tags $repoUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to query remote tags from '$repoUrl'." -ForegroundColor Red
        exit 1
    }

    $escapedTargetTag = [regex]::Escape($targetTag)
    $matchingTag = $remoteTags | Where-Object { $_ -match "refs/tags/$escapedTargetTag(\^\{\})?$" }
    if (-not $matchingTag) {
        Write-Host "[X] No matching version found for '$targetTag' in the repository." -ForegroundColor Red
        exit 1
    }

    git clone --branch $targetTag --single-branch $repoUrl $comfyUiFolderName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to clone repository at tag '$targetTag'." -ForegroundColor Red
        exit 1
    }
}

Set-Location -Path $comfyUiFolderPath

Write-Host "--- Part 4: Setting Up Virtual Environment ---" -ForegroundColor Cyan
uv venv --python 3.12
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Failed to create virtual environment." -ForegroundColor Red
    exit 1
}

Write-Host "--- Part 5: Installing Heavy Dependencies (Torch/CUDA $cudaInstallLabel) ---" -ForegroundColor Cyan
uv pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 --index-url $torchIndexUrl
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Failed to install torch packages for CUDA $cudaInstallLabel." -ForegroundColor Red
    exit 1
}

Write-Host "--- Part 6: Installing Requirements ---" -ForegroundColor Cyan
uv pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Failed to install requirements.txt." -ForegroundColor Red
    exit 1
}

if (Test-Path "manager_requirements.txt") {
    uv pip install -r manager_requirements.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to install manager_requirements.txt." -ForegroundColor Red
        exit 1
    }
}

Write-Host "--- Part 7: Installing Triton and CUDA-Specific Attention Packages ---" -ForegroundColor Cyan
uv pip install -U "triton-windows<3.7"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Failed to install triton-windows." -ForegroundColor Red
    exit 1
}

$flashAttentionInstalled = $false
$sageAttentionInstalled = $false

if ($installSageAttention -and -not [string]::IsNullOrWhiteSpace($sageAttentionWheelUrl)) {
    uv pip install $sageAttentionWheelUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to install SageAttention 2." -ForegroundColor Red
        exit 1
    }
    $sageAttentionInstalled = $true
}

if ($installFlashAttention) {
    uv pip install $flashAttentionWheelUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Failed to install FlashAttention 2." -ForegroundColor Red
        exit 1
    }
    $flashAttentionInstalled = $true
}

$defaultAttentionArg = ""
if ($flashAttentionInstalled -or $sageAttentionInstalled) {
    Write-Host "--- Part 8: Selecting Default Attention Backend ---" -ForegroundColor Cyan

    $attentionChoices = @(
        [PSCustomObject]@{
            Key = "1"
            Label = "PyTorch attention (Recommended)"
            Arg = ""
        }
    )

    if ($flashAttentionInstalled) {
        $attentionChoices += [PSCustomObject]@{
            Key = ($attentionChoices.Count + 1).ToString()
            Label = "FlashAttention"
            Arg = "--use-flash-attention"
        }
    }

    if ($sageAttentionInstalled) {
		Write-Host "[i] SageAttention can be manually enabled per workflow by using ComfyUI-KJNodes's Patch Sage Attention KJ node." -ForegroundColor Yellow
		Write-Host "[i] It is recommended to use PyTorch attention by default and patch SageAttention when you need it" -ForegroundColor Yellow
		
        $attentionChoices += [PSCustomObject]@{
            Key = ($attentionChoices.Count + 1).ToString()
            Label = "SageAttention"
            Arg = "--use-sage-attention"
        }
    }

    foreach ($choice in $attentionChoices) {
        Write-Host "$($choice.Key). $($choice.Label)"
    }

    $attentionKeys = $attentionChoices | ForEach-Object { $_.Key }
    $selectedAttentionKey = Read-NumberSelection -Prompt "Select default attention backend" -ValidChoices $attentionKeys
    $selectedAttention = $attentionChoices | Where-Object { $_.Key -eq $selectedAttentionKey } | Select-Object -First 1
    $defaultAttentionArg = $selectedAttention.Arg
}

$startCommandAttentionArg = ""
if (-not [string]::IsNullOrWhiteSpace($defaultAttentionArg)) {
    $startCommandAttentionArg = " $defaultAttentionArg"
}

Write-Host "--- Part 9: Creating Launch & Update Batch Files ---" -ForegroundColor Cyan

# 1. start.bat
$startContent = @"
@echo off
setlocal
cd /d %~dp0
call .venv\Scripts\activate.bat
python main.py --enable-manager $startCommandAttentionArg
REM --output-directory "D:\ComfyUI_Output"
REM --use-sage-attention
REM --use-flash-attention
"@
$startContent | Out-File -FilePath "start.bat" -Encoding ascii

# 2. update_latest.bat
$updateLatestContent = @"
@echo off
setlocal
cd /d %~dp0
git pull origin master
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
pause
"@
$updateLatestContent | Out-File -FilePath "update_latest.bat" -Encoding ascii

# 3. update_stable.bat
$updateStableContent = @"
@echo off
setlocal
cd /d %~dp0
set "LATEST_TAG="
git fetch --tags
for /f "usebackq delims=" %%t in (``git tag --list "v*" --sort=-v:refname``) do (
    set "LATEST_TAG=%%t"
    goto :got_tag
)
:got_tag
if "%LATEST_TAG%"=="" (
    echo No v* tags found.
    goto :eof
)
echo Latest tag is: %LATEST_TAG%
git checkout "%LATEST_TAG%"
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
pause
"@
$updateStableContent | Out-File -FilePath "update_stable.bat" -Encoding ascii

# 4. switch_comfyui_version.bat
$switchComfyUiVersionContent = @"
@echo off
setlocal
cd /d %~dp0
set "VERSION_INPUT="
set /p VERSION_INPUT="Enter ComfyUI version (e.g. 0.0.1 or v0.18.3): "
if "%VERSION_INPUT%"=="" (
    echo No version entered.
    goto :eof
)
set "VERSION=%VERSION_INPUT%"
if /i "%VERSION_INPUT:~0,1%"=="v" (
    set "VERSION=%VERSION_INPUT:~1%"
)
echo Checking out version: v%VERSION%
git fetch --tags
git checkout "v%VERSION%"
if %errorlevel% neq 0 (
    echo Failed to checkout v%VERSION%. Make sure the tag exists.
    pause
    goto :eof
)
call .venv\Scripts\activate.bat
uv pip install -r requirements.txt
uv pip install -r manager_requirements.txt
echo.
echo Successfully switched to ComfyUI v%VERSION%
pause
"@
$switchComfyUiVersionContent | Out-File -FilePath "switch_comfyui_version.bat" -Encoding ascii

# 5. reinstall_torchcuda_triton_sageattn_flashattn.bat
$reinstallTorchCudaTritonSageAttnFlashAttnContent = @"
@echo off
setlocal EnableDelayedExpansion
cd /d %~dp0

where nvidia-smi >nul 2>nul
if errorlevel 1 (
    echo [X] nvidia-smi was not found. CUDA version could not be detected.
    echo Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script.
    pause
    exit /b 1
)

set "CUDA_VERSION_RAW="
for /f "tokens=3 delims=:|" %%A in ('nvidia-smi ^| findstr /C:"CUDA Version"') do (
    set "CUDA_VERSION_RAW=%%A"
    goto :cuda_detected
)

:cuda_detected
if "!CUDA_VERSION_RAW!"=="" (
    echo [X] Could not parse CUDA version from nvidia-smi output.
    echo Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script.
    pause
    exit /b 1
)

set "CUDA_VERSION=!CUDA_VERSION_RAW: =!"
echo [i] Detected CUDA version: !CUDA_VERSION!

set "TORCH_INDEX_URL="
set "INSTALL_SAGE=0"
set "INSTALL_FLASH=0"
set "SAGE_WHEEL_URL="
set "FLASH_WHEEL_URL=https://huggingface.co/ussoewwin/Flash-Attention-2_for_Windows/resolve/main/flash_attn-2.8.3%%2Bcu130torch2.10.0cxx11abiTRUE-cp312-cp312-win_amd64.whl"

if "!CUDA_VERSION!"=="12.6" (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126"
    echo [!] CUDA 12.6 detected: FlashAttention 2 and SageAttention 2 are not available and will be skipped.
    goto :install_packages
)

if "!CUDA_VERSION!"=="12.8" (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu128"
    set "INSTALL_SAGE=1"
    set "SAGE_WHEEL_URL=https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu128torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
    echo [!] CUDA 12.8 detected: FlashAttention 2 is not available and will be skipped.
    goto :install_packages
)

if "!CUDA_VERSION:~0,3!"=="13." (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130"
    set "INSTALL_SAGE=1"
    set "INSTALL_FLASH=1"
    set "SAGE_WHEEL_URL=https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
    goto :install_packages
)

if "!CUDA_VERSION:~0,2!"=="13" (
    set "TORCH_INDEX_URL=https://download.pytorch.org/whl/cu130"
    set "INSTALL_SAGE=1"
    set "INSTALL_FLASH=1"
    set "SAGE_WHEEL_URL=https://github.com/woct0rdho/SageAttention/releases/download/v2.2.0-windows.post4/sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl"
    goto :install_packages
)

echo [X] Unsupported CUDA version "!CUDA_VERSION!".
echo Please upgrade CUDA to 12.6, 12.8, or 13.x, then rerun this script.
pause
exit /b 1

:install_packages
call .venv\Scripts\activate.bat

uv pip install torch==2.10.0 torchvision==0.25.0 torchaudio==2.10.0 --index-url !TORCH_INDEX_URL! --upgrade --force-reinstall --no-deps
if errorlevel 1 goto :install_failed

uv pip install -U "triton-windows<3.7" --upgrade --force-reinstall --no-deps
if errorlevel 1 goto :install_failed

if "!INSTALL_SAGE!"=="1" (
    uv pip install "!SAGE_WHEEL_URL!" --upgrade --force-reinstall --no-deps
    if errorlevel 1 goto :install_failed
)

if "!INSTALL_FLASH!"=="1" (
    uv pip install "!FLASH_WHEEL_URL!" --upgrade --force-reinstall --no-deps
    if errorlevel 1 goto :install_failed
)

echo [√] Reinstall completed.
pause
exit /b 0

:install_failed
echo [X] Dependency installation failed.
pause
exit /b 1
"@
$reinstallTorchCudaTritonSageAttnFlashAttnContent | Out-File -FilePath "reinstall_torchcuda_triton_sageattn_flashattn.bat" -Encoding ascii

Write-Host "[√] All scripts created successfully." -ForegroundColor Green

Write-Host "--- Part 10: Optional Shared Model Search Path ---" -ForegroundColor Cyan
Write-Host "[i] Recommended for multiple ComfyUI installations: use a shared model directory so installs can reuse one model library and avoid duplicate models." -ForegroundColor Yellow

$extraModelPathsConfigured = $false
$extraModelBasePath = $null
$invalidPathChars = [System.IO.Path]::GetInvalidPathChars()

while ($true) {
    $extraModelPathInput = Read-Host "Enter extra model search path (e.g. C:\ComfyUI_Models). Leave blank to skip"
    if ([string]::IsNullOrWhiteSpace($extraModelPathInput)) {
        break
    }

    $candidatePath = $extraModelPathInput.Trim()

    if ($candidatePath.IndexOfAny($invalidPathChars) -ge 0) {
        Write-Host "[!] Invalid directory path. Enter a valid absolute Windows path or leave blank to skip." -ForegroundColor Yellow
        continue
    }

    if (-not ($candidatePath -match '^[a-zA-Z]:\\' -or $candidatePath.StartsWith("\\"))) {
        Write-Host "[!] Please enter an absolute Windows path (for example C:\ComfyUI_Models)." -ForegroundColor Yellow
        continue
    }

    if ((Test-Path -Path $candidatePath) -and -not (Test-Path -Path $candidatePath -PathType Container)) {
        Write-Host "[!] '$candidatePath' exists but is not a directory." -ForegroundColor Yellow
        continue
    }

    $extraModelBasePath = $candidatePath
    break
}

if (-not [string]::IsNullOrWhiteSpace($extraModelBasePath)) {
    $requiredExtraModelSubfolders = @(
        "checkpoints",
        "text_encoders",
        "clip",
        "clip_vision",
        "configs",
        "controlnet",
        "diffusers",
        "diffusion_models",
        "unet",
        "embeddings",
        "gligen",
        "hypernetworks",
        "ipadapter",
        "latent_upscale_models",
        "loras",
        "model_patches",
        "photomaker",
        "style_models",
        "upscale_models",
        "vae",
        "vae_approx",
        "audio_encoders",
        "LLM",
        "onnx",
        "sams",
        "ultralytics",
        "ultralytics\bbox",
        "ultralytics\segm"
    )

    New-Item -Path $extraModelBasePath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    if (-not (Test-Path -Path $extraModelBasePath -PathType Container)) {
        Write-Host "[X] Failed to create or access '$extraModelBasePath'." -ForegroundColor Red
        exit 1
    }

    foreach ($relativeSubfolder in $requiredExtraModelSubfolders) {
        $targetSubfolderPath = Join-Path -Path $extraModelBasePath -ChildPath $relativeSubfolder
        New-Item -Path $targetSubfolderPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        if (-not (Test-Path -Path $targetSubfolderPath -PathType Container)) {
            Write-Host "[X] Failed to create required model directory '$targetSubfolderPath'." -ForegroundColor Red
            exit 1
        }
    }

    $resolvedExtraModelBasePath = (Resolve-Path -Path $extraModelBasePath).Path
    $yamlBasePath = $resolvedExtraModelBasePath -replace "'", "''"
    $extraModelPathsYamlContent = @"
comfyui:
    base_path: '$yamlBasePath'
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
"@
    $extraModelPathsYamlContent | Out-File -FilePath "extra_model_paths.yaml" -Encoding ascii
    if (-not (Test-Path -Path "extra_model_paths.yaml" -PathType Leaf)) {
        Write-Host "[X] Failed to create extra_model_paths.yaml in '$comfyUiFolderName'." -ForegroundColor Red
        exit 1
    }

    $extraModelPathsConfigured = $true
    Write-Host "[√] Created extra_model_paths.yaml using shared model path '$resolvedExtraModelBasePath'." -ForegroundColor Green
} else {
    Write-Host "[i] Skipped extra model search path setup."
}

Write-Host "--- Setup Complete! ---" -ForegroundColor Green
Write-Host "All scripts (start.bat, update_latest.bat, update_stable.bat, switch_comfyui_version.bat, reinstall_torchcuda_triton_sageattn_flashattn.bat) have been created in the '$comfyUiFolderName' folder. Run start.bat to start ComfyUI."