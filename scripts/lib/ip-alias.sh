#!/usr/bin/env bash
# IP alias management — assigns dedicated LAN IPs to apps via WiFi interface
# Requires common.sh to be sourced first (for IP_ALIAS_* settings)

# Calculate IP from slot number: slot 1 → base IP, slot 2 → base+1, etc.
slot_to_ip() {
    local slot="$1"
    local base_octets
    IFS='.' read -r o1 o2 o3 o4 <<< "$IP_ALIAS_BASE"
    local ip_last=$(( o4 + slot - 1 ))
    if (( ip_last > 254 )); then
        error "IP alias overflow: slot ${slot} would give .${ip_last}"
        return 1
    fi
    echo "${o1}.${o2}.${o3}.${ip_last}"
}

# Add an IP alias to the WiFi interface (persistent via NetworkManager)
add_ip_alias() {
    local ip="$1"
    local mask="${IP_ALIAS_NETMASK:-24}"

    # Check if already assigned
    if ip addr show "${IP_ALIAS_INTERFACE}" 2>/dev/null | grep -q "inet ${ip}/"; then
        info "IP ${ip} already assigned to ${IP_ALIAS_INTERFACE}"
        return 0
    fi

    # Add to NetworkManager connection (persistent across reboots)
    nmcli connection modify "${WIFI_CONNECTION}" +ipv4.addresses "${ip}/${mask}" 2>/dev/null || {
        error "Failed to add ${ip} to NetworkManager connection"
        return 1
    }

    # Apply immediately
    nmcli connection up "${WIFI_CONNECTION}" 2>/dev/null || {
        error "Failed to reactivate connection after adding ${ip}"
        return 1
    }

    # Verify
    if ip addr show "${IP_ALIAS_INTERFACE}" 2>/dev/null | grep -q "inet ${ip}/"; then
        success "IP alias ${ip} added to ${IP_ALIAS_INTERFACE}"
    else
        error "IP ${ip} not found on ${IP_ALIAS_INTERFACE} after applying"
        return 1
    fi
}

# Remove an IP alias from the WiFi interface
remove_ip_alias() {
    local ip="$1"
    local mask="${IP_ALIAS_NETMASK:-24}"

    # Remove from NetworkManager connection
    nmcli connection modify "${WIFI_CONNECTION}" -ipv4.addresses "${ip}/${mask}" 2>/dev/null || {
        warn "Failed to remove ${ip} from NetworkManager connection"
        return 1
    }

    # Apply
    nmcli connection up "${WIFI_CONNECTION}" 2>/dev/null || true

    info "IP alias ${ip} removed from ${IP_ALIAS_INTERFACE}"
}

# Create NPM proxy host for an IP address → container
create_ip_proxy() {
    local ip="$1"
    local forward_host="$2"
    local forward_port="${3:-80}"

    local host_id
    host_id=$(npm_create_proxy "$ip" "$forward_host" "$forward_port") || return 1
    echo "$host_id"
}
