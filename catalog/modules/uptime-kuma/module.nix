# Uptime Kuma. Create the admin account on first visit, then add a monitor per
# `<name>.local` URL.
{ ... }:
{
  # Attribute name matches the catalog name; the hostname is status.local.
  lani.services.uptime-kuma = {
    subdomain = "status";
    port = 3001;
    proxyWebsockets = true; # the dashboard is entirely socket.io driven
    description = "Uptime Kuma status dashboard";
  };

  services.uptime-kuma = {
    enable = true;
    settings = {
      HOST = "127.0.0.1";
      PORT = "3001";
    };
  };
}
