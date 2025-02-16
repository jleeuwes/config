{ komputiloj, hello-infra, nixpkgsCurrent, nixpkgsFuture, ... }:
rec {
    nixosSystem = nixpkgsCurrent.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ mainModule ];
    };

    mainModule = { config, pkgs, lib, ... }: {
        # # Add the --option extra-builtins-file to nix
        # # using a magic spell from https://elvishjerricco.github.io/2018/06/24/secure-declarative-key-management.html
        # (Doesn't work: warning: ignoring the user-specified setting 'extra-builtins-file', because it is a restricted setting and you are not a trusted user)
        # nix.extraOptions = ''
        #     plugin-files = ${pkgs.nix-plugins.override { nix = config.nix.package; }}/lib/nix/plugins/libnix-extra-builtins.so
        # '';
        
        # We need to construct our own NIX_PATH, because the default becomes very weird with our scheme.
        # Also, make sure you don't have a ~/.nix-defexpr because that gets added
        # too (see /etc/set-environment).
        nix.nixPath = [
            # Don't do ${<nixpkgs>}, because that makes a weird non-working copy of
            # our sources.nix in the nix-store. With toString the literal path is
            # used instead.
            "nixpkgs=${nixpkgsCurrent}"
            # I don't think we need these during normal operation:
            # "komputiloj=${builtins.toString <komputiloj>}"
            # "nixos-config=${builtins.toString <nixos-config>}"
        ];
        nix.settings = {
            experimental-features = [ "nix-command" "flakes" ];
        };

        nixpkgs.config = {
            # Selectively allow some unfree packages
            # - https://nixos.org/nixpkgs/manual/#sec-allow-unfree
            allowUnfreePredicate = pkg:
                builtins.elem (lib.getName pkg) [
                    "steam"
                    "steam-unwrapped"
                    "steam-run"
                    "steam-original"
                    "android-studio"
                ];
        };
        nixpkgs.overlays = [
            komputiloj.overlays.undesired-packages
        ];

        imports =
            [
                ./hardware-configuration.nix
                # willen we waarschijnlijk niet as-is: komputiloj.modules.dekstopomveging
                komputiloj.modules.ssh-client-config
                komputiloj.modules.librewolf
                komputiloj.modules.apple-superdrive
                komputiloj.modules.build-for-raspberry
            ];
  
        # override some stuff from hardware-configuration:
        fileSystems."/" = {
            options = [ "compress=lzo" ];
        };

        # Hibernation config
        # based on https://wiki.archlinux.org/title/Dm-crypt/Swap_encryption#Using_a_swap_file
        # and https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Configure_the_initramfs
        # Note that there is some talk about systemd hibernate not needing a
        # manual resumeOffset when using EFI, but it turns out we actually do need this.
        # Maybe that is something Arch-specific.
        fileSystems."/swap" = {
            device = "/dev/disk/by-uuid/4c1ae7fa-0093-4c6a-8713-c64965d831b0";
            fsType = "btrfs";
            # Created by mounting the top-level btrfs device (NOT subvolume @)
            # and running `btrfs create subvolume @swap` inside.
            options = [ "subvol=@swap" ];
        };
        swapDevices = [{
            # TODO ideally only swapon just before hibernating;
            # we don't actually want swap during normal operation
            device = "/swap/swapfile";
        }];
        boot.resumeDevice = "/dev/disk/by-uuid/4c1ae7fa-0093-4c6a-8713-c64965d831b0";
        # offset determined with `sudo btrfs inspect-internal map-swapfile -r /swap/swapfile`
        boot.kernelParams = [ "resume_offset=15139505" ];
        # TODO disable suspend, make hibernate the default lid action,
        # enable auto-login.
        # TODO maybe put this hibernation stuff in a neat little module.

        # Make sure ~/bin is added to PATH:
        environment.homeBinInPath = true;
        
        boot.loader.timeout = 2;
        # Use the systemd-boot EFI boot loader.
        boot.loader.systemd-boot = {
            enable = true;
            configurationLimit = 10;
            # editor = false; # TODO it is recommended to set this to false
        };
        boot.loader.efi.canTouchEfiVariables = true;

        systemd.sleep.extraConfig = ''
            AllowSuspend=no
            AllowHibernation=yes
            AllowHybridSleep=no
            AllowSuspendThenHibernate=no
        '';

        # Make /tmp in-memory:
        boot.tmp.useTmpfs = true;

        # Enable read-write NTFS support:
        boot.supportedFilesystems = [ "ntfs" ];

        networking = {
            hostName = "ferrix";
            networkmanager.enable = true; # wireless through GUI
            # wireless = {
            #     enable = true;  # Enables wireless support via wpa_supplicant.
            #     # interfaces = [ "wlp4s0" ];
            #     # Netwerken staan in /etc/wpa_supplicant.conf vanwege passphrases
            #     # TODO use declarative networking in combination with a secret environmentFile
            # };
            nameservers = [ "1.1.1.1" "8.8.8.8" ];
            hosts = {
                # "ip.ad.dr.es" = [ "domain.name" ];
            };
        };

        # Select internationalisation properties.
        console = {
            # font = "Lat2-Terminus16";
            keyMap = "us";
        };
        i18n = {
            defaultLocale = "nl_NL.UTF-8";
            supportedLocales = [
                "C.UTF-8/UTF-8"
                "en_US.UTF-8/UTF-8"
                "nl_NL.UTF-8/UTF-8"
                "nl_BE.UTF-8/UTF-8"
            ];
        };

        # Set your time zone.
        time.timeZone = "Europe/Amsterdam";

        fonts = {
            enableDefaultPackages = true;
            packages = [
                pkgs.dejavu_fonts
                pkgs.ubuntu_font_family
            ];
        };

        # List packages installed in system profile. To search by name, run:
        # $ nix-env -qaP | grep wget
        environment.systemPackages = with pkgs; [
            
            # enhance nix-build
            nix-output-monitor

            # gaming
            # (steam is installed through programs.steam)
            lutris

            # usefull programs:
            mkpasswd
            unicode-paracode
            gitFull vim file subversionClient pciutils pmount squashfsTools
            parted gparted
            wget rtorrent
            git-annex git-annex-remote-rclone rclone
            sshpass
            gnupg paperkey qrencode zbar pwgen
            komputiloj.packages.wachtwoord
            inetutils # for ftp for the nas
            openssl
            nmap
            tree
            # losslesscut-bin # simpele videobewerking

            # pamix pavucontrol alsaUtils # not sure what we need for pipewire
            zstd # for unpacking arch packages
            # glxinfo
            # xorg.xdpyinfo
            # xorg.xev
            
            # Install scanimage (saneBackends) and scanadf (saneFrontends),
            # among other scanning tools.
            # I can't get ADF scanning to work. 'Best' command line is:
            #     scanimage -d pixma:04A91824_214FE1 --batch=scan%02d.png --format tiff --batch-start 1 --batch-double --batch-count 3 --source "Automatic Document Feeder"
            # But it gives "scanimage: sane_read: Operation was cancelled"
            # - this is probably related to https://gitlab.com/sane-project/backends/-/merge_requests/213
            # sane-backends sane-frontends
            
            # programming:
            # (python3.withPackages myPythonPackages)
            dejsonlz4 # for reading firefox jsonlz4 files
            remarshal # for yaml2json etc
            jq # json manipulation
            jetbrains.idea-community
            openjdk21 maven
            # visualvm
            # love_11
            # arduino
            # haskellPackages.ghc
            
            # unstable.android-studio
            apktool dex2jar

            # LaTeX and PDF:
            # (Not sure if rubber uses the chosen texlive distribution)
            # texlive.combined.scheme-medium
            # rubber
            poppler_utils
            qpdf pdftk
            
            # (firefox and librewolf are configured through programs.*)
            thunderbird
            # isync # for e-mail backups (eigenlijk mbsync)
            # chromium
            geany
            zathura # pdf viewer
            # mindmapping-tools:
            vym freemind

            # media:
            vlc ffmpeg
            # music collection:
            beets komputiloj.packages.rip

            inkscape gimp exiftool
            imagemagick scrot
            libreoffice antiword
            audacity
            ocrad # OCR
            
            pstree
            
            # Belgian eID (it looks in /run/current-system/sw/ by default for some things so it's easier to have it installed system-wide):
            # eid-mw

            # other package managers (to be used for non-reproducable things only):
            # nodejs #npm

            zip unzip
            par2cmdline # for error-correcting archives
            llvmPackages.bintools # to get ar (to extract .deb files)
            sqlite
            
            komputiloj.packages.wachtwoord # TODO remove if we use dekstopomveging
        ];

        programs.steam = {
            enable = true;
        };
        programs.firefox.enable = false;
        programs.librewolf = {
            enable = true;

            languagePacks = [ "nl" "en-US" ];

            policies = {
                # https://mozilla.github.io/policy-templates/
                ExtensionSettings = {
                    "*" = {
                        blocked_install_message = "Dit moet via Nix.";
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

        # programs.gnupg.agent = {
        #     enable = true;
        #     enableSSHSupport = true;
        #     pinentryPackage = pkgs.pinentry-gtk2;
        # };

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

        # Set this to true if you want to cast with chromium,
        # in combination with enabling
        # chrome://flags/#load-media-router-component-extension and
        # chrome://flags/#cast-media-route-provider
        # Note that cupsd spams the log if this is true, so disable if not used.
        # (See https://github.com/NixOS/nixpkgs/issues/195090)
        services.avahi.enable = false;

        # Enable the OpenSSH daemon.
        # services.openssh.enable = true;
        programs.ssh = {
            knownHosts = {
                "[u362967.your-storagebox.de]:23" = {
                    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs";
                };
                "gently.radstand.nl" = {
                  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmMPh91t1reE1ddLcFYyddQs0hx4v41KcaNBS2UVnEA";
                };
                "thee.radstand.nl" = {
                  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHmMPh91t1reE1ddLcFYyddQs0hx4v41KcaNBS2UVnEA";
                };
                "github.com" = {
                  publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
                };
            };
            startAgent = true;
            extraConfig = ''
                Host *
                AddKeysToAgent confirm
            '';
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
        
        # fix for headphone jack
        # figured it out with the help of hda-jack-retask from alsaTools
        # but we apply it using systemd instead of using modprobe
        systemd.services.hda-jack-detect-fix = {
          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = 1;
            RestartMode = "direct";
          };
          # Might still not run in time before the boot is completed? Not sure.
          # TODO maybe make this run just before starting a graphical session?
          wantedBy = [ "sound.target" ];
          after = [ "sound.target" ];
          requires = [ "sound.target" ];
          script = ''
            echo "jack_detect = no" > /sys/class/sound/hwC1D0/hints
            echo 1 > /sys/class/sound/hwC1D0/reconfig
          '';
        };

        hardware.bluetooth = {
            enable = true;
        };
        
        # desktopomgeving enzo;
        # voor scarif stond dit in een aparte module, maar die gebruikt xmonad 
        # Enable the X11 windowing system.
        # You can disable this if you're only using the Wayland session.
        services.xserver.enable = true;
        # Enable the KDE Plasma Desktop Environment.
        services.displayManager = {
            sddm = {
                enable = true;
                autoLogin.relogin = true;
            };
            autoLogin = {
                enable = true;
                user = "jeroen";
            };
        };
        services.desktopManager.plasma6.enable = true;
        
        systemd.services."getty@tty6" = {
            serviceConfig = {
                ExecStart = [
                    # https://wiki.archlinux.org/title/Getty#Automatic_login_to_virtual_console
                    # TODO: https://wiki.archlinux.org/title/Xinit#Autostart_X_at_login
                    ""
                    "${pkgs.util-linux}/bin/agetty -o '-p -f -- \\\\u' --noclear --autologin speel tty6 $TERM"
                ];
            };

            # https://wiki.archlinux.org/title/Getty#Automatic_login_to_virtual_console
            overrideStrategy = "asDropin";

            restartIfChanged = false;
        };

        services.xserver.xkb = {
          layout = "us";
          options = "compose:ralt,eurosign:e";
        };
        
        # DOESN'T WORK in wayland.
        # Has to be configured through KDE instead.
        # TODO look at https://github.com/nix-community/plasma-manager?tab=readme-ov-file#supported-versions
        services.libinput = {
            touchpad = {
                tapping = false;
            };
        };

        # # Screen locker
        # services.physlock = {
        #     enable = true;
        #     # nog niet beschikbaar (eens updaten!)
        #     # allowAnyUser = true; # of moeten we rechten via systemd regelen?
        # };

        # Enable adb group and udev rules and such:
        programs.adb.enable = true;

        # For 32-bit games:
        # hardware.opengl.driSupport32Bit = true;
        # hardware.opengl.driSupport = true; # is actually the default

        # Define a user account. Don't forget to set a password with ‘passwd’.
        users.users.jeroen = {
            isNormalUser = true;
            uid = komputiloj.users.jeroen.linux.uid;
            description = komputiloj.users.jeroen.fullName;
            extraGroups = [ "wheel"
                # "adbusers"
                # "lp" # for scanning with Canon
            ];
        };
        users.extraUsers.speel = {
            # A dedicated user account to play untrusted game binaries.
            uid = 1001; # clashes with gorinchemindialoog.
                        # Fortunately, it's unlikely that we will have speel on our
                        # servers or gorinchemindialoog on this laptop.
            isNormalUser = true;
            description = "Speel Spelletjes";
            extraGroups = [ "video" "audio" ];
        };

        # The NixOS release to be compatible with for stateful data such as databases.
        system.stateVersion = "24.05";
    };
}
