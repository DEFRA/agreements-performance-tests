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

WMP_SCENARIO=wmp-test
WMP_SCENARIOFILE=${JM_SCENARIOS}/${WMP_SCENARIO}.jmx
WMP_REPORTFILE=${NOW}-perftest-${WMP_SCENARIO}-report.csv
WMP_LOGFILE=${JM_LOGS}/perftest-${WMP_SCENARIO}.log

echo "Starting WMP test..."
jmeter -n -t ${WMP_SCENARIOFILE} -e -l "${WMP_REPORTFILE}" -o ${JM_REPORTS} -j ${WMP_LOGFILE} -f -Jenv="${ENVIRONMENT}" -Jcsv_path="${JM_DATA}" -Juser_count="${USER_COUNT}" -Jramp_up_period_seconds="${RAMP_UP_PERIOD_SECONDS}" -Jduration_seconds="${DURATION_SECONDS}"
WMP_EXIT=$?
echo "WMP test exit code: ${WMP_EXIT}"

# Publish the results into S3 so they can be displayed in the CDP Portal
if [ -n "$RESULTS_OUTPUT_S3_PATH" ]; then
  if [ -f "${JM_REPORTS}/index.html" ]; then
    aws --endpoint-url=$S3_ENDPOINT s3 rm "$RESULTS_OUTPUT_S3_PATH" --recursive
    aws --endpoint-url=$S3_ENDPOINT s3 cp "$WMP_REPORTFILE" "$RESULTS_OUTPUT_S3_PATH/$WMP_REPORTFILE"
    aws --endpoint-url=$S3_ENDPOINT s3 cp "${JM_REPORTS}/" "$RESULTS_OUTPUT_S3_PATH/" --recursive
    if [ $? -eq 0 ]; then
      echo "Test results published to $RESULTS_OUTPUT_S3_PATH"
    fi
  else
    echo "No index.html found in report directory"
    exit 1
  fi
else
  echo "RESULTS_OUTPUT_S3_PATH is not set"
  exit 1
fi

# Exit non-zero if test had failures
if grep -q ',false,' "${WMP_REPORTFILE}" 2>/dev/null; then
  echo "WMP test CONTAINS FAILURES"
  echo "RESULTS CONTAIN FAILURES, EXITING NON-ZERO"
  exit 1
fi
