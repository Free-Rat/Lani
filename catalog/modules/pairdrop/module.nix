# Pairdrop. Open drop.local on two devices on the same network and they transfer
# directly. Nothing is uploaded or kept, hence no persistent state.
{ pkgs, ... }:
{
  lani.services.pairdrop = {
    subdomain = "drop";
    port = 8089;
    # Discovery and the handshake are WebSocket-based; without this nothing finds anything.
    proxyWebsockets = true;
    description = "Pairdrop local file sharing";
  };

  users.users.pairdrop = {
    isSystemUser = true;
    group = "pairdrop";
  };
  users.groups.pairdrop = { };

  systemd.services.pairdrop = {
    description = "Pairdrop local file sharing";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    environment.PORT = "8089";
    serviceConfig = {
      ExecStart = "${pkgs.pairdrop}/bin/pairdrop --localhost-only";
      User = "pairdrop";
      Group = "pairdrop";
      Restart = "on-failure";
      RestartSec = "5s";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
