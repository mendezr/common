#!/usr/bin/env bats

setup() {
    export TEST_TMPDIR="$(mktemp -d)"
    export STATE_DIRECTORY="${TEST_TMPDIR}/state"
    export IMAGE_INFO_FILE="${TEST_TMPDIR}/image-info.json"
    export BOOTED_IMAGE_FILE="${TEST_TMPDIR}/booted-image"
    export WAYLAND_SESSIONS_DIR="${TEST_TMPDIR}/wayland-sessions"
    export MOCK_BIN="${TEST_TMPDIR}/bin"
    mkdir -p "${STATE_DIRECTORY}" "${MOCK_BIN}" "${WAYLAND_SESSIONS_DIR}"
    # Mock curl to inspect executed URL
    cat << 'EOF' > "${MOCK_BIN}/curl"
#!/usr/bin/env bash
echo "$@" >> "${STATE_DIRECTORY}/curl_calls.log"
exit 0
EOF
    chmod +x "${MOCK_BIN}/curl"

    export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

@test "bluefin-countme generates epoch and sends countme=1 on first run for dakota" {
    cat << 'EOF' > "${IMAGE_INFO_FILE}"
{
  "image-name": "dakota",
  "image-flavor": "main",
  "image-tag": "stable"
}
EOF

    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]

    [ -f "${STATE_DIRECTORY}/epoch" ]
    [ -f "${STATE_DIRECTORY}/lastrun" ]

    run cat "${STATE_DIRECTORY}/curl_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "repo=dakota" ]]
    [[ "$output" =~ "tag=stable" ]]
    [[ "$output" =~ "flavor=main" ]]
    [[ "$output" =~ "gamemode=0" ]]
    [[ "$output" =~ "countme=1" ]]
}

@test "bluefin-countme detects testing tag and gaming mode" {
    cat << 'EOF' > "${IMAGE_INFO_FILE}"
{
  "image-name": "dakota-gaming",
  "image-flavor": "gaming",
  "image-tag": "testing"
}
EOF

    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]

    run cat "${STATE_DIRECTORY}/curl_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "repo=dakota" ]]
    [[ "$output" =~ "tag=testing" ]]
    [[ "$output" =~ "flavor=gaming" ]]
    [[ "$output" =~ "gamemode=1" ]]
}

@test "bluefin-countme throttles execution within 7 days" {
    cat << 'EOF' > "${IMAGE_INFO_FILE}"
{
  "image-name": "dakota",
  "image-flavor": "main",
  "image-tag": "stable"
}
EOF

    # First run
    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]
    [ -f "${STATE_DIRECTORY}/curl_calls.log" ]
    calls_1=$(wc -l < "${STATE_DIRECTORY}/curl_calls.log")

    # Immediate second run (within 7 days)
    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]
    calls_2=$(wc -l < "${STATE_DIRECTORY}/curl_calls.log")

    [ "$calls_1" -eq "$calls_2" ]
}

@test "bluefin-countme calculates bucket based on epoch age" {
    cat << 'EOF' > "${IMAGE_INFO_FILE}"
{
  "image-name": "dakota",
  "image-flavor": "main",
  "image-tag": "stable"
}
EOF
    # Set epoch to 3 weeks ago (bucket 2)
    now=$(date +%s)
    three_weeks_ago=$(( now - (3 * 7 * 86400) ))
    echo "$three_weeks_ago" > "${STATE_DIRECTORY}/epoch"

    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]

    run cat "${STATE_DIRECTORY}/curl_calls.log"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "countme=2" ]]
}

@test "bluefin-countme exits 0 without calling countme endpoint on non-dakota images" {
    cat << 'EOF' > "${IMAGE_INFO_FILE}"
{
  "image-name": "bluefin-lts",
  "image-flavor": "main",
  "image-tag": "stable"
}
EOF

    run bash system_files/shared/usr/libexec/bluefin-countme
    [ "$status" -eq 0 ]
    [ ! -f "${STATE_DIRECTORY}/curl_calls.log" ]
}
