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
        runHook preUnpack
        unzip $src
        runHook postUnpack
      '';

      installPhase = ''
        runHook preInstall
        mkdir -vp $out
        cp -rv ./bin ./repos $out
        runHook postInstall
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

        in
          stdenvNoCC.mkDerivation {
            name = "thcrap-config-${name}";

            nativeBuildInputs = [
              wine
            ];

            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            outputHash = sha256;
            impureEnvVars = [ "http_proxy" "https_proxy" ];

            inherit cfgFile cfgPretty;

            RUST_LOG = "trace";
            patch_http_proxy = "garbage://site";
            patch_https_proxy = "garbage://site";
            patch_NO_PROXY = "thpatch.net,mirrors.thpatch.net,thpatch.rcopky.top";

            dontUnpack = true;
            dontPatch = true;
            dontFixup = true;

            configurePhase = ''
              runHook preConfigure
              echo "Creating a wine prefix for running thcrap2nix"
              export BUILD=$PWD
              mkdir .wine
              export WINEPREFIX=$BUILD/.wine
              mkdir -p $BUILD/bin
              PATH="$BUILD/bin:$PATH"
              for i in ${thcrap}/bin/*; do
                ln -sv "$i" $BUILD/bin
              done
              cp -r ${thcrap}/repos $BUILD/repos

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
              runHook postConfigure
            '';

            buildPhase = ''
              runHook preBuild
              export WINEPREFIX=$PWD/.wine
              echo "Running thcrap2nix to create thcrap config for: $cfgPretty"
              echo
              cat $cfgFile

              echo PRE_RUN
              ls -lah --color=always --group-directories-first --classify ./repos
              wine $BUILD/bin/thcrap2nix.exe $cfgFile 2>&1
              echo POST_RUN
              ls -lah --color=always --group-directories-first --classify ./repos/nmlgc
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              #echo "NOTE: download_list:"
              #cat download_list*
              #echo
              #echo "NOTE: file_list:"
              #cat file_list*
              #echo
              export BUILD=$PWD
              mkdir -p $out/config
              cp -r $BUILD/thcrap2nix.js $out/config
              echo -n "Created output file: "
              cat $BUILD/thcrap2nix.js
              cp -r ./repos $out
              runHook postInstall
            '';

          }
      ; # passthru.mkConfig

    }; # self

  in
    self
