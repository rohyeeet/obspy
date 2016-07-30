#!/bin/bash

# remove log directories older than 14 days (to avoid cluttering with GB of
# data on buildbots that are run regularly)
find logs/2[0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]T[012][0-9]-[0-5][0-9]-[0-5][0-9]Z -type d -not -newermt `date --date='14 days ago' --rfc-3339=date` -exec rm -rf {} \;

OBSPY_PATH=$(dirname $(dirname $(pwd)))

# Remove all test images stored locally. Otherwise they'll end up on the
# images.
rm -rf $OBSPY_PATH/obspy/core/tests/images/testrun
rm -rf $OBSPY_PATH/obspy/imaging/tests/images/testrun
rm -rf $OBSPY_PATH/obspy/station/tests/images/testrun

DOCKERFILE_FOLDER=base_images
TEMP_PATH=temp
NEW_OBSPY_PATH=$TEMP_PATH/obspy
DATETIME=$(date -u +"%Y-%m-%dT%H-%M-%SZ")

# Determine the docker binary name. The official debian packages use docker.io
# for the binary's name due to some legacy docker package.
DOCKER=`which docker.io || which docker`

# Execute Python once and import ObsPy to trigger building the RELEASE-VERSION
# file.
python -c "import obspy"


# Create temporary folder.
rm -rf $TEMP_PATH
mkdir -p $TEMP_PATH

# Copy ObsPy to the temp path. This path is the execution context of the Docker images.
mkdir -p $NEW_OBSPY_PATH
# depending on env variable OBSPY_DOCKER_TEST_SOURCE_TREE ("cp" or "clone")
# we either copy the obspy tree (potentially with local changes) or
# `git clone` from it for a tree free of local changes
if [ ! "$OBSPY_DOCKER_TEST_SOURCE_TREE" ]
then
    # default to "cp" to not change default behavior
    OBSPY_DOCKER_TEST_SOURCE_TREE="cp"
fi
if [ "$OBSPY_DOCKER_TEST_SOURCE_TREE" == "cp" ]
then
    cp -r $OBSPY_PATH/obspy $NEW_OBSPY_PATH/obspy/
    cp $OBSPY_PATH/setup.py $NEW_OBSPY_PATH/setup.py
    cp $OBSPY_PATH/MANIFEST.in $NEW_OBSPY_PATH/MANIFEST.in
    rm -f $NEW_OBSPY_PATH/obspy/lib/*.so
elif [ "$OBSPY_DOCKER_TEST_SOURCE_TREE" == "clone" ]
then
    git clone file://$OBSPY_PATH $NEW_OBSPY_PATH
    # we're cloning so we have a non-dirty version actually
    cat $OBSPY_PATH/obspy/RELEASE-VERSION | sed 's#\.dirty$##' > $NEW_OBSPY_PATH/obspy/RELEASE-VERSION
else
    echo "Bad value for OBSPY_DOCKER_TEST_SOURCE_TREE: $OBSPY_DOCKER_TEST_SOURCE_TREE"
    exit 1
fi


# Copy the install script.
cp scripts/install_and_run_tests_on_image.sh $TEMP_PATH/install_and_run_tests_on_image.sh


# Helper function checking if an element is in an array.
list_not_contains() {
    for word in $1; do
        [[ $word == $2 ]] && return 1
    done
    return 0
}


# Function creating an image if it does not exist.
create_image () {
    image_name=$1;
    has_image=$($DOCKER images | grep obspy | grep $image_name)
    if [ "$has_image" ]; then
        printf "\e[101m\e[30m  >>> Image '$image_name' already exists.\e[0m\n"
    else
        printf "\e[101m\e[30m  Image '$image_name'will be created.\e[0m\n"
        $DOCKER build -t obspy:$image_name $image_path
    fi
}


# Function running test on an image.
run_tests_on_image () {
    image_name=$1;
    printf "\n\e[101m\e[30m  >>> Running tests for image '"$image_name"'...\e[0m\n"
    # Copy dockerfile and render template.
    sed 's/{{IMAGE_NAME}}/'$image_name'/g' scripts/Dockerfile_run_tests.tmpl > $TEMP_PATH/Dockerfile

    # Where to save the logs, and a random ID for the containers.
    LOG_DIR=logs/$DATETIME/$image_name
    mkdir -p $LOG_DIR
    ID=$RANDOM-$RANDOM-$RANDOM

    $DOCKER build -t temp:temp $TEMP_PATH

    $DOCKER run --name=$ID temp:temp

    $DOCKER cp $ID:/INSTALL_LOG.txt $LOG_DIR
    $DOCKER cp $ID:/TEST_LOG.txt $LOG_DIR

    $DOCKER cp $ID:/obspy/obspy/imaging/tests/images/testrun $LOG_DIR/imaging_testrun
    $DOCKER cp $ID:/obspy/obspy/core/tests/images/testrun $LOG_DIR/core_testrun
    $DOCKER cp $ID:/obspy/obspy/station/tests/images/testrun $LOG_DIR/station_testrun

    mkdir -p $LOG_DIR/test_images

    mv $LOG_DIR/imaging_testrun/testrun $LOG_DIR/test_images/imaging
    mv $LOG_DIR/core_testrun/testrun $LOG_DIR/test_images/core
    mv $LOG_DIR/station_testrun/testrun $LOG_DIR/test_images/station

    rm -rf $LOG_DIR/imaging_testrun
    rm -rf $LOG_DIR/core_testrun
    rm -rf $LOG_DIR/station_testrun

    $DOCKER rm $ID
    $DOCKER rmi temp:temp
}


# 1. Build all the base images if they do not yet exist.
printf "\e[44m\e[30mSTEP 1: CREATING BASE IMAGES\e[0m\n"

for image_path in $DOCKERFILE_FOLDER/*; do
    image_name=$(basename $image_path)
    if [ $# != 0 ]; then
        if list_not_contains "$*" $image_name; then
            continue
        fi
    fi
    create_image $image_name;
done


# 2. Execute the ObsPy
printf "\n\e[44m\e[30mSTEP 2: EXECUTING THE TESTS\e[0m\n"

# Loop over all ObsPy Docker images.
for image_name in $($DOCKER images | grep obspy | awk '{print $2}'); do
    if [ $# != 0 ]; then
        if list_not_contains "$*" $image_name; then
            continue
        fi
    fi
    run_tests_on_image $image_name;
done

rm -rf $TEMP_PATH
