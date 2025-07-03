#!/usr/bin/env bash
set -e

IMAGE_NAME="docker.io/nationwidechildrens/pgsb-cli:latest"

# ------------------------------------------------------------------------------
# usage: Displays help text
# ------------------------------------------------------------------------------
usage() {
  cat <<EOF

  This Docker wrapper runs the PGS Browser CLI by automatically:
   1) Determining a common directory for all input files 
      (VCF/PLINK + PGS model).
   2) Mounting that common directory as /app/data in the container (read-only).
   3) Mounting the output directory as /app/outputs (read-write).
   4) Rewriting your paths so the tool sees them under /app/data or /app/outputs.

  Required flags:
    --vcf <path>       or
    --bfile <prefix>   (exactly one of these two must be provided)
    --pgs_model <path>
    [--outdir <dir>]   (default: outputs)
    [--min_overlap <float>] (default: 0.7)
    [--help]

  Example:
    ./run_pgsb_docker.sh \\
      --vcf /home/myuser/somefolder/my.vcf.gz \\
      --pgs_model /home/myuser/models/model.pgsc.tsv.gz \\
      --outdir ./results

EOF
  exit 1
}

if [[ $# -eq 0 ]]; then
  echo "No arguments provided. Showing help..."
  usage
fi

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------
VCF_FILE=""
PLINK_PREFIX=""
PGS_MODEL=""
OUTDIR="outputs"
MIN_OVERLAP="0.7"
PLOT_MODE=false

# Capture leftover args
EXTRA_ARGS=()

# ------------------------------------------------------------------------------
# Parse user arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vcf)
      VCF_FILE="$2"
      shift 2
      ;;
    --bfile)
      PLINK_PREFIX="$2"
      shift 2
      ;;
    --pgs_model)
      PGS_MODEL="$2"
      shift 2
      ;;
    --outdir)
      OUTDIR="$2"
      shift 2
      ;;
    --min_overlap)
      MIN_OVERLAP="$2"
      shift 2
      ;;
    # --plot)
    #   PLOT_MODE=true
    #   shift
    #   ;;
    -h|--help)
      usage
      ;;
    *)
      EXTRA_ARGS+=( "$1" )
      shift
      ;;
  esac
done

# ------------------------------------------------------------------------------
# Validate required arguments
# ------------------------------------------------------------------------------
if [[ -z "$PGS_MODEL" ]]; then
  echo "Error: Missing required --pgs_model"
  exit 1
fi

# Exactly one of --vcf or --bfile
if [[ -n "$VCF_FILE" && -n "$PLINK_PREFIX" ]]; then
  echo "Error: Provide only ONE of --vcf or --bfile, not both."
  exit 1
elif [[ -z "$VCF_FILE" && -z "$PLINK_PREFIX" ]]; then
  echo "Error: Provide at least one of --vcf or --bfile."
  exit 1
fi

# Make sure outdir exists or create it
mkdir -p "$OUTDIR"

# ------------------------------------------------------------------------------
# abspath: Convert path to absolute
# ------------------------------------------------------------------------------
abspath() {
  local path="$1"
  if [[ -d "$path" ]]; then
    (cd "$path" && pwd)
  else
    (
      cd "$(dirname "$path")" || exit 1
      printf "%s/%s\n" "$(pwd)" "$(basename "$path")"
    )
  fi
}

# ------------------------------------------------------------------------------
# 1) Gather all input files (VCF or PLINK + PGS model) to find a common directory
# ------------------------------------------------------------------------------
INPUT_PATHS=()

if [[ -n "$VCF_FILE" ]]; then
  INPUT_PATHS+=( "$(abspath "$VCF_FILE")" )
fi

if [[ -n "$PLINK_PREFIX" ]]; then
  # For a PLINK prefix 'mydata', we might have mydata.bed, mydata.bim, mydata.fam
  # but let's just handle the prefix as is. We only need to mount the directory
  # that contains that prefix, not the .bed etc. 
  INPUT_PATHS+=( "$(abspath "$PLINK_PREFIX")" )
fi

INPUT_PATHS+=( "$(abspath "$PGS_MODEL")" )

# ------------------------------------------------------------------------------
# 2) Find the largest common directory among these input paths
#    e.g. /home/user if they're /home/user/data/file1 & /home/user/models/model2
# ------------------------------------------------------------------------------
common_dir="${INPUT_PATHS[0]}"

function common_prefix_of_two() {
  # Takes two absolute paths and returns their common directory path
  local path1="$1"
  local path2="$2"

  # Convert them to arrays, splitting on '/'
  IFS='/' read -r -a arr1 <<< "$path1"
  IFS='/' read -r -a arr2 <<< "$path2"

  # Compare element by element
  local idx=0
  local common=()
  while [[ $idx -lt ${#arr1[@]} && $idx -lt ${#arr2[@]} && "${arr1[$idx]}" == "${arr2[$idx]}" ]]; do
    common+=( "${arr1[$idx]}" )
    ((idx++))
  done

  # Reconstruct the path
  local prefix="/"
  local i=0
  for element in "${common[@]}"; do
    # Avoid double slashes
    if [[ $prefix == "/" ]]; then
      prefix="$prefix$element"
    else
      prefix="$prefix/$element"
    fi
  done

  echo "$prefix"
}

# Start with the first path as 'common_dir', then refine
for p in "${INPUT_PATHS[@]}"; do
  common_dir="$(common_prefix_of_two "$common_dir" "$p")"
done

# If the common prefix is actually the exact file path, we remove the filename portion
# so we definitely end with a directory. 
if [[ ! -d "$common_dir" ]]; then
  common_dir="$(dirname "$common_dir")"
fi

# ------------------------------------------------------------------------------
# 3) We'll mount this common_dir -> /app/data
# ------------------------------------------------------------------------------
abs_outdir="$(abspath "$OUTDIR")"

# Build Docker run arguments
DOCKER_ARGS=(
  "--rm"
  "-it" # We need to run interactively to make terminal colors work
  # Add memory limit if desired:
  # "-m" "6g"
  # The big input volume:
  "-v" "$common_dir:/app/data"
  # The output volume:
  "-v" "$abs_outdir:/app/outputs"
)

# ------------------------------------------------------------------------------
# 4) Rewrite each path to /app/data or /app/outputs inside the container
# ------------------------------------------------------------------------------
# We'll define a helper that maps a host path -> container path
function to_container_path() {
  local host_path="$1"
  # ensure absolute:
  host_path="$(abspath "$host_path")"

  # if it starts with the 'common_dir', we rewrite to /app/data/...
  # example:  common_dir=/home/user   host_path=/home/user/something/file.vcf
  # result -> /app/data/something/file.vcf
  if [[ "$host_path" == "$common_dir"* ]]; then
    # remove the prefix from host_path
    local suffix="${host_path#$common_dir}"
    # remove leading slash if any
    suffix="${suffix#/}"
    echo "/app/data/$suffix"
  else
    # This means the file isn't actually under the mounted 'common_dir'
    # We can either error or just pass the absolute path. But it won't be accessible in the container.
    echo "Warning: $host_path is outside of $common_dir! Not accessible in container."
    echo "$host_path"
  fi
}

# For outdir, we always map it to /app/outputs (plus any subpath).
# If user gave /some/absolute/path, that's fully mounted at $abs_outdir
function to_container_outdir() {
  local od="$1"
  # ensure absolute
  od="$(abspath "$od")"

  # If the user-specified OUTDIR is the same as $abs_outdir, then it's just /app/outputs
  if [[ "$od" == "$abs_outdir" ]]; then
    echo "/app/outputs"
  else
    # Possibly a subfolder or something
    local suffix="${od#$abs_outdir}"
    suffix="${suffix#/}"
    echo "/app/outputs/$suffix"
  fi
}

# ------------------------------------------------------------------------------
# Prepare the CLI arguments for inside the container
# ------------------------------------------------------------------------------
CLI_ARGS=()

if [[ -n "$VCF_FILE" ]]; then
  cpath="$(to_container_path "$VCF_FILE")"
  CLI_ARGS+=( "--vcf" "$cpath" )
fi

if [[ -n "$PLINK_PREFIX" ]]; then
  cpath="$(to_container_path "$PLINK_PREFIX")"
  CLI_ARGS+=( "--bfile" "$cpath" )
fi

pm_path="$(to_container_path "$PGS_MODEL")"
CLI_ARGS+=( "--pgs_model" "$pm_path" )

outdir_container="$(to_container_outdir "$OUTDIR")"
CLI_ARGS+=( "--outdir" "$outdir_container" )

CLI_ARGS+=( "--min_overlap" "$MIN_OVERLAP" )

# if $PLOT_MODE; then
#   CLI_ARGS+=( "--plot" )
# fi

# Append leftover user args
CLI_ARGS+=( "${EXTRA_ARGS[@]}" )

# ------------------------------------------------------------------------------
# 5) Show final command & run Docker
# ------------------------------------------------------------------------------
echo "==> Mounting input dir: $common_dir -> /app/data"
echo "==> Mounting output dir: $abs_outdir -> /app/outputs"
echo
echo "Running:"
echo "  docker run ${DOCKER_ARGS[*]} "${IMAGE_NAME}" ${CLI_ARGS[*]}"
echo

docker run "${DOCKER_ARGS[@]}" "${IMAGE_NAME}" "${CLI_ARGS[@]}"
# ------------------------------------------------------------------------------


