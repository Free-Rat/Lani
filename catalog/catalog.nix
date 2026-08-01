# What `lani modules list` shows. `subdomain` and `port` are duplicated from the module
# on purpose: this has to be readable without evaluating a NixOS system. The
# catalog-consistency check keeps the copies honest.
[
  {
    name = "nextcloud";
    description = "Personal cloud storage, file sync and calendars";
    subdomain = "nextcloud";
    port = 8080;
  }
  {
    name = "vaultwarden";
    description = "Bitwarden-compatible password manager (served over TLS)";
    subdomain = "vaultwarden";
    port = 8222;
  }
  {
    name = "jellyfin";
    description = "Media server for your own film and TV library";
    subdomain = "jellyfin";
    port = 8096;
  }
  {
    name = "uptime-kuma";
    description = "Status dashboard showing which services are up";
    subdomain = "status";
    port = 3001;
  }
  {
    name = "forgejo";
    description = "Git forge with issues and pull requests";
    subdomain = "git";
    port = 3030;
  }
  {
    name = "navidrome";
    description = "Music streaming from your own library, Subsonic-compatible";
    subdomain = "music";
    port = 4533;
  }
  {
    name = "pairdrop";
    description = "Direct file transfer between devices on the network";
    subdomain = "drop";
    port = 8089;
  }
  {
    name = "example";
    description = "A static page — the smallest example module, and a smoke test";
    subdomain = "example";
    port = 8081;
  }
]
