let
	util = import ./util.nix;
	# Import some stuff that is not supersecret, but is sensitive enough to not want it in a public git repo.
	# Note that this data will be readable in the nix store of the deployment machine.
	sentemoj = import <sentemoj>;
in {
	# Inspiration taken from https://github.com/nh2/nixops-tutorial/blob/master/example-nginx-deployment.nix

	network.description = "Our humble all-encompassing serviloj deployment";

	# TODO quota
	# TODO mail
	# TODO monitoring
	
	gently2 = { config, nodes, lib, pkgs, ... }: {
		imports = [
			./modules/hetzner_vps.nix
			./modules/mailserver_21_11.nix
		];

		deployment.targetHost = "gently2.radstand.nl";
		deployment.provisionSSHKey = false;
		
		deployment.keys = {
			"luks-storage" = {
				keyCommand = [ "wachtwoord" "get-exact" "secrets/luks-storage@hetzner" ];
			};
			"nextcloud-admin" = {
				keyCommand = [ "wachtwoord" "get-exact" "secrets/admin@wolk.radstand.nl" ];
				user = "nextcloud";
				group = "nextcloud";
				permissions = "ug=r,o=";
			};
		};
		
		# The rest is a configuration just like nixos/configuration.nix
		
		# WARNING this setting is ignored.
		# Instead, nixops determines the stateVersion at first deploy based on the NixOS version it encounters.
		# Our deploy script stores this state on gently now to keep the correct stateVersion.
		# system.stateVersion = lib.mkForce "20.09";

		systemd.services.mount-storage = {
			serviceConfig = {
				Type = "oneshot";
				RemainAfterExit = true;
			};
			requires = [ "luks-storage-key.service" ];
			after    = [ "luks-storage-key.service" ];
			wantedBy = [ "multi-user.target" ];
			requiredBy = [
				"nextcloud-cron.service"
				"nextcloud-setup.service"
				"nextcloud-update-plugins.service"
				"phpfpm-nextcloud.service"
				"gitea.service"
				"btrbk-storage.service"
				"postfix.service"
				"dovecot2.service"
			];
			before = [
				"nextcloud-cron.service"
				"nextcloud-setup.service"
				"nextcloud-update-plugins.service"
				"phpfpm-nextcloud.service"
				"gitea.service"
				"btrbk-storage.service"
				"postfix.service"
				"dovecot2.service"
			];
			path = [ pkgs.cryptsetup pkgs.utillinux pkgs.unixtools.mount pkgs.unixtools.umount ];
			script = ''
				if mountpoint -q /mnt/storage; then
					echo "Storage already mounted. Done here."
					exit 0
				fi
				if [ -b /dev/mapper/storage ]; then
					echo "LUKS mapping already opened."
				else
					echo "Opening LUKS mapping..."
					cryptsetup open UUID=6c8d5be7-ae46-4e51-a270-fd5bdce46f3b storage --type luks --key-file /run/keys/luks-storage
				fi
				echo "Mounting..."
				mkdir -p /mnt/storage
				mount /dev/mapper/storage /mnt/storage
				echo "Done here."
			'';
			preStop = ''
				if mountpoint -q /mnt/storage; then
					umount /mnt/storage
				fi
				cryptsetup close storage
			'';
		};
		
		services.btrbk = {
			instances = {
				storage = {
					settings = {
						timestamp_format = "long-iso"; # safe from the caveat at https://digint.ch/btrbk/doc/btrbk.conf.5.html#_reference_time as long as we don't use btrbk for backups
						snapshot_preserve_min = "24h"; # for manual snapshots? not sure, but we need to set it to something other than "all"
						snapshot_preserve = "24h 7d 5w 12m *y";
						preserve_day_of_week = "monday";
						preserve_hour_of_day = "0";
						volume."/mnt/storage" = {
							snapshot_dir = "snapshots";
							subvolume."live/*" = {};
						};
					};
					onCalendar = "hourly";
				};
			};
		};

		services.btrfs.autoScrub = {
			enable = true;
			fileSystems = [ "/mnt/storage" ];
			interval = "weekly";
		};

		services.openssh.enable = true;
		users = {
			users.root = {
				passwordFile = "/root/password"; # must be present on the machine
				openssh.authorizedKeys.keyFiles = [
					../scarif/home/jeroen/.ssh/id_rsa.pub
				];
			};

			# Make sure users have the same uid on all our machines.
			# Add users here that don't have a fixed uid in nixpkgs/nixos.
			# also exist on the machine (actually, in our whole deployment), with a fixed uid.
			# Warning: changing uids here after a user has been created has no effect!
			# (I think - the note here was about containers.)
			# You have to rm /var/lib/nixos/uid-map and userdel the user.
			users.nextcloud = {
				uid = 70000;
				group = "nextcloud";
				extraGroups = [ "keys" ];
			};
			groups.nextcloud = {
				gid = 70000;
			};
			users.gitea = {
				uid = 70001;
				group = "gitea";
			};
			groups.gitea = {
				gid = 70001;
			};
			users.vmail = {
				uid = 70002;
				group = "vmail";
				isSystemUser = true;
			};
			groups.vmail = {
				gid = 70002;
			};
		};

		networking = {
			hostName = "gently2";
			domain = "radstand.nl";
			interfaces.ens3 = {
				useDHCP = true;
			};
			firewall = {
				allowPing = true;
				allowedTCPPorts = [
					# NOTE: most services add their ports automatically,
					# so most of this is just documentation.
					22  # SSH
					80  # HTTP - only allowed for Let's Encrypt challenges
					443 # HTTPS
					143 # IMAP
					993 # IMAPS
					25  # SMTP
					465 # SMTP submission over TLS
					587 # SMTP submission
				];
			};
		};

		services.fail2ban.enable = true;

		security.acme = {
			acceptTerms = true;
			email = "jeroen@lwstn.eu";
		};

		services.nginx = {
			enable = true;
			recommendedGzipSettings = true;
			recommendedOptimisation = true;
			recommendedProxySettings = true;
			recommendedTlsSettings = true;

			virtualHosts = {
				"wolk.radstand.nl" = {
					forceSSL = true;
					enableACME = true;
				};
				"thee.radstand.nl" = {
					forceSSL = true;
					enableACME = true;
					locations."/" = {
						proxyPass = "http://localhost:3000";
					};
				};
			};
		};

		services.nextcloud = {
			enable = true;

			package = pkgs.nextcloud21;

			home = "/mnt/storage/live/nextcloud/rootdir";

			autoUpdateApps = {
				enable = true;
			};

			hostName = "wolk.radstand.nl";
			https = true; # no idea how this relates to config.overwriteProtocol

			maxUploadSize = "512M";

			config = {
				adminuser = "admin";
				adminpassFile = "/run/keys/nextcloud-admin";
				
				dbtype = "sqlite"; # let's start simple
				
				overwriteProtocol = "https";
			};
		};
		
		services.gitea = {
			enable = true;

			database.type = "sqlite3";

			rootUrl = "https://thee.radstand.nl/";
			domain = "thee.radstand.nl";
			cookieSecure = true;

			log.level = "Info";

			# NOTE: after changing the stateDir, regenerate gitea's authorized_keys file through the admin webinterface.
			stateDir = "/mnt/storage/live/gitea/rootdir";

			disableRegistration = true;

			# mailerPasswordFile = ...;
		};

		mailserver = {
			enable = true;
	
			# TODO get rid of nginx welcome page on mail2.radstand.nl
			fqdn = "mail2.radstand.nl";
			sendingFqdn = "gently.radstand.nl";
			domains = [ "testdomein.radstand.nl" ];

			forwards = util.mapNames (name : name + "@gorinchemindialoog.nl") sentemoj.gid_forwards // {
				"jeroen@testdomein.radstand.nl" = "jeroen@lwstn.eu";
			};

			indexDir = "/var/mail-indexes";
			mailDirectory = "/mnt/storage/live/mail/vmail"; # TODO make relevant service depend on this mount!
			sieveDirectory = "/mnt/storage/live/mail/sieve"; # TODO not sure if this is persistent state
			vmailGroupName = "vmail";
			vmailUserName = "vmail";
			vmailUID = 70002;

			certificateScheme = 3; # let's hope this uses the regular letsencrypt infrastructure of NixOS so it doesn't clash with nginx
		};

		environment.systemPackages = with pkgs; [
			screen
			netcat
			vim
			cryptsetup btrfs-progs parted
		];
	};
}
