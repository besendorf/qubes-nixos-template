{
  config,
  lib,
  pkgs,
  ...
}: {
  # Pin the compatibility baseline used when this template was introduced.
  system.stateVersion = "26.05";

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
    };
  };

  hardware.graphics.enable = true;

  environment.systemPackages = with pkgs; [
    xterm
  ];
}
