#!/bin/sh
# rgb_screen_react.sh - Screen-reactive RGB lighting for MuOS
# Samples screen colors and controls RGB LEDs to match content
# Uses saturation-weighted averaging for vibrant, accurate colors
#
# This is a standalone script with LED control built-in.
# No external dependencies required.

#==============================================================================
# CONFIGURATION - Edit these values to customize behavior
#==============================================================================

# System paths
SETTINGS_FILE="/run/muos/storage/theme/active/rgb/settings.txt" # MuOS RGB settings path, might change with OS updates
FB_DEVICE="/dev/fb0"			# Framebuffer path

# Sampling area
MARGIN_PERCENT=20				# Percentage of screen edges to ignore (0-50)
PIXELS_LONG_SIDE=5				# Grid size for sampling (4-6 recommended, higher=more CPU)

# Color processing
FINAL_SATURATION_BOOST=250		# Saturation boost (100=none, 200=2x, higher=more vibrant)

# Timing intervals (in milliseconds)
SAMPLE_INTERVAL_MS=400			# Screen read refresh rate (lower=more responsive but higher CPU)
FRAME_INTERVAL_MS=50			# Main loop refresh rate (lower=smoother but higher CPU)
LED_INTERVAL_MS=50				# LED update rate (should match or be higher than FRAME_INTERVAL_MS)

# Power saving
ENABLE_SCREEN_DETECTION=1		# Pauses all loops when screen is dimmed or off (1=on, 0=off)

#==============================================================================
# LED CONTROL FUNCTIONS
#==============================================================================

# LED hardware paths
LED_SYSFS="/sys/class/led_anim"
SERIAL_DEVICE="/dev/ttyS5"
MCU_PWR="/sys/class/power_supply/axp2202-battery/mcu_pwr"
BACKEND_CACHE="/tmp/rgb_backend_cache"

# Clamp value to range
led_clamp() {
    local v=$1
    local min=$2
    local max=$3
    [ "$v" -lt "$min" ] && v=$min
    [ "$v" -gt "$max" ] && v=$max
    printf "%d" "$v"
}

# Convert RGB to hex string
led_to_hex() {
    printf "%02X%02X%02X" "$1" "$2" "$3"
}

# Calculate checksum for serial protocol
led_checksum() {
    local sum=0
    for byte in $@; do
        sum=$(((sum + byte) & 255))
    done
    printf "%d" "$sum"
}

# Write bytes to serial device
led_serial_write() {
    printf %b "$(printf '\\x%02X' "$@")" >"$SERIAL_DEVICE"
}

# Initialize serial device (one-time, cached)
led_serial_init() {
    if [ ! -f "/tmp/rgb_serial_initialized" ]; then
        [ -w "$MCU_PWR" ] && printf "1\n" >"$MCU_PWR"
        stty -F "$SERIAL_DEVICE" 115200 cs8 -parenb -cstopb -opost -isig -icanon -echo 2>/dev/null
        touch "/tmp/rgb_serial_initialized"
        sleep 0.05
    fi
}

# Detect LED backend (SYSFS or SERIAL) and cache result
led_detect_backend() {
    if [ -f "$BACKEND_CACHE" ]; then
        cat "$BACKEND_CACHE"
        return
    fi
    
    if [ -d "$LED_SYSFS" ]; then
        echo "SYSFS" > "$BACKEND_CACHE"
        echo "SYSFS"
    elif [ -c "$SERIAL_DEVICE" ]; then
        echo "SERIAL" > "$BACKEND_CACHE"
        echo "SERIAL"
    else
        return 1
    fi
}

# Write to SYSFS attribute
led_sysfs_write() {
    local path="$LED_SYSFS/$1"
    local value=$2
    [ -w "$path" ] && printf "%s\n" "$value" >"$path"
}

# Check if SYSFS attribute exists
led_sysfs_has() {
    [ -w "$LED_SYSFS/$1" ]
}

# Update LEDs via SYSFS backend
led_update_sysfs() {
    local bri=$1
    local l_r=$2 l_g=$3 l_b=$4
    local r_r=$5 r_g=$6 r_b=$7
    
    # Scale brightness to SYSFS range (0-60)
    bri=$(( bri * 60 / 255 ))
    bri=$(led_clamp "$bri" 0 60)
    
    # Clamp RGB values
    l_r=$(led_clamp "$l_r" 0 255)
    l_g=$(led_clamp "$l_g" 0 255)
    l_b=$(led_clamp "$l_b" 0 255)
    r_r=$(led_clamp "$r_r" 0 255)
    r_g=$(led_clamp "$r_g" 0 255)
    r_b=$(led_clamp "$r_b" 0 255)
    
    # Convert to hex
    local hex_l=$(led_to_hex "$l_r" "$l_g" "$l_b")
    local hex_r=$(led_to_hex "$r_r" "$r_g" "$r_b")
    
    # Write brightness
    led_sysfs_write "max_scale" "$bri"
    
    # Write colors (use combined attribute if both sides match)
    if [ "$hex_l" = "$hex_r" ] && led_sysfs_has "effect_rgb_hex_lr"; then
        led_sysfs_write "effect_rgb_hex_lr" "$hex_l "
    else
        led_sysfs_write "effect_rgb_hex_l" "$hex_l "
        led_sysfs_write "effect_rgb_hex_r" "$hex_r "
    fi
    
    # Set effect mode (4 = static color)
    if led_sysfs_has "effect_lr"; then
        led_sysfs_write "effect_lr" "4"
    else
        led_sysfs_write "effect_l" "4"
        led_sysfs_write "effect_r" "4"
    fi
    
    # Enable effect
    led_sysfs_write "effect_enable" "1"
}

# Update LEDs via SERIAL backend
led_update_serial() {
    local bri=$1
    local l_r=$2 l_g=$3 l_b=$4
    local r_r=$5 r_g=$6 r_b=$7
    
    # Clamp values
    bri=$(led_clamp "$bri" 0 255)
    l_r=$(led_clamp "$l_r" 0 255)
    l_g=$(led_clamp "$l_g" 0 255)
    l_b=$(led_clamp "$l_b" 0 255)
    r_r=$(led_clamp "$r_r" 0 255)
    r_g=$(led_clamp "$r_g" 0 255)
    r_b=$(led_clamp "$r_b" 0 255)
    
    # Build packet: mode(1) + brightness + 8 right LEDs + 8 left LEDs
    local bytes="1 $bri"
    
    # Add 8 right LEDs
    local i=0
    while [ $i -lt 8 ]; do
        bytes="$bytes $r_r $r_g $r_b"
        i=$((i + 1))
    done
    
    # Add 8 left LEDs
    i=0
    while [ $i -lt 8 ]; do
        bytes="$bytes $l_r $l_g $l_b"
        i=$((i + 1))
    done
    
    # Calculate and append checksum
    local chk=$(led_checksum $bytes)
    set -- $bytes "$chk"
    
    # Send to serial device
    led_serial_write "$@"
}

# Main LED update function (auto-detects backend)
update_leds() {
    local bri=$1
    local l_r=$2 l_g=$3 l_b=$4
    local r_r=$5 r_g=$6 r_b=$7
    
    local backend=$(led_detect_backend)
    
    case "$backend" in
        SYSFS)
            led_update_sysfs "$bri" "$l_r" "$l_g" "$l_b" "$r_r" "$r_g" "$r_b"
            ;;
        SERIAL)
            led_serial_init
            led_update_serial "$bri" "$l_r" "$l_g" "$l_b" "$r_r" "$r_g" "$r_b"
            ;;
    esac
}

#==============================================================================
# SCREEN SAMPLING FUNCTIONS
#==============================================================================

get_setting() {
    grep "^$1=" "$SETTINGS_FILE" 2>/dev/null | cut -d'=' -f2
}

get_fb_resolution() {
    fbset | grep "geometry" | awk '{print $2, $3}'
}

# Check if screen is active (returns 0 if active, 1 if idle/blanked)
is_screen_on() {
    [ "$ENABLE_SCREEN_DETECTION" -eq 0 ] && return 0
    
    # Check if system is idle (managed by /opt/muos/script/device/idle.sh)
    # When idle: screen dims to 10, audio mutes, LEDs turn off
    [ -f "/tmp/is_idle" ] && return 1
    
    # Also check framebuffer blank state as backup
    # (0=on, 1-4=off/suspended)
    local blank_file="/sys/class/graphics/fb0/blank"
    if [ -r "$blank_file" ]; then
        local blank_state=$(cat "$blank_file" 2>/dev/null)
        [ -n "$blank_state" ] && [ "$blank_state" -ne 0 ] && return 1
    fi
    
    # Screen is active
    return 0
}

# Check if battery is low (returns 0 if normal, 1 if low)
is_battery_low() {
    # One-time cache init
    if [ -z "$_BATT_CACHE_INIT" ]; then
        # Load MuOS variable helpers once
        . /opt/muos/script/var/func.sh 2>/dev/null || return 1

        _BATT_CHARGER=$(GET_VAR "device" "battery/charger")
        _BATT_CAPACITY=$(GET_VAR "device" "battery/capacity")
        _BATT_THRESHOLD=$(GET_VAR "config" "settings/power/low_battery")

        _BATT_CACHE_INIT=1
    fi

    # Validate cached paths
    [ -r "$_BATT_CHARGER" ] || return 1
    [ -r "$_BATT_CAPACITY" ] || return 1

    # Live readings
    read -r charging < "$_BATT_CHARGER"
    read -r capacity < "$_BATT_CAPACITY"

    # Low battery = not charging AND under threshold
    if [ "$charging" -eq 0 ] &&
       [ -n "$capacity" ] &&
       [ -n "$_BATT_THRESHOLD" ] &&
       [ "$capacity" -le "$_BATT_THRESHOLD" ]; then
        return 0   # low battery
    fi

    return 1       # normal battery
}

smooth_value() {
    # Exponential smoothing: gradually moves current value toward target
    local curr=$1
    local target=$2
    local smoothing=$3
    
    local diff=$((target - curr))
    local step=$((diff * smoothing / 100))
    [ "$diff" -gt 0 ] && [ "$step" -eq 0 ] && step=1
    [ "$diff" -lt 0 ] && [ "$step" -eq 0 ] && step=-1
    echo $((curr + step))
}

#==============================================================================
# INITIALIZATION
#==============================================================================

# Get screen resolution
read FB_WIDTH FB_HEIGHT <<EOF
$(get_fb_resolution)
EOF

# Calculate sampling grid (maintains aspect ratio, minimum 3 on each side)
if [ "$FB_WIDTH" -ge "$FB_HEIGHT" ]; then
    GRID_W=$PIXELS_LONG_SIDE
    GRID_H=$(( FB_HEIGHT * PIXELS_LONG_SIDE / FB_WIDTH ))
    [ "$GRID_H" -lt 3 ] && GRID_H=3
else
    GRID_H=$PIXELS_LONG_SIDE
    GRID_W=$(( FB_WIDTH * PIXELS_LONG_SIDE / FB_HEIGHT ))
    [ "$GRID_W" -lt 3 ] && GRID_W=3
fi

# Calculate margin dimensions
margin_w=$(( FB_WIDTH * MARGIN_PERCENT / 100 ))
margin_h=$(( FB_HEIGHT * MARGIN_PERCENT / 100 ))
sample_w=$(( FB_WIDTH - margin_w * 2 ))
sample_h=$(( FB_HEIGHT - margin_h * 2 ))

# Auto-calculate smoothing to reach target by next sample
# This ensures colors transition smoothly and complete before next update
frames_between_samples=$(( SAMPLE_INTERVAL_MS / FRAME_INTERVAL_MS ))
if [ "$frames_between_samples" -gt 1 ]; then
    SMOOTHING=$(( 370 / frames_between_samples ))
    [ "$SMOOTHING" -lt 10 ] && SMOOTHING=10
    [ "$SMOOTHING" -gt 50 ] && SMOOTHING=50
else
    SMOOTHING=50
fi

# Color state (current and target for left and right LEDs)
curr_r_l=0 curr_g_l=0 curr_b_l=0
curr_r_r=0 curr_g_r=0 curr_b_r=0
target_r_l=0 target_g_l=0 target_b_l=0
target_r_r=0 target_g_r=0 target_b_r=0

# Timing state
next_sample_time=0
next_led_time=0

#==============================================================================
# MAIN LOOP
#==============================================================================

while true; do
    loop_start=$(awk '{print int($1 * 1000)}' /proc/uptime)
    
    mode=$(get_setting "mode")
    
    # Exit if Screen React mode (9) is not active
    # The RGB Screen React app will restart this script when mode 9 is enabled again
    if [ "$mode" != "9" ]; then
        exit 0
    fi
    
    [ ! -r "$FB_DEVICE" ] && sleep 1 && continue
    
    brightness=$(get_setting "brightness")
    [ -z "$brightness" ] && brightness=7
    
    current_time=$loop_start
	
    # Check if battery is low
    if is_battery_low; then
		# Don't need to update LEDs here because MuOS will do it when the battery is low
        sleep 1
        continue
    fi
    
    # Check if screen is active (skip updates when idle/blanked to save power)
    if ! is_screen_on; then
        # Turn off LEDs to prevent overriding idle system's LED shutdown
        update_leds 0 0 0 0 0 0 0
        sleep 1
        continue
    fi
    
    #--------------------------------------------------------------------------
    # PIXEL SAMPLING - Read screen colors at configured interval
    #--------------------------------------------------------------------------
    if [ "$current_time" -ge "$next_sample_time" ]; then
        sample_start=$current_time
        
        # Accumulate weighted color sums (left and right sides)
        weighted_r_l=0 weighted_g_l=0 weighted_b_l=0
        weighted_r_r=0 weighted_g_r=0 weighted_b_r=0
        weight_l=0 weight_r=0
        
        # Read pixels in staggered brick pattern for better coverage
        row=0
        while [ $row -lt $GRID_H ]; do
            col=0
            while [ $col -lt $GRID_W ]; do
                # Calculate pixel position in sampling area
                col_spacing=$(( sample_w / GRID_W ))
                half_spacing=$(( col_spacing / 2 ))
                quarter_spacing=$(( half_spacing / 2 ))
                
                base_px=$(( margin_w + col * col_spacing + half_spacing ))
                
                # Stagger rows for better spatial coverage
                if [ $(( row % 2 )) -eq 1 ]; then
                    px=$(( base_px - quarter_spacing ))
                else
                    px=$(( base_px + quarter_spacing ))
                fi
                
                py=$(( margin_h + row * sample_h / GRID_H + sample_h / (GRID_H * 2) ))
                
                # Read pixel from framebuffer (BGRA format)
                offset=$(( (py * FB_WIDTH + px) * 4 ))
                pixel=$(dd if="$FB_DEVICE" bs=1 skip=$offset count=4 2>/dev/null | od -An -tu1)
                
                set -- $pixel
                b=$1 g=$2 r=$3
                
                # Calculate saturation weight (vibrant colors get more influence)
                max_c=$r
                [ "$g" -gt "$max_c" ] && max_c=$g
                [ "$b" -gt "$max_c" ] && max_c=$b
                
                min_c=$r
                [ "$g" -lt "$min_c" ] && min_c=$g
                [ "$b" -lt "$min_c" ] && min_c=$b
                
                if [ "$max_c" -gt 0 ]; then
                    weight_int=$(( (max_c - min_c) * 100 / max_c ))
                    [ "$weight_int" -lt 1 ] && weight_int=1
                else
                    weight_int=1
                fi
                
                # Accumulate to left or right side based on pixel position
                if [ "$px" -lt $(( FB_WIDTH / 2 )) ]; then
                    weighted_r_l=$(( weighted_r_l + r * weight_int ))
                    weighted_g_l=$(( weighted_g_l + g * weight_int ))
                    weighted_b_l=$(( weighted_b_l + b * weight_int ))
                    weight_l=$(( weight_l + weight_int ))
                else
                    weighted_r_r=$(( weighted_r_r + r * weight_int ))
                    weighted_g_r=$(( weighted_g_r + g * weight_int ))
                    weighted_b_r=$(( weighted_b_r + b * weight_int ))
                    weight_r=$(( weight_r + weight_int ))
                fi
                
                col=$(( col + 1 ))
            done
            row=$(( row + 1 ))
        done
        
        # Calculate weighted averages and apply adaptive saturation boost
        # Left side
        if [ "$weight_l" -gt 0 ]; then
            avg_r_l=$(( weighted_r_l / weight_l ))
            avg_g_l=$(( weighted_g_l / weight_l ))
            avg_b_l=$(( weighted_b_l / weight_l ))
            
            # Calculate current saturation
            max_c=$avg_r_l
            [ "$avg_g_l" -gt "$max_c" ] && max_c=$avg_g_l
            [ "$avg_b_l" -gt "$max_c" ] && max_c=$avg_b_l
            
            min_c=$avg_r_l
            [ "$avg_g_l" -lt "$min_c" ] && min_c=$avg_g_l
            [ "$avg_b_l" -lt "$min_c" ] && min_c=$avg_b_l
            
            if [ "$max_c" -gt 0 ]; then
                current_sat=$(( (max_c - min_c) * 100 / max_c ))
            else
                current_sat=0
            fi
            
            # Adaptive boost: only boosts desaturated colors
            boost_int=$(( 100 + (100 - current_sat) * (FINAL_SATURATION_BOOST - 100) / 100 ))
            
            gray=$(( (avg_r_l + avg_g_l + avg_b_l) / 3 ))
            target_r_l=$(( gray + (avg_r_l - gray) * boost_int / 100 ))
            target_g_l=$(( gray + (avg_g_l - gray) * boost_int / 100 ))
            target_b_l=$(( gray + (avg_b_l - gray) * boost_int / 100 ))
            
            # Clamp to valid RGB range
            [ "$target_r_l" -lt 0 ] && target_r_l=0
            [ "$target_r_l" -gt 255 ] && target_r_l=255
            [ "$target_g_l" -lt 0 ] && target_g_l=0
            [ "$target_g_l" -gt 255 ] && target_g_l=255
            [ "$target_b_l" -lt 0 ] && target_b_l=0
            [ "$target_b_l" -gt 255 ] && target_b_l=255
        fi
        
        # Right side
        if [ "$weight_r" -gt 0 ]; then
            avg_r_r=$(( weighted_r_r / weight_r ))
            avg_g_r=$(( weighted_g_r / weight_r ))
            avg_b_r=$(( weighted_b_r / weight_r ))
            
            max_c=$avg_r_r
            [ "$avg_g_r" -gt "$max_c" ] && max_c=$avg_g_r
            [ "$avg_b_r" -gt "$max_c" ] && max_c=$avg_b_r
            
            min_c=$avg_r_r
            [ "$avg_g_r" -lt "$min_c" ] && min_c=$avg_g_r
            [ "$avg_b_r" -lt "$min_c" ] && min_c=$avg_b_r
            
            if [ "$max_c" -gt 0 ]; then
                current_sat=$(( (max_c - min_c) * 100 / max_c ))
            else
                current_sat=0
            fi
            
            boost_int=$(( 100 + (100 - current_sat) * (FINAL_SATURATION_BOOST - 100) / 100 ))
            
            gray=$(( (avg_r_r + avg_g_r + avg_b_r) / 3 ))
            target_r_r=$(( gray + (avg_r_r - gray) * boost_int / 100 ))
            target_g_r=$(( gray + (avg_g_r - gray) * boost_int / 100 ))
            target_b_r=$(( gray + (avg_b_r - gray) * boost_int / 100 ))
            
            [ "$target_r_r" -lt 0 ] && target_r_r=0
            [ "$target_r_r" -gt 255 ] && target_r_r=255
            [ "$target_g_r" -lt 0 ] && target_g_r=0
            [ "$target_g_r" -gt 255 ] && target_g_r=255
            [ "$target_b_r" -lt 0 ] && target_b_r=0
            [ "$target_b_r" -gt 255 ] && target_b_r=255
        fi
        
        sample_end=$(awk '{print int($1 * 1000)}' /proc/uptime)
        sample_duration=$((sample_end - sample_start))
        
        # Schedule next sample
        if [ "$sample_duration" -gt "$SAMPLE_INTERVAL_MS" ]; then
            next_sample_time=$sample_end
        else
            next_sample_time=$((sample_end + SAMPLE_INTERVAL_MS))
        fi
    fi
    
    #--------------------------------------------------------------------------
    # COLOR SMOOTHING - Gradually transition current colors toward targets
    #--------------------------------------------------------------------------
    curr_r_l=$(smooth_value $curr_r_l $target_r_l $SMOOTHING)
    curr_g_l=$(smooth_value $curr_g_l $target_g_l $SMOOTHING)
    curr_b_l=$(smooth_value $curr_b_l $target_b_l $SMOOTHING)
    curr_r_r=$(smooth_value $curr_r_r $target_r_r $SMOOTHING)
    curr_g_r=$(smooth_value $curr_g_r $target_g_r $SMOOTHING)
    curr_b_r=$(smooth_value $curr_b_r $target_b_r $SMOOTHING)
    
    #--------------------------------------------------------------------------
    # LED UPDATE - Send colors to RGB LEDs
    #--------------------------------------------------------------------------
    current_time=$(awk '{print int($1 * 1000)}' /proc/uptime)
    if [ "$current_time" -ge "$next_led_time" ]; then
        led_start=$current_time
        
        bright=$((brightness * 25))
        [ "$bright" -gt 255 ] && bright=255
        
        # Update LEDs using built-in function
        update_leds "$bright" "$curr_r_l" "$curr_g_l" "$curr_b_l" "$curr_r_r" "$curr_g_r" "$curr_b_r"
        
        led_end=$(awk '{print int($1 * 1000)}' /proc/uptime)
        led_duration=$((led_end - led_start))
        
        # Schedule next LED update
        if [ "$led_duration" -gt "$LED_INTERVAL_MS" ]; then
            next_led_time=$led_end
        else
            next_led_time=$((led_end + LED_INTERVAL_MS))
        fi
    fi
    
    #--------------------------------------------------------------------------
    # FRAME TIMING - Maintain consistent loop rate
    #--------------------------------------------------------------------------
    loop_end=$(awk '{print int($1 * 1000)}' /proc/uptime)
    loop_duration=$((loop_end - loop_start))
    sleep_time=$((FRAME_INTERVAL_MS - loop_duration))
    
    if [ "$sleep_time" -gt 0 ]; then
        sleep_sec=$(awk "BEGIN {print $sleep_time / 1000}")
        sleep "$sleep_sec"
    fi
done
