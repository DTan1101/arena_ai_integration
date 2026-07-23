#!/bin/bash

arena_ai_source_workspace() {
    export WORKSPACE_DIR="${WORKSPACE_DIR:-${ARENA_WS_DIR:-/opt/arena_ws}}"
    export ARENA_WS_DIR="$WORKSPACE_DIR"
    export ARENA_DIR="${ARENA_DIR:-$WORKSPACE_DIR/src/Arena}"

    local source_file="$WORKSPACE_DIR/source"
    if [ ! -f "$source_file" ]; then
        source_file="$ARENA_DIR/_meta/tools/source"
    fi

    if [ ! -f "$source_file" ]; then
        echo "[ERROR] Arena source file not found: $source_file"
        return 1
    fi

    local had_nounset=0
    case "$-" in
        *u*) had_nounset=1 ;;
    esac

    set +u
    pushd "$WORKSPACE_DIR" >/dev/null || return 1
    # shellcheck disable=SC1090
    source "$source_file"
    if [ -f "install/setup.bash" ]; then
        # shellcheck disable=SC1090
        source "install/setup.bash"
    fi
    popd >/dev/null || return 1
    if [ "$had_nounset" -eq 1 ]; then
        set -u
    else
        set +u
    fi
}

arena_ai_materialize_installed_file() {
    local file="$1"

    if [ ! -L "$file" ]; then
        return 0
    fi

    local tmp_file="$file.arena_ai.tmp"
    cp -L "$file" "$tmp_file" || return 1
    rm "$file" || return 1
    mv "$tmp_file" "$file" || return 1
}

arena_ai_remove_turtlebot_wheel_control_blocks() {
    local search_root="$1"
    local label="$2"
    local patched_var="$3"
    local file
    local changed=0

    if [ ! -d "$search_root" ]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        if grep -Eq '<ros2_control[^>]+name=["'"'"'](left|right)_wheel_controller[^"'"'"']*["'"'"']' "$file"; then
            echo "[INFO] Removing duplicate turtlebot wheel ros2_control blocks from $label: $file"
            cp -n "$file" "$file.arena_ai.bak" 2>/dev/null || true
            if ! arena_ai_materialize_installed_file "$file"; then
                echo "[ERROR] Could not materialize installed description symlink: $file"
                return 1
            fi
            if perl -0pi \
                -e "s#\n\s*<ros2_control\b[^>]*name=[\"']left_wheel_controller[^\"']*[\"'][^>]*>.*?</ros2_control>##gs" \
                "$file" 2>/dev/null && \
                perl -0pi \
                -e "s#\n\s*<ros2_control\b[^>]*name=[\"']right_wheel_controller[^\"']*[\"'][^>]*>.*?</ros2_control>##gs" \
                "$file" 2>/dev/null; then
                changed=1
            else
                echo "[ERROR] Could not patch duplicate turtlebot wheel ros2_control blocks in: $file"
                echo "[ERROR] Run the benchmark from a writable overlay/container, or patch this file with sudo."
                return 1
            fi
        fi
    done < <(
        find "$search_root" -type f \
            \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
            ! -name '*.arena_ai.bak' -print0
    )

    if [ "$changed" -eq 1 ]; then
        printf -v "$patched_var" 1
    fi
}

arena_ai_remove_turtlebot_templated_wheel_control_blocks() {
    local search_root="$1"
    local label="$2"
    local patched_var="$3"
    local file
    local changed=0

    if [ ! -d "$search_root" ]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        if grep -q '<ros2_control name="${wheel_link_name}_controller"' "$file"; then
            echo "[INFO] Removing templated turtlebot wheel ros2_control blocks from $label: $file"
            cp -n "$file" "$file.arena_ai.bak" 2>/dev/null || true
            if ! arena_ai_materialize_installed_file "$file"; then
                echo "[ERROR] Could not materialize installed description symlink: $file"
                return 1
            fi
            if perl -0pi \
                -e 's#\n\s*<xacro:if\b[^>]*>\s*<ros2_control\b[^>]*name="\$\{wheel_link_name\}_controller"[^>]*>.*?</ros2_control>\s*</xacro:if>##gs' \
                "$file" 2>/dev/null; then
                changed=1
            else
                echo "[ERROR] Could not patch templated turtlebot wheel ros2_control blocks in: $file"
                return 1
            fi
        fi
    done < <(
        find "$search_root" -type f \
            \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
            ! -name '*.arena_ai.bak' -print0
    )

    if [ "$changed" -eq 1 ]; then
        printf -v "$patched_var" 1
    fi
}

arena_ai_remove_legacy_gazebo_ros2_control_plugins() {
    local search_root="$1"
    local label="$2"
    local patched_var="$3"
    local file
    local changed=0

    if [ ! -d "$search_root" ]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        if grep -Eq 'libgazebo_ros2_control\.so|gazebo_ros2_control/GazeboSystem' "$file"; then
            echo "[INFO] Removing legacy gazebo ros2_control plugin blocks from $label: $file"
            cp -n "$file" "$file.arena_ai.bak" 2>/dev/null || true
            if ! arena_ai_materialize_installed_file "$file"; then
                echo "[ERROR] Could not materialize installed description symlink: $file"
                return 1
            fi
            if perl -0pi \
                -e "s#\n\s*<gazebo(?:\s+[^>]*)?>\s*<plugin\b(?=[^>]*(?:filename=[\"']libgazebo_ros2_control\.so[\"']|name=[\"']gazebo_ros2_control[\"']))[^>]*>.*?</plugin>\s*</gazebo>##gs" \
                "$file" 2>/dev/null && \
                sed -i 's#gazebo_ros2_control/GazeboSystem#gz_ros2_control/GazeboSimSystem#g' "$file" 2>/dev/null; then
                changed=1
            else
                echo "[ERROR] Could not remove legacy gazebo ros2_control plugin block in: $file"
                return 1
            fi
        fi
    done < <(
        find "$search_root" -type f \
            \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
            ! -name '*.arena_ai.bak' -print0
    )

    if [ "$changed" -eq 1 ]; then
        printf -v "$patched_var" 1
    fi
}

arena_ai_assert_turtlebot_control_sources_clean() {
    local file
    local root
    local found=0

    for root in "$@"; do
        if [ ! -d "$root" ]; then
            continue
        fi
        while IFS= read -r -d '' file; do
            if grep -Eq 'left_wheel_controller|right_wheel_controller|\$\{wheel_link_name\}_controller|libgazebo_ros2_control\.so|gazebo_ros2_control/GazeboSystem' "$file"; then
                if [ "$found" -eq 0 ]; then
                    echo "[ERROR] Turtlebot Isaac preflight still found control sources that can regenerate duplicate wheel hardware:"
                fi
                grep -HnE 'left_wheel_controller|right_wheel_controller|\$\{wheel_link_name\}_controller|libgazebo_ros2_control\.so|gazebo_ros2_control/GazeboSystem' "$file" 2>/dev/null | grep -v '\.arena_ai\.bak' || true
                found=1
            fi
        done < <(
            find "$root" -type f \
                \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
                ! -name '*.arena_ai.bak' -print0
        )
    done

    if [ "$found" -eq 1 ]; then
        echo "[ERROR] These leftover entries match the runner.log duplicate ResourceStorage wheel-interface failure."
        echo "[ERROR] Patch/remove the listed entries or run from a container layer where these files are writable."
        return 1
    fi

    return 0
}

arena_ai_dependency_needs_control_patch() {
    local search_root="$1"
    local file

    if [ ! -d "$search_root" ]; then
        return 1
    fi

    while IFS= read -r -d '' file; do
        if grep -Eq 'left_wheel_controller|right_wheel_controller|\$\{wheel_link_name\}_controller|libgazebo_ros2_control\.so|gazebo_ros2_control/GazeboSystem' "$file"; then
            return 0
        fi
    done < <(
        find "$search_root" -type f \
            \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
            ! -name '*.arena_ai.bak' -print0
    )

    return 1
}

arena_ai_overlay_dependency_package() {
    local dep_pkg="$1"
    local source_share="$2"
    local dep_prefix_var="$3"
    local dep_share_var="$4"
    local patched_var="$5"

    if [ ! -d "$source_share" ]; then
        return 0
    fi

    local overlay_root="${ARENA_AI_DESCRIPTION_OVERLAY_ROOT:-$WORKSPACE_DIR/data/benchmarks/arena_ai_description_overlays}"
    local overlay_prefix="$overlay_root/$dep_pkg"
    local overlay_share="$overlay_prefix/share/$dep_pkg"
    local marker_dir="$overlay_prefix/share/ament_index/resource_index/packages"
    local source_resolved
    local overlay_resolved

    mkdir -p "$overlay_share" "$marker_dir" || return 1
    source_resolved="$(readlink -f "$source_share" 2>/dev/null || printf '%s' "$source_share")"
    overlay_resolved="$(readlink -f "$overlay_share" 2>/dev/null || printf '%s' "$overlay_share")"
    if [ "$source_resolved" != "$overlay_resolved" ]; then
        cp -a "$source_share/." "$overlay_share/" || return 1
    fi
    : >"$marker_dir/$dep_pkg" || return 1

    case ":${AMENT_PREFIX_PATH:-}:" in
        *":$overlay_prefix:"*) ;;
        *)
            export AMENT_PREFIX_PATH="$overlay_prefix${AMENT_PREFIX_PATH:+:$AMENT_PREFIX_PATH}"
            ;;
    esac
    case ":${CMAKE_PREFIX_PATH:-}:" in
        *":$overlay_prefix:"*) ;;
        *)
            export CMAKE_PREFIX_PATH="$overlay_prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
            ;;
    esac

    echo "[INFO] Using writable Arena AI description overlay for $dep_pkg: $overlay_share"
    printf -v "$dep_prefix_var" '%s' "$overlay_prefix"
    printf -v "$dep_share_var" '%s' "$overlay_share"
    printf -v "$patched_var" 1
}

arena_ai_disable_turtlebot_create3_gazebo_controls() {
    local robot_share="$1"
    local patched_var="$2"
    local xacro_file="$robot_share/urdf/turtlebot.urdf.xacro"

    if [ ! -f "$xacro_file" ]; then
        return 0
    fi

    if ! grep -q 'create3\.urdf\.xacro' "$xacro_file"; then
        return 0
    fi

    if ! grep -q 'name="gazebo" value="ignition"' "$xacro_file"; then
        return 0
    fi

    echo "[INFO] Disabling Create3 embedded gazebo ros2_control for Isaac bridge: $xacro_file"
    cp -n "$xacro_file" "$xacro_file.arena_ai.bak" 2>/dev/null || true
    if ! arena_ai_materialize_installed_file "$xacro_file"; then
        echo "[ERROR] Could not materialize installed turtlebot xacro symlink: $xacro_file"
        return 1
    fi

    if sed -i 's#name="gazebo" value="ignition"#name="gazebo" value="false"#g' "$xacro_file" 2>/dev/null; then
        printf -v "$patched_var" 1
    else
        echo "[ERROR] Could not patch Create3 gazebo arg in: $xacro_file"
        return 1
    fi
}

arena_ai_validate_turtlebot_generated_control() {
    local robot_share="$1"
    local xacro_file="$robot_share/urdf/turtlebot.urdf.xacro"
    local generated_file
    local xacro_log
    local generated_count

    if [ ! -f "$xacro_file" ] || ! command -v xacro >/dev/null 2>&1; then
        return 0
    fi

    generated_file="$(mktemp "${TMPDIR:-/tmp}/arena_ai_turtlebot_urdf.XXXXXX")" || return 1
    xacro_log="$(mktemp "${TMPDIR:-/tmp}/arena_ai_turtlebot_xacro.XXXXXX.log")" || {
        rm -f "$generated_file"
        return 1
    }
    if ! xacro "$xacro_file" >"$generated_file" 2>"$xacro_log"; then
        rm -f "$generated_file"
        echo "[WARN] Could not validate turtlebot xacro output; continuing with installed URDF checks."
        sed -n '1,20p' "$xacro_log" 2>/dev/null | sed 's/^/[WARN] xacro: /' || true
        rm -f "$xacro_log"
        return 0
    fi
    rm -f "$xacro_log"

    generated_count="$(grep -c '<ros2_control ' "$generated_file" 2>/dev/null || echo 0)"
    if [ "$generated_count" -gt 1 ]; then
        echo "[ERROR] Turtlebot xacro still generates $generated_count ros2_control blocks after Isaac preflight."
        echo "[ERROR] Runtime URDF regeneration will reintroduce duplicate wheel hardware."
        grep -n '<ros2_control ' "$generated_file" 2>/dev/null || true
        rm -f "$generated_file"
        return 1
    fi

    rm -f "$generated_file"
}

arena_ai_patch_turtlebot_diff_drive_frames() {
    local robot_share="$1"
    local patched_var="$2"
    local control_file="$robot_share/control.yaml"
    local cmd_vel_timeout="${ARENA_AI_TURTLEBOT_CMD_VEL_TIMEOUT:-2.0}"
    local open_loop="${ARENA_AI_TURTLEBOT_OPEN_LOOP:-true}"
    local needs_patch=0

    if [ ! -f "$control_file" ]; then
        return 0
    fi

    # arena_runtime already prefixes bare odom/base frame ids with the Isaac
    # robot frame prefix (for example env_0/turtlebot/odom). Jazzy's
    # diff_drive_controller then prefixes again with the node namespace unless
    # tf_frame_prefix_enable is disabled, yielding frames such as
    # arena/env_0/task_generator_node/turtlebot/env_0/turtlebot/odom.
    if ! grep -Eq '^\s*tf_frame_prefix_enable:\s*false\s*$' "$control_file"; then
        needs_patch=1
    fi
    if ! grep -Eq "^\s*cmd_vel_timeout:\s*$cmd_vel_timeout\s*$" "$control_file"; then
        needs_patch=1
    fi
    if ! grep -Eq "^\s*open_loop:\s*$open_loop\s*$" "$control_file"; then
        needs_patch=1
    fi
    if [ "$needs_patch" -eq 0 ]; then
        return 0
    fi

    echo "[INFO] Patching turtlebot diff_drive_controller for Isaac/Jazzy: $control_file"
    echo "[INFO]   - disable TF auto-prefix"
    echo "[INFO]   - set cmd_vel_timeout=$cmd_vel_timeout"
    echo "[INFO]   - set open_loop=$open_loop"
    cp -n "$control_file" "$control_file.arena_ai.bak" 2>/dev/null || true
    if ! arena_ai_materialize_installed_file "$control_file"; then
        echo "[ERROR] Could not materialize installed turtlebot control file: $control_file"
        return 1
    fi

    if grep -q 'tf_frame_prefix_enable:' "$control_file"; then
        if perl -0pi \
            -e 's/^(\s*tf_frame_prefix_enable:\s*).*$/${1}false/m; s/^(\s*tf_frame_prefix:\s*).*$/${1}""/m' \
            "$control_file" 2>/dev/null; then
            printf -v "$patched_var" 1
        else
            echo "[ERROR] Could not patch turtlebot diff_drive_controller TF prefix settings in: $control_file"
            return 1
        fi
    elif perl -0pi \
        -e 's#(turtlebot_velocity_controller:\n\s+ros__parameters:\n\s+use_sim_time:\s*true\n)#$1\n    tf_frame_prefix_enable: false\n    tf_frame_prefix: ""\n#' \
        "$control_file" 2>/dev/null; then
        printf -v "$patched_var" 1
    else
        echo "[ERROR] Could not insert turtlebot diff_drive_controller TF prefix settings in: $control_file"
        return 1
    fi

    if grep -q 'cmd_vel_timeout:' "$control_file"; then
        if perl -0pi \
            -e "s/^(\s*cmd_vel_timeout:\s*).*$/\${1}$cmd_vel_timeout/m" \
            "$control_file" 2>/dev/null; then
            printf -v "$patched_var" 1
        else
            echo "[ERROR] Could not patch turtlebot cmd_vel_timeout in: $control_file"
            return 1
        fi
    elif perl -0pi \
        -e "s#(\n\s*use_stamped_vel:\s*true\n)#\n    cmd_vel_timeout: $cmd_vel_timeout\$1#" \
        "$control_file" 2>/dev/null; then
        printf -v "$patched_var" 1
    else
        echo "[ERROR] Could not insert turtlebot cmd_vel_timeout in: $control_file"
        return 1
    fi

    if grep -q 'open_loop:' "$control_file"; then
        if perl -0pi \
            -e "s/^(\s*open_loop:\s*).*$/\${1}$open_loop/m" \
            "$control_file" 2>/dev/null; then
            printf -v "$patched_var" 1
        else
            echo "[ERROR] Could not patch turtlebot open_loop in: $control_file"
            return 1
        fi
    elif perl -0pi \
        -e "s#(\n\s*enable_odom_tf:\s*false\n)#\n    open_loop: $open_loop\$1#" \
        "$control_file" 2>/dev/null; then
        printf -v "$patched_var" 1
    else
        echo "[ERROR] Could not insert turtlebot open_loop in: $control_file"
        return 1
    fi
}

arena_ai_prepare_isaac_urdf() {
    local sim="${1:-isaac}"
    local robot="${2:-turtlebot}"

    if [ "$sim" != "isaac" ]; then
        return 0
    fi

    if [ "${ARENA_AI_PATCH_INSTALLED_URDF:-1}" != "1" ]; then
        return 0
    fi

    local robot_share="$WORKSPACE_DIR/install/arena_robots/share/arena_robots/robots/$robot"
    if [ ! -d "$robot_share" ]; then
        echo "[WARN] Isaac URDF preflight skipped; installed robot share not found: $robot_share"
        return 0
    fi

    echo "[INFO] Checking installed $robot URDF files for Isaac ros2_control bridge compatibility: $robot_share"
    local patched=0
    local file
    while IFS= read -r -d '' file; do
        if grep -q "gazebo_ros2_control/GazeboSystem" "$file"; then
            echo "[INFO] Patching ros2_control hardware plugin for Isaac bridge: $file"
            cp -n "$file" "$file.arena_ai.bak" 2>/dev/null || true
            if ! arena_ai_materialize_installed_file "$file"; then
                echo "[ERROR] Could not materialize installed robot description symlink: $file"
                return 1
            fi
            sed -i 's#gazebo_ros2_control/GazeboSystem#gz_ros2_control/GazeboSimSystem#g' "$file"
            patched=1
        fi
    done < <(
        find "$robot_share" -type f \
            \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
            ! -name '*.arena_ai.bak' -print0
    )
    arena_ai_remove_legacy_gazebo_ros2_control_plugins "$robot_share" "installed robot share" patched || return 1
    arena_ai_remove_turtlebot_templated_wheel_control_blocks "$robot_share" "installed robot share" patched || return 1

    # Some robots, notably turtlebot/create3, include ros2_control blocks from
    # dependency packages. Patch their installed/share descriptions too when
    # available so any xacro regenerated during spawn feeds Arena's Isaac URDF
    # transformer a gz_ros2_control block it knows how to rewrite.
    local dep_pkg dep_prefix dep_share
    for dep_pkg in irobot_create_description turtlebot4_description; do
        dep_prefix="$(ros2 pkg prefix "$dep_pkg" 2>/dev/null || true)"
        dep_share="$dep_prefix/share/$dep_pkg"
        if [ -z "$dep_prefix" ] || [ ! -d "$dep_share" ]; then
            continue
        fi
        if arena_ai_dependency_needs_control_patch "$dep_share"; then
            arena_ai_overlay_dependency_package "$dep_pkg" "$dep_share" dep_prefix dep_share patched || return 1
        fi
        while IFS= read -r -d '' file; do
            if grep -q "gazebo_ros2_control/GazeboSystem" "$file"; then
                echo "[INFO] Patching dependency ros2_control hardware plugin for Isaac bridge: $file"
                cp -n "$file" "$file.arena_ai.bak" 2>/dev/null || true
                if arena_ai_materialize_installed_file "$file" 2>/dev/null && \
                    sed -i 's#gazebo_ros2_control/GazeboSystem#gz_ros2_control/GazeboSimSystem#g' "$file" 2>/dev/null; then
                    patched=1
                else
                    echo "[WARN] Could not patch dependency file (permission denied?): $file"
                fi
            fi
        done < <(
            find "$dep_share" -type f \
                \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
                ! -name '*.arena_ai.bak' -print0
        )
        arena_ai_remove_legacy_gazebo_ros2_control_plugins "$dep_share" "dependency package $dep_pkg" patched || return 1
        arena_ai_remove_turtlebot_templated_wheel_control_blocks "$dep_share" "dependency package $dep_pkg" patched || return 1
    done

    if find "$robot_share" -type f \( -name '*.urdf' -o -name '*.xacro' -o -name '*.gazebo' \) \
        ! -name '*.arena_ai.bak' -exec grep -H "gazebo_ros2_control/GazeboSystem" {} \; | grep -q .; then
        echo "[ERROR] Isaac URDF preflight failed: $robot_share still references gazebo_ros2_control/GazeboSystem"
        echo "[ERROR] Rebuild arena_robots or patch the installed robot URDF files before running Isaac benchmarks."
        return 1
    fi

    if [ "$robot" = "turtlebot" ]; then
        arena_ai_patch_turtlebot_diff_drive_frames "$robot_share" patched || return 1
        arena_ai_disable_turtlebot_create3_gazebo_controls "$robot_share" patched || return 1
        arena_ai_remove_turtlebot_wheel_control_blocks "$robot_share" "installed robot share" patched || return 1
        arena_ai_remove_turtlebot_templated_wheel_control_blocks "$robot_share" "installed robot share" patched || return 1

        local turtlebot_scan_roots=("$robot_share")
        local dep_pkg dep_prefix dep_share
        for dep_pkg in irobot_create_description turtlebot4_description; do
            dep_prefix="$(ros2 pkg prefix "$dep_pkg" 2>/dev/null || true)"
            dep_share="$dep_prefix/share/$dep_pkg"
            if arena_ai_dependency_needs_control_patch "$dep_share"; then
                arena_ai_overlay_dependency_package "$dep_pkg" "$dep_share" dep_prefix dep_share patched || return 1
            fi
            if [ -n "$dep_prefix" ] && [ -d "$dep_share" ]; then
                turtlebot_scan_roots+=("$dep_share")
            fi
            arena_ai_remove_turtlebot_wheel_control_blocks "$dep_share" "dependency package $dep_pkg" patched || return 1
            arena_ai_remove_turtlebot_templated_wheel_control_blocks "$dep_share" "dependency package $dep_pkg" patched || return 1
        done

        arena_ai_assert_turtlebot_control_sources_clean "${turtlebot_scan_roots[@]}" || return 1

        local turtlebot_urdf="$robot_share/urdf/turtlebot.urdf"
        local control_count
        control_count="$(grep -c '<ros2_control ' "$turtlebot_urdf" 2>/dev/null || echo 0)"
        if [ "$control_count" -gt 1 ]; then
            echo "[ERROR] Turtlebot URDF still has $control_count ros2_control blocks after Isaac preflight."
            echo "[ERROR] Duplicate wheel interfaces make controller_manager import the same joints more than once,"
            echo "[ERROR] which matches ResourceStorage duplicate-key errors and can leave the robot unable to move."
            grep -n '<ros2_control ' "$turtlebot_urdf" 2>/dev/null || true
            return 1
        fi

        arena_ai_validate_turtlebot_generated_control "$robot_share" || return 1
    fi

    if [ "$patched" -eq 1 ]; then
        echo "[INFO] Isaac URDF preflight patch complete for robot=$robot"
    fi
}
