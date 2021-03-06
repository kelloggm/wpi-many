#!/bin/bash

# This script performs WPI via dljc on a given project directory.
# The inputs are similar to wpi-many.sh, which uses this script internally.
# The only difference is that wpi-many.sh takes a list of projects, while
# this script operates on a single project at a time.
# See the documentation of wpi-many.sh for information on the inputs to this
# script.
#
# Input differences compared to wpi-many.sh:
# -i and -o are not valid options
# new required option -d: the absolute path to the directory containing the target project
#

while getopts "d:u:t:" opt; do
  case $opt in
    d) DIR="$OPTARG"
       ;;
    u) USER="$OPTARG"
       ;;
    t) TIMEOUT="$OPTARG"
       ;;        
    \?) # echo "Invalid option -$OPTARG" >&2
       ;;
  esac
done

# Make $@ be the arguments that should be passed to dljc.
shift $(( OPTIND - 1 ))

# check required arguments and environment variables:

# Testing for JAVA8_HOME, not a misspelling of JAVA_HOME.
# shellcheck disable=SC2153
if [ "x${JAVA8_HOME}" = "x" ]; then
    echo "JAVA8_HOME must be set to a Java 8 JDK"
    exit 1
fi

if [ ! -d "${JAVA8_HOME}" ]; then
    echo "JAVA8_HOME is set to a non-existent directory ${JAVA8_HOME}"
    exit 1
fi

# Testing for JAVA11_HOME, not a misspelling of JAVA_HOME.
# shellcheck disable=SC2153
if [ "x${JAVA11_HOME}" = "x" ]; then
    echo "JAVA11_HOME must be set to a Java 11 JDK"
    exit 1
fi

if [ ! -d "${JAVA11_HOME}" ]; then
    echo "JAVA11_HOME is set to a non-existent directory ${JAVA11_HOME}"
    exit 1
fi

JAVA_HOME="${JAVA11_HOME}"

if [ "x${CHECKERFRAMEWORK}" = "x" ]; then
    echo "CHECKERFRAMEWORK is not set; it must be set to a locally-built Checker Framework. Please clone and build github.com/typetools/checker-framework"
    exit 2
fi

if [ ! -d "${CHECKERFRAMEWORK}" ]; then
    echo "CHECKERFRAMEWORK is set to a non-existent directory ${CHECKERFRAMEWORK}"
    exit 2
fi

if [ "x${DIR}" = "x" ]; then
    echo "wpi.sh was called without a -d argument. The -d argument must be the absolute path to the directory containing the project on which to run WPI."
    exit 4
fi

if [ ! -d "${DIR}" ]; then
    echo "wpi.sh's -d argument was not a directory: ${DIR}"
    exit 4
fi

function configure_and_exec_dljc {

  if [ -f build.gradle ]; then
      if [ -f gradlew ]; then
	  chmod +x gradlew
	  GRADLE_EXEC="./gradlew"
      else
	  GRADLE_EXEC="gradle"
      fi
      CLEAN_CMD="${GRADLE_EXEC} clean -g .gradle -Dorg.gradle.java.home=${JAVA_HOME}"
      BUILD_CMD="${GRADLE_EXEC} clean compileJava -g .gradle -Dorg.gradle.java.home=${JAVA_HOME}"
  elif [ -f pom.xml ]; then
      if [ -f mvnw ]; then
	  chmod +x mvnw
	  MVN_EXEC="./mvnw"
      else
	  MVN_EXEC="mvn"
      fi
      # if running on java 8, need /jre at the end of this Maven command
      if [ "${JAVA_HOME}" = "${JAVA8_HOME}" ]; then
          CLEAN_CMD="${MVN_EXEC} clean -Djava.home=${JAVA_HOME}/jre"
          BUILD_CMD="${MVN_EXEC} clean compile -Djava.home=${JAVA_HOME}/jre"
      else
          CLEAN_CMD="${MVN_EXEC} clean -Djava.home=${JAVA_HOME}"
          BUILD_CMD="${MVN_EXEC} clean compile -Djava.home=${JAVA_HOME}"
      fi
  else
      echo "no build file found for ${REPO_NAME}; not calling DLJC"
      WPI_RESULTS_AVAILABLE="no"
      return
  fi
    
  DLJC_CMD="${DLJC} -t wpi $* -- ${BUILD_CMD}"

  if [ ! "x${TIMEOUT}" = "x" ]; then
      TMP="${DLJC_CMD}"
      DLJC_CMD="timeout ${TIMEOUT} ${TMP}"
  fi

  # Remove old DLJC output.
  rm -rf dljc-out

  # ensure the project is clean before invoking DLJC
  eval "${CLEAN_CMD}" < /dev/null

  echo "${DLJC_CMD}"

  # This command also includes "clean"; I'm not sure why it is necessary.
  eval "${DLJC_CMD}" < /dev/null

  if [[ $? -eq 124 ]]; then
      echo "dljc timed out for ${DIR}"
      WPI_RESULTS_AVAILABLE="no"
      return
  fi

  if [ -f dljc-out/wpi.log ]; then
      WPI_RESULTS_AVAILABLE="yes"
  else
      WPI_RESULTS_AVAILABLE="no"
  fi
}

#### Check and setup dependencies

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# clone or update DLJC
if [ ! -d "${SCRIPTDIR}/../do-like-javac" ]; then
    git -C "${SCRIPTDIR}/.." clone https://github.com/kelloggm/do-like-javac
else
    git -C "${SCRIPTDIR}/../do-like-javac" pull
fi

DLJC="${SCRIPTDIR}/../do-like-javac/dljc"

#### Main script

pushd "${DIR}" || exit 1

configure_and_exec_dljc "$@"

if [ "${WPI_RESULTS_AVAILABLE}" = "no" ]; then
      # if running under Java 11 fails, try to run
      # under Java 8 instead
    export JAVA_HOME="${JAVA8_HOME}"
    echo "couldn't build using Java 11; trying Java 8"
    configure_and_exec_dljc "$@"
    export JAVA_HOME="${JAVA11_HOME}"
fi

# support wpi-many.sh's ability to delete projects without usable results
# automatically
if [ "${WPI_RESULTS_AVAILABLE}" = "no" ]; then
    echo "dljc could not run the build successfully"
    touch .cannot-run-wpi
fi

popd || exit 1
