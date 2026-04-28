# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

The repo currently contains only `README.md` (written in Catalan). No scripts have been implemented yet — the README is a specification, not documentation of existing code. When working here you are usually creating the scripts it describes, not modifying them.

Match the language of existing artifacts: README, comments, and user-facing prompts/messages are written in **Catalan**. Variable names and code identifiers stay in English.

## Planned architecture

Two shell scripts that work together. Keep them as two separate scripts — they run in different contexts (host machine vs. inside/against the Mikrotik router) and have different prerequisites.

### Script 1 — VirtualBox host setup

Runs on the host. Targets the `VBoxManage` CLI. Responsibilities:

1. Download the Mikrotik CHR `.ova` (longTerm). The README pins **7.21.4** (`https://download.mikrotik.com/routeros/7.21.4/chr-7.21.4.ova`) — treat the version as a single configurable constant near the top of the script so it is easy to bump.
2. Import the `.ova` into VirtualBox.
3. Rename the imported VM to **`m00`** (the default after import is `mv`).
4. Add a **second** NIC (the OVA ships with only one). Attach it to a VirtualBox **internal network** also named **`m00`**. This second NIC is the LAN side; the first NIC remains the WAN/management side and gets a DHCP lease from the host network.
5. Start the VM.

### Script 2 — Mikrotik configuration

Runs after the VM is up. The Mikrotik's first NIC takes a DHCP address from the surrounding network, so the IP is not known in advance. Discovery approach (per README):

- `nmap` the local subnet **before and after** booting the VM and diff the results, matching against the VM's NIC MAC address (queryable via `VBoxManage showvminfo`) to pin down the new host.

Configuration is delivered either as Mikrotik `.rsc` scripts pushed over SSH, or as direct commands over SSH — both are acceptable per the spec.

First-login quirk: the very first `admin` login on a fresh CHR **requires setting a new password** before any other command will run. The script must handle this interactive step (e.g. via `sshpass` + an `expect`-style flow, or by sending the password-set command as part of the initial session).

Configuration steps the script must apply, in this order:

1. Set system identity (name) to **`m00`**.
2. Create user **`salvadorrueda`** with full permissions and **no password** (SSH-key auth only).
3. Install the operator's SSH public key for `salvadorrueda`. Look for `~/.ssh/id_rsa.pub` first, then `~/.ssh/id_ed25519.pub`. If neither exists, prompt the user for a key path or offer to generate a new keypair.
4. **Disable** the `admin` account (do this *after* the new user + key are working — otherwise you lock yourself out).
5. Change SSH port to **2222**.
6. Disable every IP service except SSH (`/ip service disable telnet,ftp,www,api,winbox,api-ssl,www-ssl`).
7. Restrict SSH availability to **the first 10 minutes after boot**. The standard idiom is a scheduler entry on `startup` that disables the SSH service after a 10-minute delay.

The "disable admin last, change port last, time-limit SSH last" sequencing matters: getting it wrong locks you out of the VM and the only recovery is reimporting from `.ova`.

## Conventions

- VM name, internal-network name, and Mikrotik system identity are all **`m00`** — keep them in sync.
- Operator username is **`salvadorrueda`**; SSH port is **2222**; these are not configurable knobs, they are project constants per the README.
- Prefer idempotent scripts where feasible (re-running should not double-add NICs, duplicate users, etc.) — the workflow of "download, import, configure" is naturally one-shot, but failures mid-way are common, so guard each step with a check.
