#!/bin/bash
set -o pipefail

# Script to verify that the OIDC S3 bucket is defined and exists
# If .global.hypershift.createBucket is true, will create the bucket if it doesn't exist
# Usage: ./verify-s3-bucket.sh [values-file]
#
# Honors EXTRA_HELM_OPTS the same way pattern install does: -f/--values files are
# merged in order, then --set/--set-string overrides win. Only keys under
# global.hypershift are considered here.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${1:-values-hypershift.yaml}"

if [ ! -f "${VALUES_FILE}" ]; then
    echo "Error: Values file '${VALUES_FILE}' not found"
    exit 1
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    exit 1
fi

read_hypershift_values_from_file() {
    local file="$1"
    local bucket region create

    bucket=$(yq '.global.hypershift.oidc.bucketName' "${file}")
    region=$(yq '.global.hypershift.oidc.region' "${file}")
    create=$(yq '.global.hypershift.createBucket' "${file}")

    if [ -n "${bucket}" ] && [ "${bucket}" != "null" ]; then
        BUCKET_NAME="${bucket}"
    fi
    if [ -n "${region}" ] && [ "${region}" != "null" ]; then
        REGION="${region}"
    fi
    if [ -n "${create}" ] && [ "${create}" != "null" ]; then
        CREATE_BUCKET="${create}"
    fi
}

# Apply a single helm --set / --set-string argument (may be comma-separated pairs).
# Escaped commas (\,) are treated as literal commas in values.
apply_set_arg() {
    local setarg="$1"
    local pair key val rest

    rest="${setarg}"
    while [ -n "${rest}" ]; do
        # Split on the next unescaped comma
        if [[ "${rest}" =~ ^(([^\\,]|\\.)+)(,(.*))?$ ]]; then
            pair="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[4]}"
        else
            pair="${rest}"
            rest=""
        fi
        # Unescape \,
        pair="${pair//\\,/,}"

        key="${pair%%=*}"
        if [ "${key}" = "${pair}" ]; then
            continue
        fi
        val="${pair#*=}"

        case "${key}" in
            global.hypershift.createBucket)
                CREATE_BUCKET="${val}"
                ;;
            global.hypershift.oidc.region)
                REGION="${val}"
                ;;
            global.hypershift.oidc.bucketName)
                BUCKET_NAME="${val}"
                ;;
        esac
    done
}

# Merge EXTRA_HELM_OPTS over values already loaded from VALUES_FILE.
# Precedence matches helm: later -f/--values override earlier; --set wins over files.
apply_extra_helm_opts() {
    local opts="${EXTRA_HELM_OPTS:-}"
    [ -z "${opts}" ] && return 0

    echo "Applying EXTRA_HELM_OPTS: ${opts}"

    # Word-split like make/helm (EXTRA_HELM_OPTS is a helm argv string)
    # shellcheck disable=SC2206
    local -a args=( ${opts} )
    local i=0
    local -a set_args=()

    while [ "${i}" -lt "${#args[@]}" ]; do
        local arg="${args[$i]}"
        case "${arg}" in
            -f|--values)
                i=$((i + 1))
                if [ "${i}" -ge "${#args[@]}" ]; then
                    echo "Error: ${arg} in EXTRA_HELM_OPTS requires a file path"
                    exit 1
                fi
                if [ ! -f "${args[$i]}" ]; then
                    echo "Error: values file '${args[$i]}' from EXTRA_HELM_OPTS not found"
                    exit 1
                fi
                read_hypershift_values_from_file "${args[$i]}"
                ;;
            -f*)
                local fpath="${arg#-f}"
                if [ ! -f "${fpath}" ]; then
                    echo "Error: values file '${fpath}' from EXTRA_HELM_OPTS not found"
                    exit 1
                fi
                read_hypershift_values_from_file "${fpath}"
                ;;
            --values=*)
                local fpath="${arg#--values=}"
                if [ ! -f "${fpath}" ]; then
                    echo "Error: values file '${fpath}' from EXTRA_HELM_OPTS not found"
                    exit 1
                fi
                read_hypershift_values_from_file "${fpath}"
                ;;
            --set|--set-string)
                i=$((i + 1))
                if [ "${i}" -ge "${#args[@]}" ]; then
                    echo "Error: ${arg} in EXTRA_HELM_OPTS requires a value"
                    exit 1
                fi
                set_args+=("${args[$i]}")
                ;;
            --set=*)
                set_args+=("${arg#--set=}")
                ;;
            --set-string=*)
                set_args+=("${arg#--set-string=}")
                ;;
        esac
        i=$((i + 1))
    done

    # --set overrides apply after all values files
    local s
    for s in "${set_args[@]}"; do
        apply_set_arg "${s}"
    done
}

# Extract base values from values file, then overlay EXTRA_HELM_OPTS
BUCKET_NAME=""
REGION=""
CREATE_BUCKET=""
read_hypershift_values_from_file "${VALUES_FILE}"
apply_extra_helm_opts

# Check if bucket name is defined and not empty
if [ -z "${BUCKET_NAME}" ] || [ "${BUCKET_NAME}" == "null" ] || [ "${BUCKET_NAME}" == "''" ] || [ "${BUCKET_NAME}" == "" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is not defined in ${VALUES_FILE}"
    if [ -n "${EXTRA_HELM_OPTS:-}" ]; then
        echo "       (also not overridden via EXTRA_HELM_OPTS)"
    fi
    exit 1
fi

# Remove any quotes from the values
BUCKET_NAME=$(echo "${BUCKET_NAME}" | tr -d "'" | tr -d '"')
CREATE_BUCKET=$(echo "${CREATE_BUCKET}" | tr -d "'" | tr -d '"' | tr '[:upper:]' '[:lower:]')

if [ -z "${BUCKET_NAME}" ]; then
    echo "Error: .global.hypershift.oidc.bucketName is empty in ${VALUES_FILE}"
    exit 1
fi

# Clean up region value
if [ -n "${REGION}" ] && [ "${REGION}" != "null" ] && [ "${REGION}" != "''" ]; then
    REGION=$(echo "${REGION}" | tr -d "'" | tr -d '"')
else
    REGION=""
fi

echo "Checking S3 bucket: ${BUCKET_NAME}"

# Wire up AWS credentials without breaking local/default CLI auth.
#
# CI copies the pattern awsCreds shared-credentials file to ~/credentials
# (see values-secret path: ~/credentials). That is not on the AWS CLI default
# search path, so only in that case we set AWS_SHARED_CREDENTIALS_FILE.
#
# Otherwise leave the normal chain alone: env vars, AWS_PROFILE, ~/.aws/*,
# SSO, instance roles, etc.
setup_aws_credentials() {
    if [ -n "${AWS_SHARED_CREDENTIALS_FILE:-}" ]; then
        if [ ! -f "${AWS_SHARED_CREDENTIALS_FILE}" ]; then
            echo "Error: AWS_SHARED_CREDENTIALS_FILE=${AWS_SHARED_CREDENTIALS_FILE} does not exist"
            exit 1
        fi
        echo "Using AWS credentials file: ${AWS_SHARED_CREDENTIALS_FILE}"
    elif [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_PROFILE:-}" ] && \
         [ -n "${HOME:-}" ] && [ -f "${HOME}/credentials" ]; then
        export AWS_SHARED_CREDENTIALS_FILE="${HOME}/credentials"
        echo "Using AWS credentials file: ${AWS_SHARED_CREDENTIALS_FILE}"
    fi

    # Prefer the bucket's configured region for this check; do not override if
    # the caller already set one explicitly.
    if [ -n "${REGION}" ]; then
        export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${REGION}}"
        export AWS_REGION="${AWS_REGION:-${REGION}}"
    fi
}

setup_aws_credentials

# Function to check if bucket is public
check_bucket_public() {
    local bucket="$1"
    
    PUBLIC_ACCESS_BLOCK=$(aws s3api get-public-access-block --bucket "${bucket}" 2>&1)
    ret=$?

    # If get-public-access-block returns error "NoSuchPublicAccessBlockConfiguration", bucket is public
    if [ $ret -ne 0 ]; then
        if echo "${PUBLIC_ACCESS_BLOCK}" | grep -q "NoSuchPublicAccessBlockConfiguration"; then
            return 0  # Bucket is public
        else
            echo "Error: Failed to check public access block configuration"
            echo "${PUBLIC_ACCESS_BLOCK}"
            return 2  # Error checking
        fi
    fi

    # Check if any public access blocks are enabled
    BLOCK_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
    IGNORE_PUBLIC_ACLS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
    BLOCK_PUBLIC_POLICY=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
    RESTRICT_PUBLIC_BUCKETS=$(echo "${PUBLIC_ACCESS_BLOCK}" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')

    if [ "${BLOCK_PUBLIC_ACLS}" == "true" ] || [ "${IGNORE_PUBLIC_ACLS}" == "true" ] || \
       [ "${BLOCK_PUBLIC_POLICY}" == "true" ] || [ "${RESTRICT_PUBLIC_BUCKETS}" == "true" ]; then
        return 1  # Bucket is not public
    fi

    return 0  # Bucket is public
}

# Function to display not public error
show_not_public_error() {
    local bucket="$1"
    echo "Error: S3 bucket '${bucket}' is not public"
    echo ""
    echo "Current public access block settings:"
    echo "  BlockPublicAcls: ${BLOCK_PUBLIC_ACLS}"
    echo "  IgnorePublicAcls: ${IGNORE_PUBLIC_ACLS}"
    echo "  BlockPublicPolicy: ${BLOCK_PUBLIC_POLICY}"
    echo "  RestrictPublicBuckets: ${RESTRICT_PUBLIC_BUCKETS}"
    echo ""
    echo "To make the bucket public, run:"
    echo "  aws s3api put-public-access-block --bucket ${bucket} \\"
    echo "    --public-access-block-configuration 'BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false'"
}

# Check if bucket exists (capture stderr — "not accessible" is often missing creds/perms)
BUCKET_EXISTS=false
HEAD_BUCKET_ERR=$(mktemp)
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>"${HEAD_BUCKET_ERR}"; then
    BUCKET_EXISTS=true
fi
HEAD_BUCKET_MSG=$(tr -d '\r' < "${HEAD_BUCKET_ERR}" | sed '/^$/d' || true)
rm -f "${HEAD_BUCKET_ERR}"

# Handle createBucket=true
if [ "${CREATE_BUCKET}" == "true" ]; then
    echo "createBucket is enabled"
    
    if [ "${BUCKET_EXISTS}" == "true" ]; then
        echo "S3 bucket '${BUCKET_NAME}' already exists, checking if public..."
        
        check_bucket_public "${BUCKET_NAME}"
        public_ret=$?
        
        if [ $public_ret -eq 0 ]; then
            echo "Success: S3 bucket '${BUCKET_NAME}' exists and is public (skipping creation)"
            exit 0
        elif [ $public_ret -eq 1 ]; then
            show_not_public_error "${BUCKET_NAME}"
            exit 1
        else
            exit 1
        fi
    else
        # Bucket doesn't exist, create it
        if [ -z "${REGION}" ]; then
            echo "Error: .global.hypershift.oidc.region is required to create the bucket"
            exit 1
        fi
        
        echo "Creating S3 bucket '${BUCKET_NAME}' in region '${REGION}'..."
        "${SCRIPT_DIR}/create-public-s3-bucket.sh" "${BUCKET_NAME}" "${REGION}"
        
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create S3 bucket"
            exit 1
        fi
        
        echo "Success: S3 bucket '${BUCKET_NAME}' created with public policy"
        exit 0
    fi
fi

# createBucket is not true - just verify bucket exists and is public
if [ "${BUCKET_EXISTS}" != "true" ]; then
    echo "Error: S3 bucket '${BUCKET_NAME}' does not exist or is not accessible"
    if [ -n "${HEAD_BUCKET_MSG}" ]; then
        echo "aws s3api head-bucket error:"
        echo "${HEAD_BUCKET_MSG}"
    fi
    echo ""
    echo "To create the bucket, either:"
    echo "  1. Set .global.hypershift.createBucket to true in ${VALUES_FILE} (or via EXTRA_HELM_OPTS --set)"
    echo "  2. Or run manually:"
    if [ -n "${REGION}" ]; then
        echo "     ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=${REGION}"
    else
        echo "     ./pattern.sh make create-s3-bucket BUCKET_NAME=${BUCKET_NAME} REGION=<your-region>"
    fi
    exit 1
fi

echo "S3 bucket '${BUCKET_NAME}' exists"

# Check if bucket is public
echo "Checking if bucket is public..."

check_bucket_public "${BUCKET_NAME}"
public_ret=$?

if [ $public_ret -eq 0 ]; then
    echo "Success: S3 bucket '${BUCKET_NAME}' exists and is public"
    exit 0
elif [ $public_ret -eq 1 ]; then
    show_not_public_error "${BUCKET_NAME}"
    exit 1
else
    exit 1
fi
