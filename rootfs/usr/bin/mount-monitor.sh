#!/usr/bin/with-contenv bashio

set -e

source /usr/bin/mount-helper.sh

STATE_DIR="/data/mount_state"
EVENT_PIPE="/tmp/network_events"
NETWORK_MONITOR_PID=""

initialize_state_dir() {
    local share_name="$1"
    local share_state_dir="${STATE_DIR}/${share_name}"

    mkdir -p "$share_state_dir"

    if [ ! -f "${share_state_dir}/status" ]; then
        echo "MOUNTED" > "${share_state_dir}/status"
    fi

    if [ ! -f "${share_state_dir}/retry_count" ]; then
        echo "0" > "${share_state_dir}/retry_count"
    fi

    if [ ! -f "${share_state_dir}/last_check" ]; then
        date +%s > "${share_state_dir}/last_check"
    fi

    if [ ! -f "${share_state_dir}/last_success" ]; then
        date +%s > "${share_state_dir}/last_success"
    fi
}

get_state() {
    local share_name="$1"
    local field="$2"
    local state_file="${STATE_DIR}/${share_name}/${field}"

    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo ""
    fi
}

set_state() {
    local share_name="$1"
    local field="$2"
    local value="$3"
    local state_file="${STATE_DIR}/${share_name}/${field}"

    echo "$value" > "$state_file"
}

send_notification() {
    local title="$1"
    local message="$2"

    if ! bashio::config.true 'reconnect_notify_ha' 'true'; then
        return 0
    fi

    send_error_notification "$title" "$message"
}

start_network_event_monitor() {
    if ! bashio::config.true 'reconnect_use_events' 'true'; then
        bashio::log.info "Network event monitoring is disabled"
        return 0
    fi

    if ! command -v inotifywait >/dev/null 2>&1; then
        bashio::log.warning "inotifywait not available, network event monitoring disabled"
        return 0
    fi

    mkfifo "$EVENT_PIPE" 2>/dev/null || true

    bashio::log.info "Starting network event monitor..."

    (
        while true; do
            if inotifywait -e modify,create /proc/net/route >/dev/null 2>&1; then
                echo "NETWORK_EVENT" > "$EVENT_PIPE" 2>/dev/null || true
            fi
            sleep 1
        done
    ) &

    NETWORK_MONITOR_PID=$!
    bashio::log.info "Network event monitor started (PID: ${NETWORK_MONITOR_PID})"
}

check_and_reconnect_mount() {
    local share_name="$1"
    local host="$2"
    local port="$3"
    local user="$4"
    local path="$5"
    local auth_type="$6"
    local ssh_key="$7"
    local ssh_password="$8"

    local mount_dir="/mnt/${share_name}"
    local status
    status=$(get_state "$share_name" "status")
    local retry_count
    retry_count=$(get_state "$share_name" "retry_count")

    set_state "$share_name" "last_check" "$(date +%s)"

    if check_mount_health "$mount_dir"; then
        if [ "$status" != "MOUNTED" ]; then
            bashio::log.info "[${share_name}] Mount recovered!"
            send_notification \
                "SSHFS Mount - Recovered" \
                "Mount '${share_name}' has been successfully reconnected to ${user}@${host}:${path}"
        fi

        set_state "$share_name" "status" "MOUNTED"
        set_state "$share_name" "retry_count" "0"
        set_state "$share_name" "last_success" "$(date +%s)"
        return 0
    fi

    if [ "$status" = "MOUNTED" ]; then
        bashio::log.warning "[${share_name}] Mount health check failed, starting reconnection..."
        send_notification \
            "SSHFS Mount - Connection Lost" \
            "Mount '${share_name}' (${user}@${host}:${path}) has disconnected. Attempting automatic reconnection..."
        set_state "$share_name" "status" "FAILED"
        set_state "$share_name" "retry_count" "0"
        set_state "$share_name" "last_failure" "$(date +%s)"
    fi

    local base_delay
    base_delay=$(bashio::config 'reconnect_base_delay' '5')
    local max_delay
    max_delay=$(bashio::config 'reconnect_max_delay' '3600')

    local delay
    delay=$(calculate_backoff_delay "$retry_count" "$base_delay" "$max_delay")

    local last_attempt
    last_attempt=$(get_state "$share_name" "last_attempt" || echo "0")
    local now
    now=$(date +%s)
    local time_since_attempt=$((now - last_attempt))

    if [ "$last_attempt" != "0" ] && [ $time_since_attempt -lt $delay ]; then
        return 0
    fi

    set_state "$share_name" "status" "RECONNECTING"
    set_state "$share_name" "last_attempt" "$now"

    bashio::log.info "[${share_name}] Reconnection attempt $((retry_count + 1)) (delay: ${delay}s)..."

    unmount_share "$mount_dir"

    if mount_share "$share_name" "$host" "$port" "$user" "$path" "$auth_type" "$ssh_key" "$ssh_password" 2>&1 | tee /tmp/mount_error_${share_name}.log; then
        bashio::log.info "[${share_name}] Reconnection successful!"
        send_notification \
            "SSHFS Mount - Reconnected" \
            "Mount '${share_name}' has been successfully reconnected to ${user}@${host}:${path}"

        set_state "$share_name" "status" "MOUNTED"
        set_state "$share_name" "retry_count" "0"
        set_state "$share_name" "last_success" "$now"
        rm -f /tmp/mount_error_${share_name}.log
        return 0
    else
        local error_output=""
        if [ -f /tmp/mount_error_${share_name}.log ]; then
            error_output=$(cat /tmp/mount_error_${share_name}.log)
            rm -f /tmp/mount_error_${share_name}.log
        fi

        if echo "$error_output" | grep -qi "permission denied\|authentication failed\|publickey"; then
            bashio::log.error "[${share_name}] Authentication failure detected - not retrying"
            send_notification \
                "SSHFS Mount - Authentication Error" \
                "Mount '${share_name}' failed due to authentication error. Please check your credentials in the configuration."
            set_state "$share_name" "status" "AUTH_FAILED"
            return 1
        fi

        bashio::log.warning "[${share_name}] Reconnection attempt failed"
        set_state "$share_name" "status" "FAILED"
        set_state "$share_name" "retry_count" "$((retry_count + 1))"
        set_state "$share_name" "last_failure" "$now"

        local next_delay
        next_delay=$(calculate_backoff_delay "$((retry_count + 1))" "$base_delay" "$max_delay")
        bashio::log.info "[${share_name}] Next attempt in ${next_delay} seconds"

        return 1
    fi
}

main() {
    bashio::log.info "Starting SSHFS Mount Monitor Service..."

    if ! bashio::config.true 'reconnect_enabled' 'true'; then
        bashio::log.info "Mount reconnection monitoring is disabled"
        exec sleep infinity
    fi

    if ! load_mount_config; then
        bashio::log.error "Failed to load mount configuration"
        exec sleep infinity
    fi

    mkdir -p "$STATE_DIR"

    for i in "${!MOUNTPOINT_SHARE_NAMES[@]}"; do
        share_name="${MOUNTPOINT_SHARE_NAMES[$i]}"
        initialize_state_dir "$share_name"
    done

    start_network_event_monitor

    local check_interval
    check_interval=$(bashio::config 'reconnect_check_interval' '60')

    bashio::log.info "Monitor configuration:"
    bashio::log.info "  - Check interval: ${check_interval}s"
    bashio::log.info "  - Network events: $(bashio::config 'reconnect_use_events' 'true')"
    bashio::log.info "  - HA notifications: $(bashio::config 'reconnect_notify_ha' 'true')"
    bashio::log.info "Monitoring ${MOUNTPOINT_COUNT} mount(s) for health and reconnection..."

    local last_check=0

    while true; do
        local now
        now=$(date +%s)
        local check_triggered=false

        if [ -p "$EVENT_PIPE" ]; then
            if read -t 0 event < "$EVENT_PIPE" 2>/dev/null; then
                bashio::log.debug "Network event detected, triggering health check..."
                check_triggered=true
                last_check=0
            fi
        fi

        if [ $((now - last_check)) -ge $check_interval ] || [ "$check_triggered" = true ]; then
            for i in "${!MOUNTPOINT_SHARE_NAMES[@]}"; do
                share_name="${MOUNTPOINT_SHARE_NAMES[$i]}"
                host="${MOUNTPOINT_HOSTS[$i]}"
                port="${MOUNTPOINT_PORTS[$i]}"
                user="${MOUNTPOINT_USERS[$i]}"
                path="${MOUNTPOINT_PATHS[$i]}"
                auth_type="${MOUNTPOINT_AUTH_TYPES[$i]}"
                ssh_key="${MOUNTPOINT_SSH_KEYS[$i]}"
                ssh_password="${MOUNTPOINT_SSH_PASSWORDS[$i]}"

                local status
                status=$(get_state "$share_name" "status")

                if [ "$status" = "AUTH_FAILED" ]; then
                    continue
                fi

                check_and_reconnect_mount "$share_name" "$host" "$port" "$user" "$path" "$auth_type" "$ssh_key" "$ssh_password" || true
            done

            last_check=$now
        fi

        sleep 5
    done
}

trap '[ -n "$NETWORK_MONITOR_PID" ] && kill $NETWORK_MONITOR_PID 2>/dev/null || true; rm -f $EVENT_PIPE' EXIT

main
