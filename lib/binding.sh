# run .travis.yml
#
# binding.sh - source binding for action.yml action and environment scripts
#

#####
# get eventname
gh_eventname() {
  if [[ "schedule" = "$1" ]]; then
    echo "cron";
  else
    echo "$1";
  fi
}

#####
# get reference name (any type)
gh_refname() {
  echo "${1#refs/*/}";
}

####
# get sudo true/false
gh_sudo() {
  if sudo -nlU "$(whoami)">/dev/null 2>&1; then
    printf 'true';
  else
    printf 'false';
  fi
}

#####
# input binding
gh_input() {
  eval "$1"=\'"$2"\'
}

#####
# reg -> gh_input
reg() {
  gh_input "$1" "${!1:-$2}"
};


gh_state_export_count=0
gh_state_export_stage=0

#####
# .travis.yml parse result
gh_parse() {
  gh_close_export
  printf '::group::\e[90m[info]\e[0m parse+validate: \e[34m%s\e[0m ' "$TRAVIS_YAML_FILE"
  "$GITHUB_ACTION_PATH"/lib/travis-parse.php \
      --file "$TRAVIS_YAML_FILE" \
      ;
}

#####
# .travis.yml plan of jobs result
gh_plan() {
  gh_close_export
  printf '::group::\e[90m[info]\e[0m plan: \e[34m%s\e[0m\n' "$TRAVIS_YAML_FILE"
  "$GITHUB_ACTION_PATH"/lib/travis-plan.php \
      --file "$TRAVIS_YAML_FILE" \
      --run-job "${run_job-}" \
      ;
}

#####
# travis environment export
gh_export() {
  if (( gh_state_export_count == 0 )); then
    if (( gh_state_export_stage == 0 )); then
      printf '::group::\e[90m[info]\e[0m env: \e[34m%s\e[0m\n' "$TRAVIS_YAML_FILE"
    else
      printf '::group::\e[90m[info]\e[0m env: \e[34m%s\e[0m (post)\n' "$TRAVIS_YAML_FILE"
    fi
    (( ++gh_state_export_stage ))
  fi
  (( ++gh_state_export_count ))

  if [[ -z ${!1+x} ]]; then
    printf '  \e[90m%s\e[0m\n' "$1"
  else
    if [[ "$1" = "TRAVIS_COMMIT_MESSAGE" ]]; then
      printf '  %s: %s\n' "$1" "$(echo "${!1}" | tr "\n\r" ".." | head -c 47)..." # beams subject line 50 chars recommendation
    else
      printf '  %s: %s\n' "$1" "${!1}"
    fi
  fi

  # shellcheck disable=SC2163
  export "${1:?}";

  if (( gh_state_export_stage == 2 )); then
    printf '%s=%s\n' "$1" "${!1}" >> "$GITHUB_ENV";
  fi
}

#####
# define environment variable with defaults and input binding
# 1: variable name
# 2: default value
# 3: input binding
gh_var() {
  local val
  val=${!1:-"${2:-}"}
  if [[ -n "${3:-}" ]]; then
    val="${!3:-"$val"}"
  fi
  eval "$1"='$val'
  # shellcheck disable=SC2163
  export -- "$1"
}

####
# compose environment table from environment variables
gh_env() {
  for i in $1; do
    gh_export "$i" ""
  done
}

#####
# close export channel
gh_close_export() {
  printf '::endgroup::\n'
  export gh_state_export_count=0
}

####
# format true / false from mixed leaning towards "$2-false" if
# neither true or false
gh_fmt_bool_def() {
  if [[ "$1" == "true" ]]; then
    printf 'true';
  elif [[ "$1" == "false" ]]; then
    printf 'false';
  else
    printf '%s' "${2-false}";
  fi
}

####
# format success / failure from build result status
gh_fmt_build_result() {
  if [[ $1 -eq 0 ]]; then printf 'success'; else printf 'failure'; fi
}

#####
# build build.sh file
gh_build_run() {
  gh_close_export

  if [[ "${dry_run_job-}" == "true" ]]; then
    set -- --dry-run
  fi

  # write build.sh
  if ! "$GITHUB_ACTION_PATH/lib/travis-script-builder.php" \
      --file "$TRAVIS_YAML_FILE" \
      --run-job "${run_job:-}" \
      "$@" \
      "${travis_steps:-}" \
      > "$GITHUB_ACTION_PATH/build.sh";
  then
    exit 1
  fi
  # execute build.sh (error fence)
  set +e
    /bin/bash "$GITHUB_ACTION_PATH/build.sh"
    export gh_build_result=$?
  set -e
  export TRAVIS_TEST_RESULT=$gh_build_result
  # action output
  printf '%s=%s\n' "exit-status" "$gh_build_result" \
    >> "$GITHUB_OUTPUT"
  printf '%s=%s\n' "outcome" "$(gh_fmt_build_result "$gh_build_result")" \
    >> "$GITHUB_OUTPUT"
}

#####
# deal allow failure / TRAVIS_ALLOW_FAILURE
gh_allow_failure() {
  if [[ $gh_build_result -ne 0 ]] && [[ "$TRAVIS_ALLOW_FAILURE" = "true" ]]; then
    printf '\e[33mTRAVIS_ALLOW_FAILURE\e[34m for build exit status \e[0m%s\n' "$gh_build_result"
    export gh_build_result=0 # silent
  fi
  # action output
  printf '%s=%s\n' "conclusion" "$(gh_fmt_build_result "$gh_build_result")" \
    >> "$GITHUB_OUTPUT"
}

#####
# build terminator
gh_terminate() {
  gh_close_export
  exit $gh_build_result
}
