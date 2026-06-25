#!/bin/sh

echo "run_id: $RUN_ID in $ENVIRONMENT"

NOW=$(date +"%Y%m%d-%H%M%S")

if [ -z "${JM_HOME}" ]; then
  JM_HOME=/opt/perftest
fi

JM_SCENARIOS=${JM_HOME}/scenarios
JM_REPORTS=${JM_HOME}/reports
JM_LOGS=${JM_HOME}/logs
JM_DATA=${JM_HOME}/data

mkdir -p ${JM_REPORTS} ${JM_LOGS}

FRPS_SCENARIO=test
WMP_SCENARIO=wmp-test

FRPS_SCENARIOFILE=${JM_SCENARIOS}/${FRPS_SCENARIO}.jmx
WMP_SCENARIOFILE=${JM_SCENARIOS}/${WMP_SCENARIO}.jmx

FRPS_REPORTFILE=${NOW}-perftest-${FRPS_SCENARIO}-report.csv
WMP_REPORTFILE=${NOW}-perftest-${WMP_SCENARIO}-report.csv

FRPS_REPORTS=${JM_REPORTS}/frps
WMP_REPORTS=${JM_REPORTS}/wmp

FRPS_LOGFILE=${JM_LOGS}/perftest-${FRPS_SCENARIO}.log
WMP_LOGFILE=${JM_LOGS}/perftest-${WMP_SCENARIO}.log

mkdir -p ${FRPS_REPORTS} ${WMP_REPORTS}

# Run sequentially to avoid JMeter resource contention that prevents HTML report generation
echo "Starting FRPS test..."
jmeter -n -t ${FRPS_SCENARIOFILE} -e -l "${FRPS_REPORTFILE}" -o ${FRPS_REPORTS} -j ${FRPS_LOGFILE} -f -Jenv="${ENVIRONMENT}" -Jcsv_path="${JM_DATA}" -Juser_count="${USER_COUNT}" -Jramp_up_period_seconds="${RAMP_UP_PERIOD_SECONDS}" -Jduration_seconds="${DURATION_SECONDS}"
FRPS_EXIT=$?
echo "FRPS test exit code: ${FRPS_EXIT}"

echo "Starting WMP test..."
jmeter -n -t ${WMP_SCENARIOFILE} -e -l "${WMP_REPORTFILE}" -o ${WMP_REPORTS} -j ${WMP_LOGFILE} -f -Jenv="${ENVIRONMENT}" -Jcsv_path="${JM_DATA}" -Juser_count="${USER_COUNT}" -Jramp_up_period_seconds="${RAMP_UP_PERIOD_SECONDS}" -Jduration_seconds="${DURATION_SECONDS}"
WMP_EXIT=$?
echo "WMP test exit code: ${WMP_EXIT}"

# Publish the results into S3 so they can be displayed in the CDP Portal
if [ -n "$RESULTS_OUTPUT_S3_PATH" ]; then
  if [ -f "${FRPS_REPORTS}/index.html" ] || [ -f "${WMP_REPORTS}/index.html" ]; then
    # Create a root index.html linking to both sub-reports so the CDP portal has an entry point
    printf '<!DOCTYPE html>\n<html>\n<head><meta charset="utf-8"><title>Agreements Performance Test Results</title></head>\n<body>\n<h1>Agreements Performance Test Results</h1>\n<ul>\n  <li><a href="frps/index.html">FRPS Report</a></li>\n  <li><a href="wmp/index.html">WMP Report</a></li>\n</ul>\n</body>\n</html>\n' > "${JM_REPORTS}/index.html"
    aws --endpoint-url=$S3_ENDPOINT s3 rm "$RESULTS_OUTPUT_S3_PATH" --recursive
    aws --endpoint-url=$S3_ENDPOINT s3 cp "$FRPS_REPORTFILE" "$RESULTS_OUTPUT_S3_PATH/$FRPS_REPORTFILE"
    aws --endpoint-url=$S3_ENDPOINT s3 cp "$WMP_REPORTFILE" "$RESULTS_OUTPUT_S3_PATH/$WMP_REPORTFILE"
    aws --endpoint-url=$S3_ENDPOINT s3 cp "${JM_REPORTS}/" "$RESULTS_OUTPUT_S3_PATH/" --recursive
    if [ $? -eq 0 ]; then
      echo "Test results published to $RESULTS_OUTPUT_S3_PATH"
      echo "  FRPS report: $RESULTS_OUTPUT_S3_PATH/frps/index.html"
      echo "  WMP report:  $RESULTS_OUTPUT_S3_PATH/wmp/index.html"
    fi
  else
    echo "No index.html found in either report directory"
    exit 1
  fi
else
  echo "RESULTS_OUTPUT_S3_PATH is not set"
  exit 1
fi

# Exit non-zero if either test had failures
FAILURES=0
if grep -q ',false,' "${FRPS_REPORTFILE}" 2>/dev/null; then
  echo "FRPS test CONTAINS FAILURES"
  FAILURES=1
fi
if grep -q ',false,' "${WMP_REPORTFILE}" 2>/dev/null; then
  echo "WMP test CONTAINS FAILURES"
  FAILURES=1
fi
if [ ${FAILURES} -eq 1 ]; then
  echo "RESULTS CONTAIN FAILURES, EXITING NON-ZERO"
  exit 1
fi
