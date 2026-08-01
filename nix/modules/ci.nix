# Host-side CI. Agents drop a tarball plus a `.req` marker into the queue; a path unit
# fires this service, which boots the tarball as an ephemeral machine, health-checks it,
# writes a result JSON and tears it down.
#
# Serial by design: two test containers would want the same machine name and bridge.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lani;
  ciDir = "/var/lib/lani-ci";
  machine = "lani-services-test";

  needs = import ../host-requirements.nix {
    inherit lib;
    activeModules = cfg.serviceHost.activeModules;
  };

  # In-repo, so the module set evaluates from a clean checkout.
  healthScript = pkgs.writeShellApplication {
    name = "lani-health";
    runtimeInputs = with pkgs; [
      systemd
      curl
      iproute2
      gnugrep
      gawk
      coreutils
      python3
    ];
    text = builtins.readFile ../../ci/health.sh;
  };

  # The test container needs the same files present or services fail to start and every
  # run reports a false red. Throwaway values; the real ones stay in /var/lib/lani.
  testSecretBinds = lib.concatMapStringsSep "\n" (
    s: "Bind=${ciDir}/secrets/${s.fileName}:${s.containerPath}"
  ) needs.secrets;

  seedTestSecrets = lib.concatMapStringsSep "\n" (s: ''
    if [ ! -s "$CI/secrets/${s.fileName}" ]; then
      head -c 18 /dev/urandom | base64 > "$CI/secrets/${s.fileName}"
      chmod 0600 "$CI/secrets/${s.fileName}"
    fi
  '') needs.secrets;

  ciOrchestrator = pkgs.writeShellApplication {
    name = "lani-ci";
    runtimeInputs = with pkgs; [
      systemd
      btrfs-progs
      e2fsprogs
      util-linux
      coreutils
      healthScript
    ];
    text = ''
      CI=${ciDir}
      Q="$CI/queue"
      R="$CI/results"
      M=${machine}

      install -d -m 0775 "$Q" "$R"
      install -d -m 0700 "$CI/secrets"
      ${seedTestSecrets}

      teardown() {
        machinectl stop "$M" 2>/dev/null || true
        sleep 2
        systemctl reset-failed "systemd-nspawn@$M.service" 2>/dev/null || true
        machinectl remove "$M" 2>/dev/null || true
        # /var/lib/machines may be a btrfs subvolume, and NixOS marks /var/empty
        # immutable, which blocks rm until cleared.
        btrfs subvolume delete "/var/lib/machines/$M" 2>/dev/null || true
        chattr -R -i "/var/lib/machines/$M" 2>/dev/null || true
        rm -rf "/var/lib/machines/$M" 2>/dev/null || true
      }

      shopt -s nullglob
      for req in "$Q"/*.req; do
        id="$(basename "$req" .req)"
        tar="$Q/$id.tar.xz"
        res="$R/$id.json"
        label="$(head -n1 "$req" 2>/dev/null || echo "$id")"
        echo "==> processing $id ($label)"
        status="error"
        detail="started"
        ip=""

        if [ ! -f "$tar" ]; then
          detail="tarball missing: $tar"
        else
          teardown
          if import_err="$(machinectl import-tar --force "$tar" "$M" 2>&1 1>/dev/null)"; then
            if machinectl start "$M"; then
              if ip="$(lani-health "$M" 180)"; then
                status="pass"
                detail="all health checks green"
              else
                status="fail"
                detail="health checks failed (inspect: journalctl -M $M)"
              fi
            else
              detail="machine failed to start (inspect: journalctl -u systemd-nspawn@$M)"
            fi
          else
            detail="import-tar failed: $(printf '%s' "$import_err" | tr '\n' ' ' | tr -d '"' | tail -c 200)"
          fi
          teardown
        fi

        printf '{"id":"%s","label":"%s","status":"%s","ip":"%s","detail":"%s","ts":"%s"}\n' \
          "$id" "$label" "$status" "$ip" "$detail" "$(date -Is)" > "$res.tmp"
        mv "$res.tmp" "$res"
        chmod 0664 "$res"
        rm -f "$req" "$tar"
        echo "==> $id -> $status ($detail)"
      done
    '';
  };
in
lib.mkIf (cfg.enable && cfg.serviceHost.enable) {

  # Group-writable: the workbench user enqueues from inside the container, same uid.
  systemd.tmpfiles.rules = [
    "d ${ciDir}         0775 root users - -"
    "d ${ciDir}/queue   0775 root users - -"
    "d ${ciDir}/results 0775 root users - -"
    "d ${ciDir}/logs    0775 root users - -"
    "d ${ciDir}/status  0775 root users - -"
    "d ${ciDir}/secrets 0700 root root  - -"
  ];

  environment.etc."systemd/nspawn/${machine}.nspawn".text = ''
    [Exec]
    Boot=on

    [Network]
    VirtualEthernet=yes
    Bridge=${cfg.serviceHost.bridge}

    [Files]
    ${testSecretBinds}
  '';

  systemd.paths.lani-ci = {
    description = "Watch the Lani CI queue for test requests";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExistsGlob = "${ciDir}/queue/*.req";
  };

  systemd.services.lani-ci = {
    description = "Process queued Lani CI test requests";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe ciOrchestrator;
    };
  };
}
