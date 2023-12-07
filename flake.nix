{
  description = "A very basic flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      # Use the same nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, gitignore }:
    let
      pkgsWin = import nixpkgs {
        system = "x86_64-linux";
        crossSystem = nixpkgs.lib.systems.examples.mingw32;
        overlays = [ rust-overlay.overlays.default ];
      };
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ rust-overlay.overlays.default ];
      };
      inherit (gitignore.lib) gitignoreSource;

      thcrap2nix = pkgsWin.callPackage ./thcrap2nix {
        winePackageNative = pkgs.winePackages.staging;
        inherit gitignoreSource;
      };

      thcrap = pkgs.callPackage ./thcrap.nix { };

      thprac = pkgs.fetchurl {
        url =
          "https://github.com/touhouworldcup/thprac/releases/download/v2.2.1.4/thprac.v2.2.1.4.exe";
        sha256 = "sha256-eIfkABD0Wfg0/NjtfMO+yjfZFvF7oLfUjOaR0pkv1FM=";
      };

      makeWinePrefix = { defaultFont ? "Noto Sans CJK SC", fontPackage ? pkgs.noto-fonts-cjk-sans }:
        let
          touhou-wineprefix = { stdenvNoCC, wine, pkgsCross, bash }:
            stdenvNoCC.mkDerivation {
              name = "touhou-wineprefix";
              nativeBuildInputs = [ wine ];
              phases = [ "installPhase" ];

              dxvk32_dir = "${pkgsCross.mingw32.dxvk_2}/bin";
              mcfgthreads32_dir = "${pkgsCross.mingw32.windows.mcfgthreads_pre_gcc_13}/bin";

              installPhase = ''
                runHook preInstall
                export WINEPREFIX=$out/share/wineprefix
                mkdir -p $WINEPREFIX
                wineboot -i
                wineserver --wait || true
                echo Setting up DXVK
                ${bash}/bin/bash ${./setup_dxvk.sh}
                echo DXVK installed
                wineserver --wait || true
                echo "${defaultFont}" > $out/share/wineprefix/default_font.txt
                find ${fontPackage} -type f -name "*.ttc" -exec cp {} $out/share/wineprefix/drive_c/windows/Fonts/ \;
                find ${fontPackage} -type f -name "*.ttf" -exec cp {} $out/share/wineprefix/drive_c/windows/Fonts/ \;
                runHook postInstall
              '';
            }
          ; # touhou-wineprefix
        in
          pkgs.callPackage touhou-wineprefix { }
      ; # makeWinePrefix

      defaultWinePrefix = makeWinePrefix { };

      makeTouhou = {
        thVersion,
        name ? thVersion,
        enableVpatch ? true,
        enableThprac ? true,
        thcrapPatches ? null,
        thcrapSha256 ? "",
        baseDrv ? null,
        winePrefix ? defaultWinePrefix,
      }:
        let
          thcrapConfig = pkgs.callPackage thcrap.mkConfig {
            jansson = pkgsWin.jansson;

            inherit thcrap2nix;

            name = thVersion;
            sha256 = thcrapSha256;
            patchSpec = [
              { repo_id = "thpatch"; patch_id = "lang_en"; }
            ];

            games = [
              thVersion
              "${thVersion}_custom"
            ];
          }; # thcrapConfig

        in
          pkgs.callPackage ./wrapper.nix {
            inherit
              thVersion
              name
              enableVpatch
              enableThprac
              baseDrv
              thcrapPatches
              thcrap
              thcrapSha256
              thcrapConfig
              thprac
              vpatch
              winePrefix
            ;
          }
      ; # makeTouhou

      vpatch =
        let
          self = {
            stdenvNoCC,
            unzip,
            fetchurl
          }:
            stdenvNoCC.mkDerivation {
              name = "vsyncpatch-bin";
              version = "2015-11-28";

              src = fetchurl {
                url = "https://maribelhearn.com/mirror/VsyncPatch.zip";
                sha256 = "XVmbdzF6IIpRWQiKAujWzy6cmA8llG34jkqUb29Ec44=";
                # https://web.archive.org/web/20220824223436if_/https://maribelhearn.com/mirror/VsyncPatch.zip
              };
              srcthcrap = fetchurl {
                url = "https://www.thpatch.net/w/images/1/1a/vpatch_th06_unicode.zip";
                sha256 = "06x8gQNmz8UZVIt6hjUJHvpWS3SVz0iWG2kqJIBN9M4=";
              };

              nativeBuildInputs = [
                unzip
              ];

              unpackPhase = ''
                runHook preUnpack
                unzip $src
                unzip $srcthcrap
                runHook postUnpack
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out/bin
                cp vpatch/vpatch_rev4/vpatch.exe $out/bin
                cp vpatch/vpatch_rev4/*.dll $out/bin
                cp vpatch/vpatch_rev7/*.dll $out/bin
                cp vpatch/vpatch_th12.8/*.dll $out/bin
                cp vpatch/vpatch_th13/*.dll $out/bin
                cp vpatch/vpatch_th14/*.dll $out/bin
                cp vpatch/vpatch_th15/*.dll $out/bin
                cp vpatch_th06_unicode.dll $out/bin/vpatch_th06.dll
                runHook postInstall
              '';

            }
          ; # vsyncpatch-bin
        in
          pkgs.callPackage self { }
      ; # vpatch

      #makeTouhouOverlay = args: makeTouhou (args // { baseDrv = null; });

      th07 = makeTouhou {
        thVersion = "th07";
        thcrapPatches = patches: with patches; [
          lang_en
          #western_name_order
        ];
        #thcrapSha256 = "sha256-4aym1BTYOcp4isg3tfqEsTUjuLqcs5V7P/CzrwiZvgk=";
        #thcrapSha256 = "sha256-DSIZLjVtEBon25kqSnKRD0ZIfr+mzsXuoDi8jG+FPsY=";
        thcrapSha256 = "sha256-ANXCxm4E9RZ47SYWJDbGwxl7E9Jb36Z2CvneT+I1biE=";
      };

    in {
      packages.x86_64-linux = rec {
        default = th07;
        inherit th07;
        touhouTools = rec {
          defaultWinePrefix = makeWinePrefix { };
          vpatch = pkgs.callPackage ({ stdenvNoCC, unzip, fetchurl }:
            stdenvNoCC.mkDerivation {
              name = "vsyncpatch-bin";
              version = "2015-11-28";
              src = fetchurl {
                url = "https://maribelhearn.com/mirror/VsyncPatch.zip";
                sha256 = "XVmbdzF6IIpRWQiKAujWzy6cmA8llG34jkqUb29Ec44=";
                # https://web.archive.org/web/20220824223436if_/https://maribelhearn.com/mirror/VsyncPatch.zip
              };
              srcthcrap = fetchurl {
                url = "https://www.thpatch.net/w/images/1/1a/vpatch_th06_unicode.zip";
                sha256 = "06x8gQNmz8UZVIt6hjUJHvpWS3SVz0iWG2kqJIBN9M4=";
              };
              nativeBuildInputs = [ unzip ];
              unpackPhase = ''
                unzip $src
                unzip $srcthcrap
              '';
              installPhase = ''
                mkdir -p $out/bin
                cp vpatch/vpatch_rev4/vpatch.exe $out/bin
                cp vpatch/vpatch_rev4/*.dll $out/bin
                cp vpatch/vpatch_rev7/*.dll $out/bin
                cp vpatch/vpatch_th12.8/*.dll $out/bin
                cp vpatch/vpatch_th13/*.dll $out/bin
                cp vpatch/vpatch_th14/*.dll $out/bin
                cp vpatch/vpatch_th15/*.dll $out/bin
                cp vpatch_th06_unicode.dll $out/bin/vpatch_th06.dll
              '';
            }) { };
          makeTouhouOverlay = args: makeTouhou (args // { baseDrv = null; });
          thcrap = pkgs.callPackage ({ stdenvNoCC, unzip, fetchurl }:
            stdenvNoCC.mkDerivation {
              name = "thcrap-bin";
              version = "2023-08-30";
              src = fetchurl {
                url = "https://github.com/thpatch/thcrap/releases/download/2023-08-30/thcrap.zip";
                sha256 = "XdJTmVNTa16gcq7gipP7AeYxvD1+K9n4u4kJafeXv5c=";
              };
              nativeBuildInputs = [ unzip ];
              unpackPhase = ''
                unzip $src
              '';
              installPhase = ''
                mkdir -p $out
                cp -r ./bin ./repos $out
              '';
            }) { };
          thprac = pkgs.fetchurl {
            url =
              "https://github.com/touhouworldcup/thprac/releases/download/v2.2.1.4/thprac.v2.2.1.4.exe";
            sha256 = "sha256-eIfkABD0Wfg0/NjtfMO+yjfZFvF7oLfUjOaR0pkv1FM=";
          };
          thcrapPatches = {
            lang_zh-hans = {
              repo_id = "thpatch";
              patch_id = "lang_zh-hans";
            };
            lang_en = {
              repo_id = "thpatch";
              patch_id = "lang_en";
            };
            EoSD_Retexture_Hitbox = {
              repo_id = "WindowDump";
              patch_id = "EoSD_Retexture_Hitbox";
            };
          };
          thcrapDown = { name, sha256 ? "", patches, games }:
            let
              cfg = {
                patches = patches thcrapPatches;
                inherit games;
              };
              cfgFile = pkgs.writeText "thcrap2nix.json" (builtins.toJSON cfg);
            in pkgs.stdenvNoCC.mkDerivation {
              name = "thcrap-config-${name}";
              nativeBuildInputs = [ pkgs.wine ];
              outputHashMode = "recursive";
              outputHashAlgo = "sha256";
              outputHash = sha256;
              phases = [ "buildPhase" ];
              impureEnvVars = [ "http_proxy" "https_proxy" ];
              buildPhase = ''
                export BUILD=$PWD
                mkdir .wine
                export WINEPREFIX=$BUILD/.wine
                mkdir -p $BUILD/bin
                for i in ${thcrap}/bin/*; do
                  ln -s $i $BUILD/bin/
                done
                cp -r ${thcrap}/repos $BUILD
                chmod -R 777 $BUILD/repos
                for i in ${thcrap2nix}/bin/*; do
                  ln -s $i $BUILD/bin/
                done
                ln -s ${pkgsWin.jansson}/bin/libgcc* $BUILD/bin/
                wine wineboot
                echo "Wineboot finished."
                export RUST_LOG=trace
                export patch_http_proxy=garbage://site
                export patch_https_proxy=garbage://site
                export patch_NO_PROXY="thpatch.net,thpatch.rcopky.top"
                wine $BUILD/bin/thcrap2nix.exe ${cfgFile}
                mkdir -p $out/config
                cp -r $BUILD/repos $out
                cp $BUILD/thcrap2nix.js $out/config
              '';
            };

        };
        examples = {
          thcrapDownExample = touhouTools.thcrapDown {
            name = "example";
            patches = (p: with p; [ lang_zh-hans ]);
            games = [ "th16" ];
            sha256 = "xHX3FIjaG5epe+N3oLkyP4L7h01eYjiHjTXU39QuSpA=";
          };
        };
        zh_CN = {
          th06 = touhouTools.makeTouhouOverlay {
            thVersion = "th06";
            thcrapPatches = (p: with p; [ EoSD_Retexture_Hitbox lang_zh-hans lang_en ]);
            thcrapSha256 = "o/vce/9bDqH6hvuvmZWMhOfXd4EJ2klw0BGAEu47HZI=";
          };
          th07 = touhouTools.makeTouhouOverlay {
            thVersion = "th07";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "/4yNd+r0P+uttIrkTaxItmG5UGrWqk5bq4b2sOD/RDM=";
          };
          th08 = touhouTools.makeTouhouOverlay {
            thVersion = "th08";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "lPrCzNQqvFRJaHX+eYKladopCMVBnTcS+fnHYG0Y468=";
          };
          th09 = touhouTools.makeTouhouOverlay {
            thVersion = "th09";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "WWU8j9XtubFlab7zQ3kUK++vbAImPjKtlD+dxrsH3jc=";
          };
          th10 = touhouTools.makeTouhouOverlay {
            thVersion = "th10";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "Quc94iqcdfudcJpboUL6PxJTgHk2mzCEumoXM5QB2qM=";
          };
          th11 = touhouTools.makeTouhouOverlay {
            thVersion = "th11";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "RM+N/GYuRJpgXVcMAVAR8uwRL9l3hfp/g3FCNB5eMRs=";
          };
          th12 = touhouTools.makeTouhouOverlay {
            thVersion = "th12";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "hXJVsq3Ha+whczB+yorWdpj6fVWB3WYoMRHOt/ug3PI=";
          };
          th13 = touhouTools.makeTouhouOverlay {
            thVersion = "th13";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "T6CR9j6gwsPy0tSMJYzAkln6VVq5F1/VVg/nKSK/kpg=";
          };
          th14 = touhouTools.makeTouhouOverlay {
            thVersion = "th14";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "JSzdEWpdgKpSa4t+ymsQCAKbHQt1+TYzBx29FmnGxvE=";
          };
          th15 = touhouTools.makeTouhouOverlay {
            thVersion = "th15";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "4AvJHQ+XHtBb6AdeyCDuyykxtqwMc38Bx1gWCu6WDso=";
          };
          th16 = touhouTools.makeTouhouOverlay {
            thVersion = "th16";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "HYagDCpD70uU7/kiI8+h8NYRxS4G9C+mXf/6KMovbe0=";
          };
          th17 = touhouTools.makeTouhouOverlay {
            thVersion = "th17";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "jwOEw9ce2+sJQYDJ4hz6VendJOfIub4Myuh+xc4g0qU=";
          };
          th18 = touhouTools.makeTouhouOverlay {
            thVersion = "th18";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "sfpYFWlTTALCgcrya2cewXWIkMQIXTT0RVvTw9WnO5Y=";
          };
          th19 = touhouTools.makeTouhouOverlay {
            thVersion = "th19";
            thcrapPatches = (p: with p; [ lang_zh-hans lang_en ]);
            thcrapSha256 = "xWWuEjt5+dfB2LqQiLRGeHYMZGyPgAub6rjgVlRbkfk=";
          };

        };
      };

      packages.x86_64-linux.hello = nixpkgs.legacyPackages.x86_64-linux.hello;

      #packages.x86_64-linux.default = self.packages.x86_64-linux.hello;
      devShells.x86_64-linux.default = pkgsWin.callPackage
        ({ mkShell, stdenv, rust-bin, windows, jansson }:
          mkShell {
            #buildInputs = [pkgs.rust-bin.stable.latest.minimal];
            #CARGO_TARGET_I686_PC_WINDOWS_GNU_LINKER = "${stdenv.cc.targetPrefix}cc";
            nativeBuildInputs = [
              pkgsWin.pkgsBuildHost.rust-bin.stable.latest.complete
              pkgs.libclang
              pkgs.winePackages.staging
            ];
            buildInputs = [ windows.pthreads windows.mcfgthreads stdenv.cc.libc jansson ];
            LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
            WINEPATH = "${jansson}/bin;${windows.mcfgthreads}/bin;../thcrap/bin";
            HOST_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          }) { };

    };
}
