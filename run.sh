#!/bin/bash

function main {
  prepare_execution
  run_suite_targets functional _sanity _extended _special
  for suite in openjdk system perf ; do
    run_suite_targets "$suite" _sanity _extended
  done
  cleanup_execution

  if [ "$#" -eq 0 ]; then
    echo "No gcloud storage bucked address was provided, skipping upload."
  else
    upload_results  "$1"
  fi

  echo "Done! Results file is at $results_file_location"
}

function prepare_execution {
  # AQAVIT envvars
  if [ -z "$JAVA_HOME" ] ; then
    echo "\$JAVA_HOME must be set for this script to function properly"
    exit 1
  fi
  export TEST_JDK_HOME=$JAVA_HOME
  export USE_TESTENV_PROPERTIES=true
  export JDK_VERSION=17
  export JDK_IMPL=hotspot


  # TODO it may be better to pass these parameters from the execution trigger
  #  rather than infer them from the system
  # Also these variables are only used to name the results file.
  OS_DISTRIBUTION=$(lsb_release -si)
  OS_VERSION=$(lsb_release -sr)
  case $(uname -m) in
    "arm64") ARCH=arm64 ;;
    "aarch64") ARCH=arm64 ;;
    "x86_64") ARCH=amd64 ;;
    *) echo "Unsupported architecture" ; exit 1
  esac

  work_dir=$(mktemp -d)
  pushd "$work_dir"
  mkdir results
  results_dir="$work_dir/results"
}

# This function creates a fresh checkout for the suite, under the assumption
# that get.sh and compile.sh may not be compatible with multiple invocations
# for different BUILD_LIST values. Should simplify this if that's not the case.
function prepare_suite {
  local suite=$1
  mkdir "$suite"
  cd "$suite"
  # TODO map branch name to JDK version
  # each aqa-tests release is tested for one specific set of JDK versions
  # https://github.com/adoptium/aqa-tests/releases/tag/v0.9.6
  local branch="v0.9.6-release"
  git clone --depth 1 --branch "$branch" https://github.com/adoptium/aqa-tests.git
  export BUILD_LIST=$suite
  cd aqa-tests
  ./get.sh
  ./compile.sh
  cd TKG
}

function cleanup_suite {
  mv output_*/*.tap "$results_dir/"
  cd ../../../
}

function cleanup_execution {
  echo "Results directory is $results_dir"
  results_file_name="aqa-results-$OS_DISTRIBUTION-$OS_VERSION-$ARCH-$(date +"%Y_%m_%d_%I_%M_%p_%Z%z").tar.gz"
  results_file_location="$work_dir/$results_file_name"
  tar cvzf "$results_file_location" results/*.tap
  popd
}

function upload_results {
  local upload_location="gs://$1/"
  gcloud storage cp "$results_file_location" "$upload_location"
  echo "Uploaded results to $upload_location/$results_file_name"
}

function run_suite_targets {
    local suite=$1
    shift;
    prepare_suite "$suite"
    for target in "$@" ; do
      echo "Running target $target on suite $suite"
      make "$target.$suite"
    done
    cleanup_suite
}

main "$@"