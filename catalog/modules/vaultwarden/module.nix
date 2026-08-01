# Vaultwarden. TLS is not optional: browsers only expose the Web Crypto API in a secure
# context, so over plain http the web vault loads and then refuses to unlock.
#
# To create the first account, flip SIGNUPS_ALLOWED on, register, and flip it back.
{ ... }:
{
  lani.services.vaultwarden = {
    subdomain = "vaultwarden";
    port = 8222;
    tls = true;
    proxyWebsockets = true; # live sync between clients
    description = "Vaultwarden password manager";
  };

  services.vaultwarden = {
    enable = true;
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      DOMAIN = "https://vaultwarden.local";
      SIGNUPS_ALLOWED = false;
      DATA_FOLDER = "/var/lib/vaultwarden";
      LOG_LEVEL = "warn";
    };
  };
}
