#!/bin/bash -eu

usage() {
  cat <<EOUSAGE
    Usage: $0 [< Options >]

      Options:
        -r: REQUIREMENTS                : [conditional] Python requrements file contents, replaced line feed code with |. (delimiter is |).
                                          If you specify this argument, you need not prepare requirements file path.
        -p: REQUIREMENTS_FILE_PATH      : [conditional] Python requirements local file path or S3 object url (s3://bucketname/path/to/requirements.txt).
                                          If both -r REQUIREMENTS and -p REQUIREMENTS_FILE_PATH are specified, -p REQUIREMENTS_FILE_PATH has priority.
                                          see https://pip.pypa.io/en/latest/reference/requirements-file-format/#requirements-file-format
        -n: LAMBDA_LAYER_NAME           : [required] Python Lambda layer name.
        -s: LAMBDA_LAYER_S3_BUCKET_NAME : [optional] Upload Lambda layer zip file S3 bucket name.
                                          Omit this argument if you only need to create a Lambda Layer zip file.
        -k: LAMBDA_LAYER_S3_KEY_PREFIX  : [optional] Upload Lambda layer zip file S3 key prefix. (default is python)
        -l: LAMBDA_LAYER_LICENSE_INFO   : [optional] Python Lambda layer license info.

      How to use:
        (1) Prepare environment.
          [required] python, zip installed.
          If you want to upload lambda layer zip file and publish lambda layer, below environments are required.
          * aws cli installed.
          * Create the S3 bucket for store lambda layer zip file.
        (2) Grant execution rights to the shell.
          chmod +x $0
        (3) Execute the shell.
          $0 "-r requests|httpx" "-n http_request_lib" "-s LambdaLayerS3BucketName"
          $0 "-p requirements.txt" "-n http_request_lib" "-s LambdaLayerS3BucketName"
          $0 "-p s3://bucketname/path/to/requirements.txt" "-n http_request_lib" "-s LambdaLayerS3BucketName"

      IAM policy action requirements:
        If you want to upload lambda layer zip file and publish lambda layer, below actions are required.

        {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "PublishPythonLambdaLayer",
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:ListBucket",
                        "s3:PutObject",
                        "lambda:PublishLayerVersion"
                    ],
                    "Resource": "*"
                }
            ]
        }

EOUSAGE
}

readonly DATETIME_MILLISEC=`date +%Y%m%d%H%M%S%3N`

REQUIREMENTS=
REQUIREMENTS_FILE_PATH=
LAMBDA_LAYER_NAME=
LAMBDA_LAYER_S3_BUCKET_NAME=
LAMBDA_LAYER_S3_DIR_KEY=python
LAMBDA_LAYER_LICENSE_INFO=

while getopts r:p:n:s:k:l: OPT
do
  case ${OPT} in
    r) REQUIREMENTS=${OPTARG} ;;
    p) REQUIREMENTS_FILE_PATH=${OPTARG} ;;
    n) LAMBDA_LAYER_NAME=${OPTARG} ;;
    s) LAMBDA_LAYER_S3_BUCKET_NAME=${OPTARG} ;;
    k) LAMBDA_LAYER_S3_DIR_KEY=${OPTARG} ;;
    l) LAMBDA_LAYER_LICENSE_INFO=${OPTARG} ;;
    *) usage
       exit 1 ;;
  esac
done;

REQUIREMENTS=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$REQUIREMENTS")
REQUIREMENTS_FILE_PATH=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$REQUIREMENTS_FILE_PATH")
LAMBDA_LAYER_NAME=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$LAMBDA_LAYER_NAME")
LAMBDA_LAYER_S3_BUCKET_NAME=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$LAMBDA_LAYER_S3_BUCKET_NAME")
LAMBDA_LAYER_S3_DIR_KEY=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$LAMBDA_LAYER_S3_DIR_KEY")
LAMBDA_LAYER_LICENSE_INFO=$(sed -r 's/^[[:space:]]*|[[:space:]]*$//g' <<< "$LAMBDA_LAYER_LICENSE_INFO")

echo "------------------------------ $0 input parameters ------------------------------"
echo "-r REQUIREMENTS                :" "$REQUIREMENTS"
echo "-p REQUIREMENTS_FILE_PATH      :" "$REQUIREMENTS_FILE_PATH"
echo "-n LAMBDA_LAYER_NAME           :" "$LAMBDA_LAYER_NAME"
echo "-s LAMBDA_LAYER_S3_BUCKET_NAME :" "$LAMBDA_LAYER_S3_BUCKET_NAME"
echo "-k LAMBDA_LAYER_S3_DIR_KEY     :" "$LAMBDA_LAYER_S3_DIR_KEY"
echo "-l LAMBDA_LAYER_LICENSE_INFO   :" "$LAMBDA_LAYER_LICENSE_INFO"
echo "------------------------------ $0 input parameters ------------------------------"

HAS_ERROR=false

if !(type "python" > /dev/null 2>&1); then
  HAS_ERROR=true
  echo "cannot use 'python' command."
fi

if !(type "zip" > /dev/null 2>&1); then
  HAS_ERROR=true
  echo "cannot use 'zip' command."
fi

CAN_USE_AWS_CLI=false
if [ -n "$REQUIREMENTS_FILE_PATH" ] || [ -n "$LAMBDA_LAYER_S3_BUCKET_NAME" ]; then
  if !(type "aws" > /dev/null 2>&1); then
    HAS_ERROR=true
    echo "cannot use 'aws' command."
  else
    CAN_USE_AWS_CLI=true
  fi
fi

if [ -z "$REQUIREMENTS" ] && [ -z "$REQUIREMENTS_FILE_PATH" ]; then
  HAS_ERROR=true
  echo "Either '-r REQUIREMENTS' or '-p REQUIREMENTS_FILE_PATH' is required."
fi

REQUIREMENTS_FILE_NAME=
REQUIREMENTS_FILE_S3_EXISTS=false
if [ -n "$REQUIREMENTS_FILE_PATH" ]; then
  REQUIREMENTS_FILE_NAME=$(echo -n "$REQUIREMENTS_FILE_PATH" | awk -F "/" '{ print $NF }')
  REQUIREMENTS_FILE_PATH_PREFIX=$(echo -n "$REQUIREMENTS_FILE_PATH" | sed -E 's/^(.{5}).*$/\1/')
  if [ "$REQUIREMENTS_FILE_PATH_PREFIX" = "s3://" ]; then
    if [ "$CAN_USE_AWS_CLI" = "true" ]; then
      S3_LS_RESULT=$(aws s3 ls "$REQUIREMENTS_FILE_PATH" 2>&1)
      S3_LS_RESULT_GREP=$(echo -n "$S3_LS_RESULT" | grep -w "$REQUIREMENTS_FILE_NAME")
      if [ -z "$S3_LS_RESULT_GREP" ]; then
        HAS_ERROR=true
        echo "'-s REQUIREMENTS_FILE_PATH':"$REQUIREMENTS_FILE_PATH" is not exists or cannot access."
        echo "$S3_LS_RESULT"
      else
        REQUIREMENTS_FILE_S3_EXISTS=true
      fi
    fi
  elif [ ! -f "$REQUIREMENTS_FILE_PATH" ]; then
    HAS_ERROR=true
    echo "'-p REQUIREMENTS_FILE_PATH':"$REQUIREMENTS_FILE_PATH" is not exists."
  fi
fi

if [ -z "$LAMBDA_LAYER_NAME" ]; then
  HAS_ERROR=true
  echo "'-n LAMBDA_LAYER_NAME' is required."
fi

if [ -n "$LAMBDA_LAYER_S3_BUCKET_NAME" ] && [ "$CAN_USE_AWS_CLI" = "true" ]; then
  S3_API_RESULT=$(aws s3api head-bucket --bucket "$LAMBDA_LAYER_S3_BUCKET_NAME" 2>&1)
  if [[ "$S3_API_RESULT" != *"BucketRegion"* ]]; then
    HAS_ERROR=true
    echo "'-s LAMBDA_LAYER_S3_BUCKET_NAME':"$LAMBDA_LAYER_S3_BUCKET_NAME" is not exists or cannot access."
    echo "$S3_API_RESULT"
  fi
fi

if [ "$HAS_ERROR" = "true" ]; then
  echo "validation error. publish python lambda layer failed."
  exit 1
fi

PYTHON_PACKAGES_INSTALL_DIR_NAME="$LAMBDA_LAYER_NAME"_"$DATETIME_MILLISEC"
PYTHON_PACKAGES_INSTALL_DIR_PATH=/tmp/"$PYTHON_PACKAGES_INSTALL_DIR_NAME"
if [ -n "$REQUIREMENTS_FILE_PATH" ]; then
  if [ "$REQUIREMENTS_FILE_S3_EXISTS" = "true" ]; then
    aws s3 cp "$REQUIREMENTS_FILE_PATH" /tmp
    REQUIREMENTS_FILE_CONTENTS=$(cat /tmp/"$REQUIREMENTS_FILE_NAME")
  else
    REQUIREMENTS_FILE_CONTENTS=$(cat "$REQUIREMENTS_FILE_PATH")
  fi
  REQUIREMENTS_FILE_CONTENTS=$(echo -n "$REQUIREMENTS_FILE_CONTENTS" | awk -v RS="\r\n" -v ORS="\n" '{print $0}')
  REQUIREMENTS_FILE_CONTENTS=$(echo -n "$REQUIREMENTS_FILE_CONTENTS" | awk -v RS="\r" -v ORS="\n" '{print $0}')
else
  REQUIREMENTS_FILE_CONTENTS=$(echo -n "$REQUIREMENTS" | tr "|" "\n")
fi
REQUIREMENTS_FILE_CONTENTS_PATH="$PYTHON_PACKAGES_INSTALL_DIR_PATH"_requirements.txt
echo -n "$REQUIREMENTS_FILE_CONTENTS" > "$REQUIREMENTS_FILE_CONTENTS_PATH"

CPU_ARCHITECTURE=$(uname -m)
if [ "$CPU_ARCHITECTURE" = "aarch64" ]; then
  CPU_ARCHITECTURE=arm64
fi

PYTHON_VERSION=$(python --version)
PYTHON_VERSION=$(echo -n "$PYTHON_VERSION" | cut -d' ' -f2)
PYTHON_MAJOR_VERSION=$(echo -n "$PYTHON_VERSION" | cut -d'.' -f1)
PYTHON_MINOR_VERSION=$(echo -n "$PYTHON_VERSION" | cut -d'.' -f2)
PYTHON_RUNTIME_VERSION=python"$PYTHON_MAJOR_VERSION"."$PYTHON_MINOR_VERSION"

mkdir -p "$PYTHON_PACKAGES_INSTALL_DIR_PATH"
python -m pip install -r "$REQUIREMENTS_FILE_CONTENTS_PATH" -t "$PYTHON_PACKAGES_INSTALL_DIR_PATH"/python/lib/"$PYTHON_RUNTIME_VERSION"/site-packages

cd "$PYTHON_PACKAGES_INSTALL_DIR_PATH"
LAMBDA_LAYER_FILE_NAME="$PYTHON_PACKAGES_INSTALL_DIR_NAME".zip
zip -q -r ../"$LAMBDA_LAYER_FILE_NAME" python
cd ../

LAMBDA_LAYER_S3KEY="$LAMBDA_LAYER_S3_DIR_KEY"/"$LAMBDA_LAYER_FILE_NAME"
LAMBDA_LAYER_UPLOAD_URL=s3://"$LAMBDA_LAYER_S3_BUCKET_NAME"/"$LAMBDA_LAYER_S3KEY"

echo "------------------------------ $0 layer information ------------------------------"
echo "create env cpu architecture    :" "$CPU_ARCHITECTURE"
echo "create env python version      :" "$PYTHON_VERSION"
echo "lambda layer zip file name     :" "$LAMBDA_LAYER_FILE_NAME"
if [ -n "$LAMBDA_LAYER_S3_BUCKET_NAME" ]; then
  echo "lambda layer upload url        :" "$LAMBDA_LAYER_UPLOAD_URL"
fi
echo "lambda layer zip file size     :" $(echo `du -h -s "$LAMBDA_LAYER_FILE_NAME"` | cut -d' ' -f1)
echo "lambda layer unzip size        :" $(echo `du -h -s "$PYTHON_PACKAGES_INSTALL_DIR_NAME"` | cut -d' ' -f1)
echo "requirements                   :"
echo "$REQUIREMENTS_FILE_CONTENTS"
echo "------------------------------ $0 layer information ------------------------------"

rm -rf "$PYTHON_PACKAGES_INSTALL_DIR_NAME"

if [ -z "$LAMBDA_LAYER_S3_BUCKET_NAME" ]; then
  echo create lambda layer completed.
  exit 0
fi

REQUIREMENTS_FILE_CONTENTS=$(echo -n "$REQUIREMENTS_FILE_CONTENTS" | tr "\n", "|")
LAMBDA_LAYER_LICENSE_INFO2048=$(echo -n "$LAMBDA_LAYER_LICENSE_INFO" | sed -E 's/^(.{2048}).*$/\1/')
REQUIREMENTS_FILE_CONTENTS2048=$(echo -n "$REQUIREMENTS_FILE_CONTENTS" | sed -E 's/^(.{2048}).*$/\1/')

aws s3 cp "$LAMBDA_LAYER_FILE_NAME" "$LAMBDA_LAYER_UPLOAD_URL" \
  --metadata layer-name="$LAMBDA_LAYER_NAME",requirements="$REQUIREMENTS_FILE_CONTENTS2048",license-info="$LAMBDA_LAYER_LICENSE_INFO2048",python-version="$PYTHON_VERSION",compatible-runtimes="$PYTHON_RUNTIME_VERSION",compatible-architectures="$CPU_ARCHITECTURE",create-date="$DATETIME_MILLISEC"

REQUIREMENTS_FILE_CONTENTS256=$(echo -n "$REQUIREMENTS_FILE_CONTENTS" | sed -E 's/^(.{256}).*$/\1/')

aws lambda publish-layer-version \
  --layer-name "$LAMBDA_LAYER_NAME" \
  --description "$REQUIREMENTS_FILE_CONTENTS256" \
  --license-info "$LAMBDA_LAYER_LICENSE_INFO" \
  --compatible-runtimes "$PYTHON_RUNTIME_VERSION" \
  --compatible-architectures "$CPU_ARCHITECTURE" \
  --content S3Bucket="$LAMBDA_LAYER_S3_BUCKET_NAME",S3Key="$LAMBDA_LAYER_S3KEY"
