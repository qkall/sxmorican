#!/bin/sh
# title="$icon_trm Gomuks Control"
# gomuks_control.sh - Select action: Restart or Update Gomuks

SCRIPT_PATH=$(realpath "$0")
NOTIFY="sxmo_notify_user.sh"
TITLE="Gomuks Control"

notify() {
    "$NOTIFY" "$1" "$2" 2>/dev/null || true
    echo "[$1] $2"
}

restart_gomuks() {
    notify "$TITLE" "Stopping old instances..."
    killall gomuks 2>/dev/null || true
    
    notify "$TITLE" "Starting Gomuks..."
    nohup /usr/bin/gomuks >/dev/null 2>&1 &
    
    notify "$TITLE" "Restart complete!"
    sleep 2
}

update_gomuks() {
    notify "$TITLE" "Navigating to source..."
    cd "$HOME/gomuks" || { notify "$TITLE" "Error: ~/gomuks not found!"; sleep 5; exit 1; }

    notify "$TITLE" "Pulling latest changes..."
    if ! git pull; then
        notify "$TITLE" "Git pull failed!"
        sleep 5
        exit 1
    fi

    notify "$TITLE" "Building... this may take a while."
    if ! ./build.sh; then
        notify "$TITLE" "Build failed!"
        sleep 5
        exit 1
    fi

    notify "$TITLE" "Stopping old instances..."
    killall gomuks 2>/dev/null || true

    notify "$TITLE" "Installing new binary..."
    echo ""
    echo "=================================================="
    echo "  Root privileges required to install the binary  "
    echo "=================================================="

    while ! doas cp gomuks /usr/bin/gomuks; do
        echo "Incorrect password or error. Please try again."
    done

    notify "$TITLE" "Starting Gomuks..."
    nohup /usr/bin/gomuks >/dev/null 2>&1 &

    notify "$TITLE" "Update complete!"
    echo "Closing terminal in 3 seconds..."
    sleep 3
}

# 1. Check for command-line arguments (Triggered when terminal wrapper relaunches)
if [ "$1" = "update" ]; then
    update_gomuks
    exit 0
fi

# 2. Prompt for action
# If launched via GUI menu (no TTY), prompt via dmenu/wofi before spawning terminal
if [ ! -t 0 ]; then
    if command -v sxmo_dmenu.sh >/dev/null 2>&1; then
        CHOICE=$(printf "Restart Gomuks\nUpdate & Build Gomuks" | sxmo_dmenu.sh -p "Gomuks Action:")
    elif command -v wofi >/dev/null 2>&1; then
        CHOICE=$(printf "Restart Gomuks\nUpdate & Build Gomuks" | wofi -d -p "Gomuks Action:")
    else
        CHOICE="Update & Build Gomuks"
    fi
else
    # Interactively prompt in terminal
    echo "Select an option:"
    echo "1) Restart Gomuks"
    echo "2) Update & Build Gomuks"
    printf "Option [1-2]: "
    read -r REPLY
    case "$REPLY" in
        1) CHOICE="Restart Gomuks" ;;
        2) CHOICE="Update & Build Gomuks" ;;
        *) echo "Invalid choice"; exit 1 ;;
    esac
fi

# 3. Execute selected action
case "$CHOICE" in
    "Restart Gomuks")
        restart_gomuks
        ;;
    "Update & Build Gomuks")
        # Relaunch in terminal wrapper for doas/build output if GUI-launched
        if [ ! -t 0 ]; then
            exec sxmo_terminal.sh -- sh -c "'$SCRIPT_PATH' update"
            exit 0
        fi
        update_gomuks
        ;;
esac
