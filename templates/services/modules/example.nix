# A feature module, and the shape every other one takes. One `lani.services.<name>`
# declaration is the whole integration; everything else is just the app.
{ pkgs, ... }:
let
  backendPort = 8081;
  site = pkgs.runCommand "example-site" { } ''
    mkdir -p $out
    cat > $out/index.html <<'HTML'
    <!doctype html>
    <html lang="en">
      <head><meta charset="utf-8"><title>It works</title></head>
      <body style="font-family: system-ui; margin: 4rem auto; max-width: 40rem;">
        <h1>It works 🎉</h1>
        <p>Served from <code>modules/example.nix</code> at <code>example.local</code>.</p>
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

  # Loopback: the platform's proxy is the only public door.
  services.nginx.virtualHosts."example-site" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = backendPort;
      }
    ];
    root = site;
  };
}
