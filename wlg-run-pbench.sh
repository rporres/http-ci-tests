#!/bin/sh

# This is a wrapper script for pbench.

main() {
  test "$HTTP_TEST_SERVER_RESULTS" && {
    local server_results=$(echo ${HTTP_TEST_SERVER_RESULTS:6} | cut -d: -f1)
    HTTP_TEST_SERVER_RESULTS="${HTTP_TEST_SERVER_RESULTS:0:6}${server_results}:$benchmark_run_dir"
  }

  ./wlg-run.sh
}

main
