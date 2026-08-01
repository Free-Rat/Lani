# LUKS-encrypted home for the workbench user: three ordered, idempotent oneshots — key,
# image, unseal. The container is ordered after the unseal so it never mounts an empty
# directory over the real home.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lani;
  lk = cfg.lukshome;
  mapper = "lani-home";

  # No user namespacing, so these are host uids too. NixOS gives the first normal user
  # 1000 and `users` is 100; matching that is what makes the home belong to the account.
  ownerUid = 1000;
  ownerGid = 100;
in
lib.mkIf (cfg.enable && cfg.shell.enable && lk.enable) {

  systemd.tmpfiles.rules = [
    "d ${builtins.dirOf lk.imagePath} 0711 root root - -"
    "d ${lk.mountPoint} 0700 root root - -"
  ];

  systemd.services.lani-luks-key = {
    description = "Generate the LUKS key for the workbench home";
    before = [ "lani-luks-create.service" ];
    requiredBy = [ "lani-luks-create.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      key=${lib.escapeShellArg lk.keyPath}
      if [ ! -f "$key" ]; then
        install -m 0400 /dev/null "$key"
        dd if=/dev/urandom bs=64 count=1 of="$key" 2>/dev/null
        echo "lani: generated LUKS key at $key — back this up, there is no recovery"
      fi
    '';
  };

  systemd.services.lani-luks-create = {
    description = "Create the workbench LUKS home image";
    after = [
      "lani-luks-key.service"
      "local-fs.target"
    ];
    before = [ "lani-luks-open.service" ];
    requiredBy = [ "lani-luks-open.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.cryptsetup
      pkgs.e2fsprogs
      pkgs.util-linux
    ];
    script = ''
      img=${lib.escapeShellArg lk.imagePath}
      key=${lib.escapeShellArg lk.keyPath}
      if [ ! -f "$img" ]; then
        echo "lani: allocating ${toString lk.imageSizeGB}G image…"
        dd if=/dev/zero bs=1M count=${toString (lk.imageSizeGB * 1024)} of="$img" status=progress
        cryptsetup luksFormat --batch-mode --key-file "$key" "$img"
        cryptsetup luksOpen --key-file "$key" "$img" ${mapper}-init
        mkfs.ext4 -L ${mapper} /dev/mapper/${mapper}-init
        mkdir -p /mnt/lani-init
        mount /dev/mapper/${mapper}-init /mnt/lani-init
        install -d -o ${toString ownerUid} -g ${toString ownerGid} -m 0700 \
          /mnt/lani-init/${cfg.user}
        umount /mnt/lani-init
        cryptsetup luksClose ${mapper}-init
        echo "lani: LUKS home image created at $img"
      fi
    '';
  };

  systemd.services.lani-luks-open = {
    description = "Unseal the workbench LUKS home";
    after = [
      "lani-luks-create.service"
      "local-fs.target"
    ];
    before = [ "container@lani-shell.service" ];
    requiredBy = [ "container@lani-shell.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = pkgs.writeShellScript "lani-luks-seal" ''
        mountpoint -q ${lib.escapeShellArg lk.mountPoint} && \
          umount ${lib.escapeShellArg lk.mountPoint} || true
        [ -e /dev/mapper/${mapper} ] && \
          ${pkgs.cryptsetup}/bin/cryptsetup luksClose ${mapper} || true
      '';
    };
    path = [
      pkgs.cryptsetup
      pkgs.util-linux
    ];
    script = ''
      if [ ! -e /dev/mapper/${mapper} ]; then
        cryptsetup luksOpen \
          --key-file ${lib.escapeShellArg lk.keyPath} \
          ${lib.escapeShellArg lk.imagePath} ${mapper}
      fi
      mountpoint -q ${lib.escapeShellArg lk.mountPoint} || \
        mount /dev/mapper/${mapper} ${lib.escapeShellArg lk.mountPoint}
    '';
  };
}
