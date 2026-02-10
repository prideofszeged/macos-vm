# How It All Works

This doc walks through the entire system — what each piece does, how they connect, and what happens at every stage from first clone to a running macOS VM.

## The Big Picture

```mermaid
graph TB
    subgraph "Your Config Repo (macos-vm)"
        BS[bootstrap.sh]
        PATCH[patches/OpenCore-Boot.sh.patch]
        SETUP[files/setup.sh]
        LAUNCHER[files/macos-launcher.sh]
        KVMCONF[files/kvm-macos.conf]
        VMCLIP[files/vm-clip]
    end

    subgraph "Upstream (kholia/OSX-KVM)"
        UPSTREAM[GitHub: kholia/OSX-KVM]
    end

    subgraph "Local Working Copy (OSX-KVM/)"
        OC[OpenCore-Boot.sh<br><i>patched for AMD</i>]
        SETUP2[setup.sh<br><i>copied in</i>]
        LAUNCHER2[macos-launcher.sh<br><i>copied in</i>]
        OPENCORE[OpenCore/OpenCore.qcow2]
        FETCH[fetch-macOS-v2.py]
        OVMF[OVMF firmware files]
        BASE[BaseSystem.img]
        HDD[mac_hdd_ng.img]
    end

    BS -->|"1. git clone"| UPSTREAM
    UPSTREAM -->|cloned to| OC
    BS -->|"2. git apply"| PATCH
    PATCH -->|patches| OC
    BS -->|"3. cp"| SETUP
    BS -->|"3. cp"| LAUNCHER
    BS -->|"3. cp"| KVMCONF
    SETUP -->|copied to| SETUP2
    LAUNCHER -->|copied to| LAUNCHER2
    BS -->|"4. runs"| SETUP2
    BS -->|"3. install"| VMCLIP
    VMCLIP -->|installed to| VMCLIP2["~/.local/bin/vm-clip"]

    style BS fill:#4a9eff,color:#fff
    style PATCH fill:#ff6b6b,color:#fff
    style OC fill:#51cf66,color:#fff
    style SETUP2 fill:#ffd43b,color:#000
    style LAUNCHER2 fill:#ffd43b,color:#000
    style VMCLIP fill:#b197fc,color:#fff
    style VMCLIP2 fill:#b197fc,color:#fff
```

## Bootstrap Flow

When you run `./bootstrap.sh`, here's what happens step by step:

```mermaid
flowchart TD
    START([./bootstrap.sh]) --> CHECK{OSX-KVM<br>already cloned?}

    CHECK -->|No| CLONE["<b>1. Clone upstream</b><br>git clone kholia/OSX-KVM"]
    CHECK -->|Yes| PULL["<b>1. Pull latest</b><br>git pull --ff-only"]

    CLONE --> PATCHCHECK
    PULL --> PATCHCHECK

    PATCHCHECK{"Patch applies<br>cleanly?"}
    PATCHCHECK -->|Yes| APPLY["<b>2. Apply patch</b><br>git apply OpenCore-Boot.sh.patch<br><br>- CPU: Skylake-Client → Haswell-noTSX<br>- RAM: 4GB → 16GB<br>- Cores: 2/4 → 6/12<br>- Flags: +avx2,+fma,+bmi1,+bmi2,+smep"]
    PATCHCHECK -->|No| SKIP["2. Skip<br>(already applied or conflict)"]

    APPLY --> COPY
    SKIP --> COPY

    COPY["<b>3. Copy custom files</b><br>setup.sh, macos-launcher.sh, kvm-macos.conf"]

    COPY --> SETUPFLAG{"--no-setup<br>flag?"}
    SETUPFLAG -->|No| RUNSETUP["<b>4. Run setup.sh</b><br>(see Setup Flow below)"]
    SETUPFLAG -->|Yes| DONE

    RUNSETUP --> DONE([Done — VM ready to launch])

    style START fill:#4a9eff,color:#fff
    style APPLY fill:#ff6b6b,color:#fff
    style COPY fill:#ffd43b,color:#000
    style RUNSETUP fill:#51cf66,color:#fff
    style DONE fill:#51cf66,color:#fff
```

## Setup Flow

`setup.sh` handles all the one-time installation work:

```mermaid
flowchart TD
    START(["setup.sh"]) --> CPU["<b>[1/7] Check CPU</b><br>grep /proc/cpuinfo for vmx|svm<br>→ Detects AMD vs Intel"]
    CPU --> KVM["<b>[2/7] Check KVM</b><br>Is /dev/kvm readable+writable?"]
    KVM --> DEPS["<b>[3/7] Install deps</b><br>apt/dnf/pacman install<br>qemu-system-x86, dmg2img"]
    DEPS --> KMOD["<b>[4/7] Kernel modules</b><br>Write /etc/modprobe.d/kvm-macos.conf<br>Set ignore_msrs=1 (live)"]
    KMOD --> DL{"BaseSystem.img<br>exists?"}
    DL -->|No| DOWNLOAD["<b>[5/7] Download macOS</b><br>fetch-macOS-v2.py → .dmg<br>dmg2img → BaseSystem.img"]
    DL -->|Yes| DISKCHECK
    DOWNLOAD --> DISKCHECK
    DISKCHECK{"mac_hdd_ng.img<br>exists?"}
    DISKCHECK -->|No| DISK["<b>[6/7] Create disk</b><br>qemu-img create -f qcow2<br>mac_hdd_ng.img 80G"]
    DISKCHECK -->|Yes| DESKTOP
    DISK --> DESKTOP
    DESKTOP["<b>[7/7] Desktop launcher</b><br>Write .desktop file<br>to ~/.local/share/applications/"]
    DESKTOP --> READY(["Setup complete"])

    style START fill:#51cf66,color:#fff
    style KMOD fill:#ff6b6b,color:#fff
    style DOWNLOAD fill:#ffd43b,color:#000
    style READY fill:#51cf66,color:#fff
```

## VM Launch Flow

`macos-launcher.sh` manages the VM lifecycle:

```mermaid
flowchart TD
    START(["./macos-launcher.sh"]) --> ARGS{"Command line<br>argument?"}

    ARGS -->|start| STARTVM
    ARGS -->|stop| STOPVM
    ARGS -->|restart| STOPVM2["Stop VM"] --> WAIT["sleep 1"] --> STARTVM2["Start VM"]
    ARGS -->|status| STATUS["Check PID file"]
    ARGS -->|log| LOG["tail -f vm.log"]
    ARGS -->|none| MENU["Show interactive menu"]

    STARTVM{"Already<br>running?"}
    STARTVM -->|Yes| ABORT["Print error, exit"]
    STARTVM -->|No| LAUNCH["nohup ./OpenCore-Boot.sh<br>> vm.log 2>&1 &<br><br>Save PID to .macos-vm.pid"]
    LAUNCH --> RUNNING(["VM running in background<br>Terminal safe to close"])

    STOPVM["Read PID from file<br>kill $PID<br>rm .macos-vm.pid"]

    style START fill:#4a9eff,color:#fff
    style LAUNCH fill:#51cf66,color:#fff
    style RUNNING fill:#51cf66,color:#fff
    style MENU fill:#ffd43b,color:#000
```

## What QEMU Actually Runs

When the VM starts, `OpenCore-Boot.sh` assembles a big `qemu-system-x86_64` command. Here's what each piece does:

```mermaid
graph LR
    subgraph "CPU & Memory"
        A["-cpu Haswell-noTSX<br>+avx2,+fma,+bmi..."]
        B["-m 16384<br>(16GB RAM)"]
        C["-smp 12,cores=6<br>(6 cores, 12 threads)"]
    end

    subgraph "Storage"
        D["OpenCore.qcow2<br>(bootloader)"]
        E["BaseSystem.img<br>(macOS installer)"]
        F["mac_hdd_ng.img<br>(main disk, 80GB)"]
    end

    subgraph "Firmware"
        G["OVMF_CODE_4M.fd<br>(UEFI firmware)"]
        H["OVMF_VARS-1920x1080.fd<br>(UEFI settings + resolution)"]
    end

    subgraph "Devices"
        I["vmware-svga<br>(display)"]
        J["virtio-net-pci<br>(network)"]
        K["ich9-intel-hda<br>(audio)"]
        L["usb-kbd + usb-tablet<br>(input)"]
    end

    subgraph "Network"
        M["User-mode networking<br>Host :2222 → Guest :22<br>(SSH access)"]
    end

    A --> QEMU((qemu-system-x86_64))
    B --> QEMU
    C --> QEMU
    D --> QEMU
    E --> QEMU
    F --> QEMU
    G --> QEMU
    H --> QEMU
    I --> QEMU
    J --> QEMU
    K --> QEMU
    L --> QEMU
    M --> QEMU

    style QEMU fill:#4a9eff,color:#fff,stroke-width:3px
```

## The Boot Chain

When the VM starts, this is the boot sequence:

```mermaid
sequenceDiagram
    participant Q as QEMU
    participant OC as OpenCore<br>(bootloader)
    participant I as macOS Installer<br>(BaseSystem.img)
    participant M as macOS<br>(mac_hdd_ng.img)

    Q->>OC: UEFI loads OpenCore from OpenCore.qcow2
    Note over OC: OpenCore presents boot menu

    alt First boot (installing)
        OC->>I: Boot "macOS Base System"
        Note over I: You run Disk Utility<br>→ format mac_hdd_ng.img as APFS
        I->>M: Install macOS to disk
        Note over M: Multiple reboots during install
        OC->>M: Boot "Macintosh HD"
        Note over M: macOS Sonoma running!
    else Normal boot (installed)
        OC->>M: Boot "Macintosh HD"
        Note over M: macOS Sonoma running!
    end
```

## Network: Talking to the VM

```mermaid
graph LR
    subgraph "Linux Host"
        APP["Your terminal"]
        PORT["localhost:2222"]
    end

    subgraph "QEMU Network"
        NAT["User-mode NAT<br>(10.0.2.x)"]
    end

    subgraph "macOS Guest"
        SSH["sshd :22"]
        MAC["macOS Sonoma"]
    end

    APP -->|"ssh -p 2222<br>localhost"| PORT
    PORT -->|"port forward"| NAT
    NAT -->|"→ :22"| SSH
    SSH --> MAC

    style APP fill:#4a9eff,color:#fff
    style NAT fill:#ffd43b,color:#000
    style MAC fill:#51cf66,color:#fff
```

## Clipboard Sharing: vm-clip

`vm-clip` provides seamless bidirectional clipboard sync between the Linux host and macOS VM. No special agent needed on the macOS side — it uses `pbcopy`/`pbpaste` over SSH.

### How It Works

```mermaid
sequenceDiagram
    participant HC as Linux Clipboard<br>(xclip)
    participant LOOP as vm-clip<br>(bash loop)
    participant SSH as SSH ControlMaster<br>(persistent connection)
    participant MC as macOS Clipboard<br>(pbcopy/pbpaste)

    Note over LOOP: Polls every 500ms

    loop Every 500ms
        LOOP->>HC: Read host clipboard (xclip -o)
        LOOP->>SSH: Read VM clipboard (pbpaste)
        SSH->>MC: pbpaste
        MC-->>SSH: "current text"
        SSH-->>LOOP: "current text"

        alt Host clipboard changed
            LOOP->>SSH: Write to VM (pbcopy)
            SSH->>MC: pbcopy
            Note over MC: Cmd+V now has<br>the Linux text
        else VM clipboard changed
            LOOP->>HC: Write to host (xclip)
            Note over HC: Ctrl+V now has<br>the macOS text
        end
    end
```

### Why It Feels Instant

```mermaid
graph LR
    subgraph "Without ControlMaster"
        A1["Poll 1:<br>TCP handshake<br>SSH handshake<br>pbpaste<br>~200ms"] --> A2["Poll 2:<br>TCP handshake<br>SSH handshake<br>pbpaste<br>~200ms"]
    end

    subgraph "With ControlMaster (what vm-clip uses)"
        B1["Poll 1:<br>SSH handshake<br>(first time only)<br>pbpaste<br>~200ms"] --> B2["Poll 2:<br>reuse socket<br>pbpaste<br>~5ms"] --> B3["Poll 3:<br>reuse socket<br>pbpaste<br>~5ms"]
    end

    style A1 fill:#ff6b6b,color:#fff
    style A2 fill:#ff6b6b,color:#fff
    style B1 fill:#ffd43b,color:#000
    style B2 fill:#51cf66,color:#fff
    style B3 fill:#51cf66,color:#fff
```

### Commands

| Command | What it does |
|---------|-------------|
| `vm-clip sync` | Start background daemon — copies flow both directions automatically |
| `vm-clip push` | One-shot: host clipboard → VM |
| `vm-clip pull` | One-shot: VM clipboard → host |
| `vm-clip stop` | Kill the background sync |
| `vm-clip status` | Check if sync is running |

## Why Not Just Fork?

```mermaid
graph TB
    subgraph "Fork Approach (avoided)"
        FORK[Full fork of OSX-KVM<br>~100+ files, constant merge conflicts]
    end

    subgraph "Overlay Approach (this repo)"
        OVERLAY["9 files total<br>1 patch + 3 scripts + docs"]
        UPSTREAM2["Upstream stays pristine<br>Easy to update"]
    end

    FORK -.->|"❌ Merge conflicts<br>❌ Stale upstream<br>❌ 100+ files to manage"| BAD(["Maintenance nightmare"])
    OVERLAY -->|"✅ Clean separation<br>✅ Easy updates<br>✅ Minimal surface area"| GOOD(["Just works"])

    style BAD fill:#ff6b6b,color:#fff
    style GOOD fill:#51cf66,color:#fff
    style OVERLAY fill:#4a9eff,color:#fff
```

## File Relationship Map

How every file in the repo relates to every other file:

```mermaid
graph TD
    BS[bootstrap.sh] -->|reads| PATCH[patches/<br>OpenCore-Boot.sh.patch]
    BS -->|copies| SETUP[files/setup.sh]
    BS -->|copies| LAUNCHER[files/macos-launcher.sh]
    BS -->|copies| KVMCONF[files/kvm-macos.conf]
    BS -->|installs| VMCLIP[files/vm-clip]
    BS -->|runs| SETUP

    VMCLIP -->|installed to| VMCLIPBIN["~/.local/bin/<br>vm-clip"]
    VMCLIPBIN -->|"xclip"| HOSTCLIP["Linux clipboard"]
    VMCLIPBIN -->|"SSH → pbcopy/<br>pbpaste"| VMCLIPBOARD["macOS clipboard"]

    PATCH -->|modifies| OCBOOT["OSX-KVM/<br>OpenCore-Boot.sh"]

    SETUP -->|installs| KVMCONF2["/etc/modprobe.d/<br>kvm-macos.conf"]
    SETUP -->|downloads| BASE["OSX-KVM/<br>BaseSystem.img"]
    SETUP -->|creates| HDD["OSX-KVM/<br>mac_hdd_ng.img"]
    SETUP -->|creates| DESKTOP["~/.local/share/<br>applications/<br>macos-vm.desktop"]

    LAUNCHER -->|runs| OCBOOT
    OCBOOT -->|launches| QEMU["qemu-system-x86_64"]
    DESKTOP -->|launches| LAUNCHER

    KVMCONF -.->|"reference for"| KVMCONF2

    QEMU -->|loads| BASE
    QEMU -->|loads| HDD
    QEMU -->|loads| OC["OSX-KVM/<br>OpenCore/OpenCore.qcow2"]
    QEMU -->|loads| OVMF["OSX-KVM/<br>OVMF_*.fd"]

    style BS fill:#4a9eff,color:#fff
    style PATCH fill:#ff6b6b,color:#fff
    style QEMU fill:#51cf66,color:#fff
    style LAUNCHER fill:#ffd43b,color:#000
    style SETUP fill:#ffd43b,color:#000
    style VMCLIP fill:#b197fc,color:#fff
    style VMCLIPBIN fill:#b197fc,color:#fff
```

## Summary

| Layer | What | Files |
|-------|------|-------|
| **Config repo** | Your customizations, stored in git | `bootstrap.sh`, `patches/*`, `files/*` |
| **Upstream clone** | The full OSX-KVM toolkit (OpenCore, OVMF, scripts) | Cloned into `OSX-KVM/` at bootstrap time |
| **System config** | Kernel module params for KVM | `/etc/modprobe.d/kvm-macos.conf` |
| **Runtime** | QEMU process running macOS | `qemu-system-x86_64` launched by `macos-launcher.sh` |
| **Clipboard** | Bidirectional sync over SSH | `vm-clip sync` (polls xclip + pbcopy/pbpaste) |

The key insight: you only version-control **your changes** (the patch + helper scripts), not the entire upstream project. When upstream updates, you re-run bootstrap and the patch applies on top of the latest code.
