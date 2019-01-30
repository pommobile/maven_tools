#!/bin/bash -ex

# Copy maven settings to default settings location
TARGET_DIR=/root/.m2
[ ! -d $TARGET_DIR ] && exit -1 || :
SOURCE_FILE_NAME=settings.xml
[ -f ./src/main/resources/$SOURCE_FILE_NAME ] && SOURCE_FILE=./src/main/resources/$SOURCE_FILE_NAME || SOURCE_FILE=./$SOURCE_FILE_NAME
cp -v $SOURCE_FILE $TARGET_DIR

