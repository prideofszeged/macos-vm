#!/usr/bin/env bash

# macOS VM Launcher
# Runs the VM in background so closing terminal won't kill it

VM_NAME="macOS-Sonoma"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$SCRIPT_DIR/.macos-vm.pid"
LOGFILE="$SCRIPT_DIR/vm.log"

is_running() {
    if [[ -f "$PIDFILE" ]]; then
        pid=$(cat "$PIDFILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

start_vm() {
    if is_running; then
        echo "VM is already running (PID: $(cat "$PIDFILE"))"
        echo "Use 'stop' or 'restart' options"
        exit 1
    fi

    echo "Starting $VM_NAME..."
    cd "$SCRIPT_DIR"

    # Run in background with nohup
    nohup ./OpenCore-Boot.sh > "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"

    echo "VM started in background (PID: $(cat "$PIDFILE"))"
    echo "Log: $LOGFILE"
    echo ""
    echo "The QEMU window should appear shortly."
    echo "You can safely close this terminal."
}

stop_vm() {
    if ! is_running; then
        echo "VM is not running"
        rm -f "$PIDFILE"
        exit 0
    fi

    pid=$(cat "$PIDFILE")
    echo "Stopping VM (PID: $pid)..."
    kill "$pid" 2>/dev/null
    sleep 2

    if ps -p "$pid" > /dev/null 2>&1; then
        echo "Force killing..."
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PIDFILE"
    echo "VM stopped"
}

status_vm() {
    if is_running; then
        echo "VM is running (PID: $(cat "$PIDFILE"))"
    else
        echo "VM is not running"
    fi
}

show_menu() {
    echo "================================"
    echo "   macOS VM Launcher"
    echo "================================"
    echo ""
    status_vm
    echo ""
    echo "1) Start VM"
    echo "2) Stop VM"
    echo "3) Restart VM"
    echo "4) View Log"
    echo "5) Exit"
    echo ""
    read -p "Choose option: " choice

    case $choice in
        1) start_vm ;;
        2) stop_vm ;;
        3) stop_vm; sleep 1; start_vm ;;
        4) tail -50 "$LOGFILE" 2>/dev/null || echo "No log file yet" ;;
        5) exit 0 ;;
        *) echo "Invalid option" ;;
    esac
}

# Handle command line args or show menu
case "${1:-}" in
    start)   start_vm ;;
    stop)    stop_vm ;;
    restart) stop_vm; sleep 1; start_vm ;;
    status)  status_vm ;;
    log)     tail -f "$LOGFILE" ;;
    *)       show_menu ;;
esac
