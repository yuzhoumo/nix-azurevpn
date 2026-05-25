# nix-azurevpn

NixOS module for the [Microsoft Azure VPN Client](https://learn.microsoft.com/en-us/azure/vpn-gateway/point-to-site-entra-vpn-client-linux).

This module wraps the proprietary Microsoft Azure VPN client, sourced from the
official debian file. The module exposes both `azurevpnclient-unprivileged` and
the privileged `azurevpnclient` binaries.

### Unprivileged vs Privileged

The privileged binary `azurevpnclient` is a security wrapper that grants
`CAP_NET_ADMIN`, which is required for creating tun devices and establishing
VPN connections. However, running with elevated capabilities breaks the GUI
file picker, so the **Import** button will not work.

Use `azurevpnclient-unprivileged` if you need to import profiles via the
Import button in the GUI. Alternatively, use the `profileFile` option to
deploy profiles declaratively (see [Profile deployment](#profile-deployment)
below) and skip the Import button entirely.

## Usage

Add the flake input and import the module:

```nix
# flake.nix
{
  inputs.nix-azurevpn = {
    url = "github:yuzhoumo/nix-azurevpn";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-azurevpn, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        nix-azurevpn.nixosModules.default
        # ...
      ];
    };
  };
}
```

Enable in your NixOS configuration:

```nix
programs.azurevpn.enable = true;
```

## Options

| Option                           | Type           | Default         | Description                               |
|----------------------------------|----------------|-----------------|-------------------------------------------|
| `programs.azurevpn.enable`       | bool           | `false`         | Enable the Azure VPN Client.              |
| `programs.azurevpn.profileFile`  | string or null | `null`          | Path to a VPN profile XML file to deploy. |
| `programs.azurevpn.profileName`  | string         | `"profile.xml"` | Filename for the imported profile.        |
| `programs.azurevpn.profileUsers` | string list    | `[]`            | Users to receive the deployed profile.    |
| `programs.azurevpn.polkitGroup`  | string         | `"wheel"`       | Group allowed to manage DNS via polkit.   |

## Profile deployment

When `profileFile` is set, an activation script copies the XML into each
listed user's `~/.local/share/microsoft-azurevpnclient/profiles/` and
registers it in the Flutter client's `shared_preferences.json`.

Example with [sops-nix](https://github.com/Mic92/sops-nix):

```nix
sops.secrets.azure-vpn-profile = {
  sopsFile = ./secrets/azvpn-profile.xml;
  format = "binary";
};

programs.azurevpn = {
  enable = true;
  profileFile = config.sops.secrets.azure-vpn-profile.path;
  profileName = "MyVpnProfile.xml";
  profileUsers = [ "alice" ];
};
```
