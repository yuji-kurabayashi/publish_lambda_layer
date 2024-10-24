# see https://hub.docker.com/r/amazon/aws-lambda-python/
ARG BASE_IMAGE_TAG=latest

FROM amazon/aws-lambda-python:${BASE_IMAGE_TAG?}

COPY ./PublishPythonLambdaLayer.sh .

RUN <<EOF
chmod +x ./PublishPythonLambdaLayer.sh

# for Amazon Linux 2023 (for python 3.12)
if (type dnf > /dev/null 2>&1); then
  # see https://docs.aws.amazon.com/ja_jp/linux/al2023/ug/deterministic-upgrades-usage.html
  # dnf update -y
  dnf upgrade -y --releasever=latest
  dnf install -y zip unzip
  dnf clean all
  rm -rf /var/cache/dnf/*
# for Amazon Linux 2 (for python 3.11)
elif (type yum > /dev/null 2>&1); then
  yum update -y
  yum install -y zip unzip
  yum clean all
  rm -rf /var/cache/yum/*
else
  echo update failed. unsupported package management tool.
  exit 1
fi

# see https://docs.aws.amazon.com/ja_jp/cli/latest/userguide/getting-started-install.html
if !(type aws > /dev/null 2>&1); then
  CPU_ARCHITECTURE=$(uname -m)
  if [ "$CPU_ARCHITECTURE" = "x86_64" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  elif [ "$CPU_ARCHITECTURE" = "aarch64" ]; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
  else
    echo aws cli install failed. unsupported cpu architecture.
    exit 1
  fi
  unzip -qq awscliv2.zip
  ./aws/install > /dev/null 2>&1
  rm -f awscliv2.zip
fi
EOF

ENTRYPOINT [ "bash", "./PublishPythonLambdaLayer.sh" ]
CMD [ "" ]
