{ config, lib, pkgs, ... }:

let
  cfg = config.programs.azurevpn;
  azureVpnPackage = import ./package.nix {
    inherit pkgs;
    inherit (cfg) softwareRendering;
  };
in
{
  options.programs.azurevpn = {
    enable = lib.mkEnableOption "Microsoft Azure VPN Client";

    profileFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to an Azure VPN client connection profile XML file.
        When set, the profile is copied into each profile user's
        ~/.local/share/microsoft-azurevpnclient/profiles/ directory
        so the client picks it up on launch.
      '';
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "profile.xml";
      description = ''
        Filename for the imported VPN profile.
      '';
    };

    profileUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of usernames whose Azure VPN client profile directories
        should be populated with the connection profile.
      '';
    };

    polkitGroup = lib.mkOption {
      type = lib.types.str;
      default = "wheel";
      description = ''
        Unix group whose members may control systemd-resolved via polkit,
        required for Azure VPN Client DNS management.
      '';
    };

    softwareRendering = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Force software rendering for the Flutter-based client by setting
        GALLIUM_DRIVER=llvmpipe and LIBGL_ALWAYS_SOFTWARE=1 in its wrapper
        only. Works around the blank-window failure on WSLg, where EGL
        cannot initialize a usable GL implementation ("Failed to start
        Flutter renderer: No GL implementation is available").
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ azureVpnPackage pkgs.zenity ];

    services.resolved.enable = true;

    # Security wrapper to grant CAP_NET_ADMIN for tun device creation
    security.wrappers.azurevpnclient = {
      source = "${azureVpnPackage}/bin/azurevpnclient-unprivileged";
      owner = "root";
      group = "root";
      capabilities = "cap_net_admin+eip";
    };

    # Polkit rule to allow the VPN client to manage DNS via resolved
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (
          action.id.indexOf("org.freedesktop.resolve1.") == 0 &&
          subject.isInGroup("${cfg.polkitGroup}")
        ) { return polkit.Result.YES; }
      });
    '';

    # DigiCert root CA required for Azure VPN server validation
    environment.etc."ssl/certs/DigiCert_Global_Root_G2.pem".source =
      pkgs.runCommand "azurevpn-digicert-global-root-g2.pem" { } ''
        sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
          ${pkgs.cacert.unbundled}/etc/ssl/certs/DigiCert_Global_Root_G2:33af1e6a711a9a0bb2864b11d09fae5.crt > "$out"
      '';

    # Deploy VPN profile and register it in the Flutter client's preferences
    system.activationScripts.azurevpn-profile = lib.mkIf (cfg.profileFile != null) {
      deps = [ "setupSecrets" ];
      text = let
        xmllint = "${pkgs.libxml2}/bin/xmllint";
        jq = "${pkgs.jq}/bin/jq";
        deployProfile = pkgs.writeShellScript "azurevpn-deploy-profile" ''
          PROFILE_SRC="$1"
          PROFILE_NAME="$2"
          DATA_DIR="$3"
          CONFIG_DIR="$4"
          OWNER="$5"

          PROFILE_DIR="$DATA_DIR/profiles"
          CONFIG_PROFILE_DIR="$CONFIG_DIR/profiles"
          PREFS="$DATA_DIR/shared_preferences.json"
          XML="$PROFILE_DIR/$PROFILE_NAME"

          # Query XML text node by slash-delimited local-name path
          xpath() {
            local expr="" first=true part
            for part in $(echo "$1" | tr '/' ' '); do
              if $first; then expr="//*[local-name()='$part']"; first=false
              else expr="$expr/*[local-name()='$part']"; fi
            done
            ${xmllint} --xpath "$expr/text()" "$XML" 2>/dev/null || true
          }

          mkdir -p "$PROFILE_DIR" "$CONFIG_PROFILE_DIR"
          cp -f "$PROFILE_SRC" "$XML"

          # Extract connection metadata from profile XML
          name=$(xpath "AzVpnProfile/name")
          auth=$(xpath "clientauth/type")
          tenant=$(xpath "aad/tenant")
          audience=$(xpath "aad/audience")
          issuer=$(xpath "aad/issuer")
          secret=$(xpath "serversecret")
          hash=$(xpath "Cert/hash")
          fqdn=$(${xmllint} --xpath \
            "//*[local-name()='serverlist']/*[local-name()='ServerEntry'][1]/*[local-name()='fqdn']/text()" \
            "$XML" 2>/dev/null || true)

          count=$(${xmllint} --xpath \
            "count(//*[local-name()='ServerEntry'])" \
            "$XML" 2>/dev/null || echo "1")
          if [ "$count" -gt 1 ] 2>/dev/null; then ha="true"; else ha="false"; fi

          # Build Flutter shared_preferences entry for this VPN profile
          entry="{server_name: $name, fqdn: $fqdn,"
          entry+=" profile_file_path: $XML,"
          entry+=" profile_file_name: $PROFILE_NAME,"
          entry+=" server_secret: $secret,"
          entry+=" auth_type: $auth,"
          entry+=" tenant: $tenant,"
          entry+=" audience: $audience,"
          entry+=" issuer: $issuer,"
          entry+=" cert_hash: $hash,"
          entry+=" cert_public_data_file_path: ,"
          entry+=" cert_public_data_file_name: ,"
          entry+=" cert_private_key_file_path: ,"
          entry+=" cert_private_key_file_name: ,"
          entry+=" is_highly_available: $ha,"
          entry+=" last_logged_user: , msal_cache: ,"
          entry+=" cert_passphrase: , profile_data: ,"
          entry+=" status: }"

          if [ -f "$PREFS" ]; then
            ${jq} --arg entry "$entry" --arg pfn "$PROFILE_NAME" \
              '."flutter.profiles" = ([
                ."flutter.profiles"[]?
                | select(contains($pfn) | not)
              ] + [$entry])' \
              "$PREFS" > "$PREFS.tmp" && mv "$PREFS.tmp" "$PREFS"
          else
            ${jq} -n --arg entry "$entry" \
              '{"flutter.profiles": [$entry]}' > "$PREFS"
          fi

          cp -f "$XML" "$CONFIG_PROFILE_DIR/$name"
          chown -R "$OWNER:$(id -gn "$OWNER")" "$DATA_DIR" "$CONFIG_DIR"
        '';
      in lib.concatMapStringsSep "\n" (user: let
        home = config.users.users.${user}.home;
      in ''
        ${deployProfile} \
          "${cfg.profileFile}" \
          "${cfg.profileName}" \
          "${home}/.local/share/microsoft-azurevpnclient" \
          "${home}/.config/microsoft-azurevpnclient" \
          "${user}"
      '') cfg.profileUsers;
    };
  };
}
