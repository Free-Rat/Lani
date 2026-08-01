# What each catalog service needs from the host, since the services container is
# re-imported wholesale on deploy. Consumed by nix/modules/services-container.nix.
#
#   secrets.<path in container> = <file under /var/lib/lani>   generated, mounted ro
#   state.<path in container>   = { dir; mode; }               created, mounted rw
#
# Only Nextcloud declares state: without user namespacing a persisted directory can end up
# owned by the wrong account if a rebuild shifts a service uid. See docs/catalog.md.
{
  nextcloud = {
    secrets."/etc/nextcloud-admin-pass" = "nextcloud-admin-pass";
    state."/var/lib/nextcloud" = {
      dir = "nextcloud-data";
      mode = "0700";
    };
  };
}
