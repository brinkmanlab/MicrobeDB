#!/usr/bin/env bash
# This script will resubmit an array job for any task id not present in the ./completed_tasks file
# update.sh must have completed successfully before this can run
source $(dirname $(realpath "$0"))/job.env

if [[ ! -f completed_tasks ]]; then
  job=$(sbatch --array="0-$(($TASKCOUNT - 1))%50" "${SRCDIR}/fetch.sh")
  if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
    echo "Scheduling finalize.sh after job ${BASH_REMATCH[1]} completes"
    sbatch --dependency="afterok:${BASH_REMATCH[1]}" "${SRCDIR}/finalize.sh"
    echo "Run 'squeue -rj ${BASH_REMATCH[1]}' to monitor progress"
  else
    echo "finalize.sh failed to schedule, sbatch failed to return job id for fetch.sh"
    exit 1
  fi
  exit
fi

sort -n completed_tasks |
(
  read next_complete
  if (( $? != 0 )); then
    indexs="0-$(($TASKCOUNT - 1))"
  else
    indexs=""
    start=0
    for ((i = 0; i < $TASKCOUNT; i++)); do
      if (( $i == $next_complete )); then
        end=$((i - 1))
        if (( $start == $end )); then
          indexs="$indexs,$start"
        elif (( $start < $end )); then
          indexs="$indexs,$start-$end"
        fi
        start=$((i + 1))
        read next_complete
        if (( $? != 0 )); then
          i=$TASKCOUNT
          break
        fi
      fi
    done
    end=$((i - 1))
    if (( $start == $end )); then
      indexs="$indexs,$start"
    elif (( $start < $end )); then
      indexs="$indexs,$start-$end"
    fi
  fi
  indexs="${indexs:1}"
  echo "$indexs"
  if [[ -n $indexs ]]; then
    job=$(sbatch --array="${indexs}%50" "${SRCDIR}/fetch.sh")
    if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
      echo "Scheduling finalize.sh after job ${BASH_REMATCH[1]} completes"
      sbatch --dependency="afterok:${BASH_REMATCH[1]}" "${SRCDIR}/finalize.sh"
      echo "Run 'squeue -rj ${BASH_REMATCH[1]}' to monitor progress"
    else
      echo "finalize.sh failed to schedule, sbatch failed to return job id for fetch.sh"
      exit 1
    fi
  else
    echo "All fetch jobs complete, rescheduling finalize.sh"
    job=$(sbatch "${SRCDIR}/finalize.sh")
    if [[ $job =~ ([[:digit:]]+) ]]; then # sbatch may return human readable string including job id, or only job id
      echo "Run 'squeue -rj ${BASH_REMATCH[1]}' to monitor progress"
    else
      echo "finalize.sh failed to schedule, sbatch failed to return job id"
      exit 1
    fi
  fi
)