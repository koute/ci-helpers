#!/bin/bash
# Parts of this script are based on this gist:
#   https://gist.github.com/domenic/ec8b0fc8ab45f39403dd

IFS=$'\n\t'
set -euo pipefail

##
# Detect environment
##

if [ $TRAVIS_OS_NAME == linux ]; then
    if [ $ARCH == 'i686' ]; then
        export TARGET="i686-unknown-linux-gnu"
        export EXTRA_CFLAGS="-m32"
    elif [ $ARCH == 'x86_64' ]; then
        export TARGET="x86_64-unknown-linux-gnu"
        export EXTRA_CFLAGS="-m64"
    else
        echo "No arch defined!"
        exit 1
    fi
else
    echo "Unknown OS!"
    exit 1
fi

##
# Configure
##

source ./config.sh

##
# Prepare
##

export SOURCE_BRANCH="${SOURCE_BRANCH:-master}"
export TARGET_BRANCH="${TARGET_BRANCH:-gh-pages}"

export BUILD_CMAKE="${BUILD_CMAKE:-false}"
export INSTALL_CMAKE="${INSTALL_CMAKE:-false}"

export REPOSITORY=`git config remote.origin.url`
export SSH_REPOSITORY=${REPOSITORY/https:\/\/github.com\//git@github.com:}
export COMMIT_HASH=`git rev-parse --verify HEAD`

git clone $REPOSITORY deployment

pushd deployment
git checkout $TARGET_BRANCH || git checkout --orphan $TARGET_BRANCH
popd # deployment

if [ -f "deployment/$OUTPUT" ]; then
    echo "$OUTPUT already exists in the repository! Nothing to do."
    exit 0
fi

##
# Prepare dependencies
##

mkdir -p /tmp/tools/usr/local/bin
export PATH=/tmp/tools/usr/local/bin:$PATH

if [ $BUILD_CMAKE == true ]; then
    curl -Lo cmake-3.7.2.tar.gz https://cmake.org/files/v3.7/cmake-3.7.2.tar.gz
    tar -xf cmake-3.7.2.tar.gz
    pushd cmake-3.7.2

    ./configure --parallel=4
    make -j 4
    make install DESTDIR=/tmp/tools

    popd # cmake-3.7.2
elif [ $INSTALL_CMAKE == true ]; then
    curl -Lo cmake-3.7.2-Linux-x86_64.sh https://cmake.org/files/v3.7/cmake-3.7.2-Linux-x86_64.sh
    chmod +x ./cmake-3.7.2-Linux-x86_64.sh
    ./cmake-3.7.2-Linux-x86_64.sh --skip-license --prefix=/tmp/tools/usr/local
fi

##
# Build
##

source ./build.sh
sha256sum $OUTPUT

##
# Deploy
##

if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
    echo "Skipping deployment"
    exit 0
fi

cp $OUTPUT deployment/$OUTPUT
sha256sum $OUTPUT > deployment/$OUTPUT.sha256

pushd deployment
if [ $(git status --porcelain | wc -l) -lt 1 ]; then
    echo "No changes; exiting."
    exit 0
fi

git config user.name "Travis CI"
git config user.email "$COMMIT_AUTHOR_EMAIL"

git add -A .
git commit -m "Deploy $OUTPUT based on commit $COMMIT_HASH"

ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
eval `ssh-agent -s`
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in ../deploy_key.enc -d | ssh-add -

git push $SSH_REPOSITORY $TARGET_BRANCH
popd # deployment
