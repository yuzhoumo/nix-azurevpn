# nix-azurevpnclient

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
  inputs.nix-azurevpnclient = {
    url = "github:yuzhoumo/nix-azurevpnclient";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-azurevpnclient, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        nix-azurevpnclient.nixosModules.default
        # ...
      ];
    };
  };
}
```

Enable in your NixOS configuration:

```nix
programs.azurevpnclient.enable = true;
```

## Options

| Option                                      | Type                     | Default         | Description                               |
|---------------------------------------------|--------------------------|-----------------|-------------------------------------------|
| `programs.azurevpnclient.enable`            | bool                     | `false`         | Enable the Azure VPN Client.              |
| `programs.azurevpnclient.profileFile`       | string or null           | `null`          | Path to a VPN profile XML file to deploy. |
| `programs.azurevpnclient.profileName`       | string                   | `"profile.xml"` | Filename for the imported profile.        |
| `programs.azurevpnclient.profileUsers`      | string list              | `[]`            | Users to receive the deployed profile.    |
| `programs.azurevpnclient.polkitGroup`       | string                   | `"wheel"`       | Group allowed to manage DNS via polkit.   |
| `programs.azurevpnclient.softwareRendering` | bool                     | `false`         | Force software rendering.                 |
| `programs.azurevpnclient.browser`           | package, string, or null | `null`          | Browser for interactive auth.             |

## Profile deployment

When `profileFile` is set, an activation script copies the XML into each
listed user's `~/.local/share/microsoft-azurevpnclient/profiles/` and
registers it in the Flutter client's `shared_preferences.json`.

Example with [sops-nix](https://github.com/Mic92/sops-nix):

```nix
sops.secrets.azurevpnclient-profile = {
  sopsFile = ./secrets/azvpn-profile.xml;
  format = "binary";
};

programs.azurevpnclient = {
  enable = true;
  profileFile = config.sops.secrets.azurevpnclient-profile.path;
  profileName = "MyVpnProfile.xml";
  profileUsers = [ "alice" ];
};
```

## WSL Compatability

Use the following settings for compatability with nixos-wsl.

```nix
# disable auto-generated resolv conf
wsl.wslConf.network.generateResolvConf = false;

# set default resolved dns to wsl endpoint, with cloudflare as fallback
networking.nameservers = [ "10.255.255.254" "1.1.1.1" ];

programs.azurevpnclient = {
  enable = true;

  # set browser to launch inside of WSL, otherwise client uses xdg-open, which
  # will route to the Windows host's browser for entra auth.
  browser = "firefox";

  # enable software rendering to fix blank window issue on WSL
  softwareRendering = true;
};
```
