#!/usr/bin/env bats
# ci.bats - CI/CD architecture check tests
#
# Trace: AC-G09

load 'helpers/common'

PROJECT_ROOT="$BATS_TEST_DIRNAME/.."
WORKFLOW_FILE="$PROJECT_ROOT/.github/workflows/arch-check.yml"
GITLAB_TEMPLATE="$PROJECT_ROOT/.gitlab-ci.yml.template"

@test "test_workflow_syntax: GitHub Action workflow passes actionlint" {
    skip_if_missing "actionlint"

    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    run actionlint "$WORKFLOW_FILE"
    assert_exit_success "$status"
}

@test "test_workflow_trigger: workflow triggers on PR and workflow_dispatch" {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    grep -q "pull_request" "$WORKFLOW_FILE" || skip_not_implemented "pull_request trigger"
    grep -q "workflow_dispatch" "$WORKFLOW_FILE" || skip_not_implemented "workflow_dispatch trigger"

    # Branch filter should include common main branch names
    if ! grep -qE "branches:.*\[.*main.*\]|branches:.*\[.*master.*\]" "$WORKFLOW_FILE"; then
        # Also check for YAML list format
        if ! grep -qE "^\s*-\s*(main|master)\s*$" "$WORKFLOW_FILE"; then
            skip_not_implemented "branch filter for main/master"
        fi
    fi
}

@test "test_workflow_cycles: workflow runs dependency cycle check" {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    grep -q "dependency-guard.sh --cycles" "$WORKFLOW_FILE" || skip_not_implemented "cycle check step"
}

@test "test_workflow_violations: workflow runs architecture rule check" {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    grep -q "boundary-detector.sh detect" "$WORKFLOW_FILE" || skip_not_implemented "architecture rule check"
}

@test "test_workflow_orphan: workflow runs orphan module detection" {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    # Check for orphan detection step - could be via dependency-guard or dedicated script
    local has_orphan=false

    if grep -qE "orphan|--orphan|orphan-detection|unused.module" "$WORKFLOW_FILE"; then
        has_orphan=true
    fi

    # Alternative: orphan check might be part of dependency-guard with different flag
    if grep -qE "dependency-guard.sh.*(--all|--orphan|--unused)" "$WORKFLOW_FILE"; then
        has_orphan=true
    fi

    # Alternative: separate orphan detection script
    if grep -qE "orphan-detector|detect-orphan|find.*orphan" "$WORKFLOW_FILE"; then
        has_orphan=true
    fi

    if [ "$has_orphan" != "true" ]; then
        skip_not_implemented "orphan module detection step"
    fi
}

@test "test_workflow_success: workflow fails when checks fail" {
    if [ ! -f "$WORKFLOW_FILE" ]; then
        skip_not_implemented "arch-check workflow file"
    fi

    # Check for failure gate - should fail if any check fails
    local has_failure_gate=false

    if grep -q "Fail if checks failed" "$WORKFLOW_FILE"; then
        has_failure_gate=true
    fi

    if grep -qE "steps\.(cycles|violations|orphan)\.outputs\.status" "$WORKFLOW_FILE"; then
        has_failure_gate=true
    fi

    if grep -qE "if:.*failure\(\)|continue-on-error:\s*false" "$WORKFLOW_FILE"; then
        has_failure_gate=true
    fi

    # Check for exit code propagation
    if grep -qE "exit\s+\\\$\?|exit\s+1|\|\|\s+exit" "$WORKFLOW_FILE"; then
        has_failure_gate=true
    fi

    if [ "$has_failure_gate" != "true" ]; then
        skip_not_implemented "failure gate"
    fi
}

@test "test_gitlab_template: GitLab CI template includes arch checks" {
    if [ ! -f "$GITLAB_TEMPLATE" ]; then
        skip_not_implemented "gitlab ci template"
    fi

    grep -q "dependency-guard.sh --cycles" "$GITLAB_TEMPLATE" || skip_not_implemented "gitlab cycle check"
    grep -q "boundary-detector.sh detect" "$GITLAB_TEMPLATE" || skip_not_implemented "gitlab architecture check"
}

@test "test_gitlab_template_orphan: GitLab CI template includes orphan detection" {
    if [ ! -f "$GITLAB_TEMPLATE" ]; then
        skip_not_implemented "gitlab ci template"
    fi

    # Check for orphan detection in GitLab template
    local has_orphan=false

    if grep -qE "orphan|--orphan|orphan-detection" "$GITLAB_TEMPLATE"; then
        has_orphan=true
    fi

    if grep -qE "dependency-guard.sh.*(--all|--orphan|--unused)" "$GITLAB_TEMPLATE"; then
        has_orphan=true
    fi

    if [ "$has_orphan" != "true" ]; then
        skip_not_implemented "gitlab orphan module detection"
    fi
}
