# Navidrome, Subsonic-compatible. Put files in /var/lib/navidrome/music, or bind-mount
# your library over it:
#
#   lani.serviceHost.extraBindMounts."/var/lib/navidrome/music".hostPath = "/srv/music";
{ ... }:
{
  lani.services.navidrome = {
    subdomain = "music";
    port = 4533;
    description = "Navidrome music server";
  };

  services.navidrome = {
    enable = true;
    settings = {
      Address = "127.0.0.1";
      Port = 4533;
      MusicFolder = "/var/lib/navidrome/music";
      EnableSharing = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/navidrome/music 0755 navidrome navidrome -"
  ];
}
