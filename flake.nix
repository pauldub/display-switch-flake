{
  description = "A very basic flake";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    display-switch.url = "github:haimgel/display-switch";
    display-switch.flake = false;
  };

  outputs = { self, nixpkgs, flake-utils, display-switch, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
          rec {
            packages.display-switch = pkgs.rustPlatform.buildRustPackage rec {
              pname = "display-switch";
              version = "master";

              src = display-switch;

              cargoSha256 = "sha256-msjbhcKmovGWLlCiqLvZSqwQKYFOfAW15lEuFhqISzI=";
              doCheck = false;

              nativeBuildInputs = [ pkgs.pkgconfig ];

              buildInputs = [ pkgs.libudev ];
            };

            overlay = final: prev: { display-switch = packages.display-switch; };
          }
    ) // {
      nixosModule = { config, lib, pkgs, ... }:
        let
          inherit (lib) mkEnableOption mkOption types mkIf generators;

          monitorOptions = {
            options = {
              monitorId = mkOption {
                type = types.either types.str types.int;
                description = "ID or substring of the monitor name";
              };

              onUsbConnect = mkOption {
                type = types.nullOr types.str;
                default = null;
                description =
                  "DCC/IC output to enable when the usb device is connected";
              };

              onUsbDisconnect = mkOption {
                type = types.nullOr types.str;
                default = null;
                description =
                  "DCC/IC output to enable when the usb device is disconnected";
              };
            };
          };

          mkMonitorConfig = name: monitor: ''
            [${name}]
            monitor_id = "${builtins.toString monitor.monitorId}"
            ${if monitor.onUsbConnect != null then
            ''on_usb_connect = "${monitor.onUsbConnect}"''
          else
            ""}

            ${if monitor.onUsbDisconnect != null then
            ''on_usb_disconnect = "${monitor.onUsbDisconnect}"''
          else
            ""}
          '';

          cfg = config.services.display-switch;
        in
          {
            options = {
              services.display-switch = {
                enable = mkEnableOption "Enable display-switch service";

                usbDevice = mkOption {
                  type = types.str;
                  description =
                    "ID of the USB device that will be monitored by display-switch";
                };

                onUsbConnect = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description =
                    "DCC/IC output to enable when the usb device is connected";
                };

                onUsbDisconnect = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description =
                    "DCC/IC output to enable when the usb device is disconnected";
                };

                monitors = mkOption {
                  type = types.attrsOf (types.submodule monitorOptions);
                  description = "Monitor specific configuration overrides";
                };
              };
            };

            config = mkIf cfg.enable {
              nixpkgs.overlays = [ self.overlay."${config.nixpkgs.system}" ];

              boot.kernelModules = [ "i2c_dev" ];

              services.udev.extraRules = ''
                KERNEL=="i2c-[0-9]*", TAG+="uaccess"
              '';

              environment.etc."display-switch/display-switch.ini".text = ''
                usb_device = "${cfg.usbDevice}"

                ${if cfg.onUsbConnect != null then
                ''on_usb_connect = "${cfg.onUsbConnect}"''
              else
                ""}

                ${if cfg.onUsbDisconnect != null then
                ''on_usb_disconnect = "${cfg.onUsbDisconnect}"''
              else
                ""}

                ${lib.concatStringsSep "\n"
                (lib.mapAttrsToList mkMonitorConfig cfg.monitors)}
              '';

              systemd.services.display-switch = {
                description = "display-switch";

                partOf = [ "graphical.target" ];
                wantedBy = [ "graphical.target" ];

                environment = { XDG_CONFIG_HOME = "/etc"; };

                script = "${pkgs.display-switch}/bin/display_switch";
              };
            };
          };
    };
}
