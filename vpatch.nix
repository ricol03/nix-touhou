{ stdenvNoCC, unzip, fetchurl}:

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

