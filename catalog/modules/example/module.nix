# The smallest catalog module, and a smoke test: if example.local serves this page, vhost
# generation, mDNS, the firewall and the health manifest are all working.
{ pkgs, ... }:
let
  backendPort = 8081;
  site = pkgs.runCommand "lani-example-site" { } ''
    mkdir -p $out
    cat > $out/index.html <<'HTML'
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>Lani — example site</title></head>
      <body style="font-family: system-ui; margin: 4rem auto; max-width: 40rem;">
        <h1>It works 🎉</h1>
        <p>Served by the Lani services container, reached at <code>example.local</code>.</p>
      </body>
    </html>
    HTML
  '';
in
{
  lani.services.example = {
    subdomain = "example";
    port = backendPort;
    description = "Example site";
  };

  services.nginx.virtualHosts."lani-example-site" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = backendPort;
      }
    ];
    root = site;
  };
}
