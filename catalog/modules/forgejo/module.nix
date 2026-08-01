# Forgejo. SQLite backend, no separate database. Registration is disabled — create your
# account through the first-run wizard, then invite people from the admin panel.
{ ... }:
{
  lani.services.forgejo = {
    subdomain = "git";
    port = 3030;
    description = "Forgejo git forge";
    proxyWebsockets = true; # live issue and pull-request updates
    maxBodySize = "512M"; # git push over HTTP
  };

  services.forgejo = {
    enable = true;
    settings = {
      server = {
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3030;
        DOMAIN = "git.local";
        ROOT_URL = "http://git.local/";
      };
      service.DISABLE_REGISTRATION = true;
    };
  };
}
