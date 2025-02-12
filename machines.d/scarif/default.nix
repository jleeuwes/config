{ komputiloj, privata, hello-infra, nixpkgsCurrent, nixpkgsFuture, ... }:
rec {
    targetHost = "scarif.radstand.nl";
    inherit (privata.machines.scarif) masterAgeKey;
    sshPublicKeys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFN+m0J0mjJBDho4cTqt9OlnbMUtYuj6OacT7VWi/ahC";
    nixosSystem = nixpkgsCurrent.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ mainModule ];
    };

    mainModule = { config, pkgs, lib, ... }: {
        # We need to construct our own NIX_PATH, because the default becomes very weird with our scheme.
        # Also, make sure you don't have a ~/.nix-defexpr because that gets added
        # too (see /etc/set-environment).
        nix.nixPath = [
            # Don't do ${<nixpkgs>}, because that makes a weird non-working copy of
            # our sources.nix in the nix-store. With toString the literal path is
            # used instead.
            "nixpkgs=${nixpkgsCurrent}"
        ];
        
        # Get rid of dependency on whole nixpkgs source tree (400MB)
        nix.registry = lib.mkForce {};

        nixpkgs.overlays = [
            komputiloj.overlays.undesired-packages
        ];

        imports = [
            ./hardware-configuration.nix
            komputiloj.modules.ssh-client-config
        ];
        

        # Use the systemd-boot EFI boot loader.
        boot.loader.systemd-boot.enable = true;
        boot.loader.efi.canTouchEfiVariables = true;

        # Make /tmp in-memory:
        boot.tmp.useTmpfs = true;

        # Enable read-write NTFS support:
        boot.supportedFilesystems = [ "ntfs" ];

        networking = {
            hostName = "scarif";
            wireless = {
                enable = true;  # Enables wireless support via wpa_supplicant.
                interfaces = [ "wlp4s0" ];
                # Netwerken staan in /etc/wpa_supplicant.conf vanwege passphrases
            };
            nameservers = [ "1.1.1.1" "8.8.8.8" ];
            hosts = {
                # "ip.ad.dr.es" = [ "domain.name" ];
            };
        };

        # Select internationalisation properties.
        console = {
            font = "Lat2-Terminus16";
            keyMap = "us";
        };
        i18n = {
            defaultLocale = "nl_NL.UTF-8";
        };

        # Set your time zone.
        time.timeZone = "Europe/Amsterdam";

        environment.systemPackages = with pkgs; [
            zathura # pdf viewer
            vlc

            inkscape gimp
            libreoffice
            audacity
            
            zip unzip
        ];

        programs.firefox = {
            enable = true;

            # TODO configure search engines

            languagePacks = [ "nl" "en-US" ];

            policies = {
                # https://mozilla.github.io/policy-templates/
                ExtensionSettings = {
                    "*" = {
                        blocked_install_message = "Vraag dit even aan Jeroen :)";
                        installation_mode = "blocked";
                    };
                    "gdpr@cavi.au.dk" = {
                        # TODO figure out how to do updates and/or pinning
                        install_url = "https://addons.mozilla.org/firefox/downloads/latest/consent-o-matic/latest.xpi";
                        installation_mode = "force_installed";
                    };
                    # ublock origin is included with librewolf,
                    # but they use Extensions for that, and apparently
                    # having an ExtensionSettings policy overrides that
                    # completely. So we need to have ublock here.
                    "uBlock0@raymondhill.net" = {
                        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
                        installation_mode = "force_installed";
                    };
                };
            };
        };

        programs.thunderbird = {
            enable = true;
        };

        programs.gnupg.agent = {
            enable = true;
            enableSSHSupport = true;
            pinentryPackage = pkgs.pinentry-gtk2;
        };

        # Generate setuid wrappers for pmount:
        security.wrappers = {
            pmount = {
                source  = "${pkgs.pmount}/bin/pmount";
                setuid = true;
                owner = "root";
                group = "root";
            };
            pumount = {
                source = "${pkgs.pmount}/bin/pumount";
                setuid = true;
                owner = "root";
                group = "root";
            };
        };

        # List services that you want to enable:
        

        # Set this to true if you want to cast with chromium,
        # in combination with enabling
        # chrome://flags/#load-media-router-component-extension and
        # chrome://flags/#cast-media-route-provider
        # Note that cupsd spams the log if this is true, so disable if not used.
        # (See https://github.com/NixOS/nixpkgs/issues/195090)
        services.avahi.enable = false;

        # Enable the OpenSSH daemon.
        services.openssh.enable = true;
        programs.ssh = {
            knownHosts = {
                "[u362967.your-storagebox.de]:23" = {
                    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
                };
            };
        };

        # Enable CUPS and printing.
        # Add the Canon TR7500 printer using:
        #   lpadmin -p kantoor -v ipp://192.168.1.44:631/ipp/print -E -m everywhere
        # (Don't forget to make the IP fixed in the router config!)
        # Then further configure it at http://localhost:631/printers/kantoor
        # 
        # I used https://wiki.debian.org/CUPSDriverlessPrinting to get this stuff
        # working; I had to use the IP address in the URI instead of using the
        # dnssd://... detected by the CUPS web interface or the name-based ipp://...
        # detected by ippfind
        services.printing.enable = true;
        
        # enable gvfs to have ftp support etcetera in thunar
        # (doesn't work; maybe use
        # https://github.com/NixOS/nixpkgs/blob/release-19.09/nixos/modules/services/x11/desktop-managers/xfce.nix
        # ?)
        # services.gvfs.enable = true;
        # services.gvfs.package = pkgs.xfce.gvfs;
        
        # Enable sound with pipewire
        hardware.pulseaudio.enable = false;
        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          # If you want to use JACK applications, uncomment this
          #jack.enable = true;

          # use the example session manager (no others are packaged yet so this is enabled by default,
          # no need to redefine it in your config for now)
          #media-session.enable = true;
        };

        hardware.bluetooth = {
            enable = true;
        };

        # Screen locker
        services.xserver.enable = true;
        services.displayManager = {
            sddm = {
                enable = true;
            };
        };
        services.desktopManager.plasma6.enable = true;

        # Enable adb group and udev rules and such:
        programs.adb.enable = true;

        users.users.root = {
            openssh.authorizedKeys.keys = [
                # Always have a key here, otherwise we can't deploy.
                komputiloj.users.jeroen.sshKeys.ferrix
            ];
            
        };
        # Define a user account. Don't forget to set a password with ‘passwd’.
        users.extraUsers.jeroen = {
            uid = komputiloj.users.jeroen.linux.uid;
            isNormalUser = true;
            description = komputiloj.users.jeroen.fullName;
            extraGroups = [ "wheel" "network-manager" "dialout" "adbusers" "video" "audio" ];
        };
        users.users.karin = {
            uid = hello-infra.users.karin.linux.uid;
            isNormalUser = true;
            description = hello-infra.users.karin.fullName;
        };

        # The NixOS release to be compatible with for stateful data such as databases.
        system.stateVersion = "16.09";
    };
}
