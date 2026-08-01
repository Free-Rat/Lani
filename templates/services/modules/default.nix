# The only file shared between parallel feature branches. Imports, nothing else: add
# exactly one line. That keeps the worst case an add/add conflict on adjacent lines. Put
# logic here and simultaneous features start conflicting for real.
{
  imports = [
    ./example.nix
  ];
}
