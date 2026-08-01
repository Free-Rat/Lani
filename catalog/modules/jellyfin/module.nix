# Jellyfin. The setup wizard asks for a library path; point it at a directory you
# bind-mounted in:
#
#   lani.serviceHost.extraBindMounts."/media".hostPath = "/srv/media";
{ ... }:
{
  lani.services.jellyfin = {
    subdomain = "jellyfin";
    port = 8096;
    proxyWebsockets = true; # playback session and SyncPlay messages
    maxBodySize = "1G"; # subtitle and artwork uploads
    description = "Jellyfin media server";
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false; # the platform owns the firewall
  };
}
