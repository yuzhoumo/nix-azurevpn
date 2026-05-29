{
  description = "NixOS module for the Microsoft Azure VPN Client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules = rec {
      default = azurevpnclient;
      azurevpnclient = import ./module;
    };
  };
}
