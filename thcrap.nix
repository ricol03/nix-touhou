{
  stdenvNoCC,
  lib,
  symlinkJoin,
  unzip,
  fetchurl,
}:
  let
    self = stdenvNoCC.mkDerivation {
      name = "thcrap-bin";
      version = "2023-08-30";
      src = fetchurl {
        url = "https://github.com/thpatch/thcrap/releases/download/2023-08-30/thcrap.zip";
        sha256 = "XdJTmVNTa16gcq7gipP7AeYxvD1+K9n4u4kJafeXv5c=";
      };

      nativeBuildInputs = [
        unzip
      ];

      unpackPhase = ''
        unzip $src
      '';

      installPhase = ''
        mkdir -vp $out
        cp -rv ./bin ./repos $out
      '';

      passthru.mkConfig = {
        name,
        sha256 ? lib.fakeSha256,
        # The patches to enable.
        patchSpec ? [ { repo_id = "thpatch"; patch_id = "lang_en"; } ],
        games ? [ name ],
        wine,
        writeText,
        lndir,
        thcrap2nix,
        # Should be pkgsWin.jansson
        jansson,
      }:
        #assert (builtins.isFunction patches);
        assert (builtins.isList patchSpec);
        assert (builtins.isList games);
        assert (lib.lists.all lib.isDerivation [ wine thcrap2nix jansson ]);
        let

          inherit (builtins) toJSON concatStringsSep map;

          thcrap = self;

          # FIXME: refactor into something dynamic or a separate Nix file.
          thcrapPatches = {
            lang_en = {
              repo_id = "thpatch";
              patch_id = "lang_en";
            };
          };

          # Will be JSON-ified for thcrap's config.
          cfg = {
            patches = patchSpec;
            inherit games;
          };
          cfgFile = writeText "thcrap2nix.json" (toJSON cfg);
          cfgPretty = lib.generators.toPretty { allowPrettyValues = true; } cfg;
          patchNames = concatStringsSep "-" map (p: p.patch_id) cfg.patches;
          buildenv = symlinkJoin {
            name = "${name}-buildenv";
            paths = [
              thcrap
              thcrap2nix
            ];
          };

        in
          stdenvNoCC.mkDerivation {
            name = "thcrap-config-${name}";

            nativeBuildInputs = [
              wine
              buildenv
              lndir
            ];

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = sha256;
            impureEnvVars = [ "http_proxy" "https_proxy" ];

            inherit cfgFile cfgPretty;

            RUST_LOG = "trace";
            patch_http_proxy = "garbage://site";
            patch_https_proxy = "garbage://site";
            patch_NO_PROXY = "thpatch.net,thpatch.rcopky.top";

            dontUnpack = true;
            dontPatch = true;
            dontFixup = true;

            configurePhase = ''
              echo "Creating a wine prefix for running thcrap2nix"
              export BUILD=$PWD
              mkdir .wine
              export WINEPREFIX=$BUILD/.wine
              mkdir -p $BUILD/bin
              PATH="$BUILD/bin:$PATH"
              for i in ${thcrap}/bin/*; do
                ln -sv "$i" $BUILD/bin
              done
              cp -rv ${buildenv}/repos $BUILD/repos

              chmod -Rv 777 $BUILD/repos
              for i in ${thcrap2nix}/bin/*; do
                ln -sv "$i" $BUILD/bin/
              done
              ls -lah $BUILD
              ls -lah $BUILD/bin

              echo ln -sv ${jansson}/bin/libgcc* $BUILD/bin/
              ln -sv ${jansson}/bin/libgcc* $BUILD/bin/

              echo "Booting wine"
              export XDG_CACHE_HOME=$BUILD/.cache
              export XDG_CONFIG_HOME=$BUILD/.config
              WINEDEBUG=-all wine wineboot
              set +x
            '';

            buildPhase = ''
              echo "Running thcrap2nix to create thcrap config for: $cfgPretty"

              WINEDEBUG=-all wine $BUILD/bin/thcrap2nix.exe $cfgFile
            '';

            installPhase = ''
              mkdir -p $out/config
              cp -r $BUILD/thcrap2nix.js $out/config
              echo -n "Created output file: "
              cat $BUILD/thcrap2nix.js
            '';

          }
      ; # passthru.mkConfig

    }; # self

    mkConfig = {
      name,
      sha256 ? lib.fakeSha256,
      # The patches to enable.
      patchSpec ? [ { repo_id = "thpatch"; patch_id = "lang_en"; } ],
      games,
      wine,
      writeText,
      lndir,
      thcrap2nix,
      # Should be pkgsWin.jansson
      jansson,
    }:
      #assert (builtins.isFunction patches);
      assert (builtins.isList patchSpec);
      assert (builtins.isList games);
      assert (lib.lists.all lib.isDerivation [ wine thcrap2nix jansson ]);
      let

        inherit (builtins) toJSON concatStringsSep map;

        thcrap = self;

        # FIXME: refactor into something dynamic or a separate Nix file.
        thcrapPatches = {
          lang_en = {
            repo_id = "thpatch";
            patch_id = "lang_en";
          };
        };

        # Will be JSON-ified for thcrap's config.
        cfg = {
          patches = patchSpec;
        };
        cfgFile = writeText "thcrap2nix.json" (toJSON cfg);
        cfgPretty = lib.generators.toPretty { allowPrettyValues = true; } cfg;
        patchNames = concatStringsSep "-" map (p: p.patch_id) cfg.patches;

      in
        stdenvNoCC.mkDerivation {
          name = "thcrap-config-${name}";

          nativeBuildInputs = [
            wine
            lndir
          ];

          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = sha256;
          impureEnvVars = [ "http_proxy" "https_proxy" ];

          inherit cfgFile cfgPretty;
          passAsFile = [ "cfgPretty" ];

          RUST_LOG = "trace";
          patch_http_proxy = "garbage://site";
          patch_https_proxy = "garbage://site";
          patch_NO_PROXY = "thpatch.net,thpatch.rcopky.top";

          dontUnpack = true;
          dontPatch = true;
          dontFixup = true;

          configurePhase = ''
            echo "Creating a wine prefix for running thcrap2nix"
            export BUILD=$PWD
            mkdir .wine
            export WINEPREFIX=$BUILD/.wine
            mkdir -p $BUILD/bin
            lndir ${thcrap}/bin $BUILD/bin

            cp -rv ${thcrap}/repos $BUILD
            chmod -Rv 777 $BUILD/repos
            lndir ${thcrap2nix}/bin $BUILD/bin

            ln -sv ${jansson}/bin/libgcc* $BUILD/bin/

            echo "Booting wine"
            wine wineboot
          '';

          buildPhase = ''
            echo -n "Running thcrap2nix to create thcrap config for: "
            cat $cfgPretty

            wine $BUILD/bin/thcrap2nix.exe $cfgFile
          '';

          installPhase = ''
            mkdir -p $out/config
            cp -r $BUILD/thcrap2nix.js $out/config
            echo -n "Created output file: "
            cat $BUILD/thcrap2nix.js
          '';

        }
    ; # mkConfig

  in
    self // { passthru.mkConfig = mkConfig; }
