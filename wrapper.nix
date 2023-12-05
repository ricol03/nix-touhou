{
  stdenvNoCC,
  lib,
  bash,
  makeWrapper,
  writeScript,
  writeShellScript,
  wine,
  bubblewrap,
  iconv,
  dxvk,
  thVersion,
  touhouMetadata,
  name,
  enableVpatch,
  enableThprac,
  baseDrv,
  thcrapPatches,
  thcrap,
  downloadThcrap,
  thcrapSha256,
  thprac,
  vpatch,
  winePrefix,
}:
  assert (builtins.hasAttr thVersion touhouMetadata);
  let
    inherit (lib.strings) optionalString;

    pname = "${name}-wrapper";
    metadata = touhouMetadata.${thVersion};
    setAppdata = appdata:
      writeScript "setappdata-and-run" ''
        @echo off
        set APPDATA=${appdata}
        start "" %*
      ''

    ; # setAppdata

    relativeMutableBase = ''
      for f in ${builtins.toString metadata.mutable.paths}; do
        if [[ "$f" =~ .*/ ]]; then
          mkdir -p "$mutableBase/$f"
        else
          if ! [[ -e "$mutableBase/$f" ]]; then
            if [[ -e "$touhouRoot/$f" ]]; then
              echo "Copying $f from touhouRoot $touhouRoot"
              cp "$touhouRoot/$f" "$mutableBase/$f"
            fi
          fi
          touch "$mutableBase/$f"
        fi
      done
    ''; # relativeMutableBase

    appdataMutableBase = ''
      mkdir -p "$mutableBase/appdata"
    '';

    mutableBaseScript = if metadata.mutable.type == "relative"
      then
        relativeMutableBase
      else
        appdataMutableBase
    ;

    relativeMount = ''
      mutableMount=""
      for f in ${builtins.toString metadata.mutable.paths}; do
        mutableMount="--bind \"$mutableBase/$f\" \"/opt/touhou/$f\" $mutableMount"
      done
    '';

    appdataMount = ''
      mutableMount="--bind \"$mutableBase/$f\" \"/opt/touhou/$f\" $mutableMount"
    '';

    mutableMountScript = if metadata.mutable.type == "relative"
      then
        relativeMount
      else
        appdataMount
    ;

  in
    stdenvNoCC.mkDerivation {
      name = pname;
      gameExe = "${thVersion}.exe";
      inherit thVersion;
      phases = [ "installPhase" ];
      nativeBuildInputs = [ makeWrapper ];
      thcrapPath = optionalString (thcrapPatches != null) thcrap;
      thcrapConfigPath = optionalString (thcrapPatches != null) (downloadThcrap {
        name = thVersion;
        sha256 = thcrapSha256;
        patches = thcrapPatches;
        games = [
          thVersion
          "${thVersion}_custom"
        ];
      });

      thpracPath = optionalString enableThprac thprac;
      vpatchPath = optionalString enableVpatch vpatch;
      baseDrv = optionalString (baseDrv != null) baseDrv;

      inherit enableThprac enableVpatch;

      enableThcrap = thcrapPatches != null;
      enableBase = baseDrv != null;

      launcherScriptBwrap = writeShellScript "${pname}-script-bwrap" ''
        WINEPREFIX=$OVERRIDE_WINEPREFIX
        export PATH=${wine}/bin:$PATH
        touhouRoot="$wrapperRoot/base"
        mutableBase="$HOME/.local/opt/nix-touhou/${name}"
        if [[ -z "$enableBase" ]]; then
          touhouRoot="$PWD"
        fi
        wineprefixMount="--bind $WINEPREFIX /opt/wineprefix"
        if [[ -z "$WINEPREFIX" ]]; then
          WINEPREFIX="${winePrefix}/share/wineprefix"
          export COPY_WINEPREFIX=1
          wineprefixMount="--ro-bind $WINEPREFIX /opt/wineprefix"
        fi

        mkdir -p "$mutableBase"

        ${mutableBaseScript}

        thcrapMount=""
        vpatchMount=""
        thpracMount=""

        if ! [[ -z $enableThcrap ]]; then
          mkdir "$mutableBase/thcrap-logs"
          thcrapMount="--ro-bind \"$wrapperRoot/thcrap\" /opt/thcrap/ --bind \"$mutableBase/thcrap-logs\" /opt/thcrap/logs"
        fi

        if ! [[ -z $enableVpatch ]]; then
          if ! [[ -e "$mutableBase/vpatch.ini" ]]; then
            if [[ -e "$touhouRoot/vpatch.ini" ]]; then
              echo "Copying vpatch.ini from touhouRoot $touhouRoot"
              cp "$touhouRoot/vpatch.ini" "$mutableBase/vpatch.ini"
            fi
          fi
          touch "$mutableBase/vpatch.ini"
          vpatchMount="--ro-bind \"$wrapperRoot/vpatch.exe\" /opt/touhou/vpatch.exe --ro-bind \"$wrapperRoot/vpatch_${thVersion}.dll\" /opt/touhou/vpatch_${thVersion}.dll --bind \"$mutableBase/vpatch.ini\" /opt/touhou/vpatch.ini"
        fi

        touhouBaseMount=""
        touhouBaseMountMethod="--ro-bind"
        if ! [[ -z $MUTABLE_TOUHOU_ROOT ]]; then
          touhouBaseMountMethod="--bind"
        fi
        for f in "$touhouRoot/"*; do
          fbase=$(basename "$f")
          touhouBaseMount="$touhouBaseMountMethod \"$f\" \"/opt/touhou/$fbase\" $touhouBaseMount"
        done

        ${mutableMountScript}

        cmd="LAUNCH_WITH_BWRAP=1 XAUTHORITY=/opt/.Xauthority WINEPREFIX=/opt/wineprefix ${bubblewrap}/bin/bwrap \
          --ro-bind /nix /nix \
          --proc /proc \
          --dev-bind /dev /dev \
          --bind /sys /sys \
          --tmpfs /tmp \
          --tmpfs /opt \
          $wineprefixMount \
          --ro-bind $XAUTHORITY /opt/.Xauthority \
          --ro-bind /tmp/.X11-unix /tmp/.X11-unix \
          --bind /run /run \
          --ro-bind /var /var \
          --ro-bind /bin /bin \
          $touhouBaseMount \
          $thcrapMount \
          $thpracMount \
          $vpatchMount \
          $mutableMount \
          --chdir /opt/touhou \
          $wrapperPath/bin/${pname}-raw"
        echo "$cmd"
        bash -c "$cmd"
      ''; # launcherScriptBwrap

      launcherScript = writeShellScript "${pname}-script" ''
        LAUNCHPATH=$PWD
        if ! [[ -z $enableThprac ]]; then
          if ! [[ -z "$LAUNCHPATH/thprac.exe" ]]; then
            echo "Linking thprac.exe for debugging purposes"
            ln -s $wrapperRoot/thprac.exe "$LAUNCHPATH/thprac.exe"
          fi
        fi

        if ! [[ -z $enableVpatch ]]; then
          if ! [[ -e "$LAUNCHPATH/vpatch.exe" ]]; then
            echo "Linking vpatch.exe for debugging purposes"
            ln -s $wrapperRoot/vpatch.exe "$LAUNCHPATH/vpatch.exe"
            ln -s $wrapperRoot/vpatch*.dll "$LAUNCHPATH/"
          fi
        fi

        if ! [[ -z $COPY_WINEPREFIX ]]; then
          echo "Copying wineprefix"
          cp -r $WINEPREFIX /tmp/wineprefix
          chmod -R 777 /tmp/wineprefix
          WINEPREFIX=/tmp/wineprefix
          ls -lah $WINEPREFX
          if [[ -e $WINEPREFIX/default_font.txt ]]; then
            font=$(cat $WINEPREFIX/default_font.txt)
            echo "Setting font to $font"
            regc="REGEDIT4

      [HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]
      \"PMingLiU\"=\"$font\"
      \"ＭＳ ゴシック\"=\"$font\"
      "

            echo -e -n "\xff\xf3" > "/tmp/thcfg.reg"
            ${iconv}/bin/iconv --from-code UTF-8 --to-code UTF-16LE <(echo "$regc") >> "/tmp/thcfg.reg"
            ${wine}/bin/wine regedit "/tmp/thcfg.reg"
          fi # WINEPREFIX/default_font
        fi # COPY_WINEPREFIX

        echo "Wine prefix '$WINEPREFIX' should be mutable"
        mkdir -p $WINEPREFIX

        # Set executable
        if ! [[ -z $enableThprac ]]; then
          gameExe="thprac.exe" # thprac can find vpatch on its own
        elif ! [[ -z $enableVpatch ]]; then
          gameExe="vpatch.exe"
        fi

        cp ${setAppdata "z:/opt/"} /opt/launch.bat
        if [[ -z $RUN_CUSTOM ]]; then
          if ! [[ -e "$LAUNCHPATH/$gameExe" ]]; then
            echo "gameExe not found: $gameExe"
            exit 1
          fi

          if ! [[ -z $enableThcrap ]]; then
            if ! [[ -z $LAUNCH_WITH_BWRAP ]]; then
              cd /opt/thcrap
            else
              cd "$wrapperRoot/thcrap"
            fi
            ${wine}/bin/wine /opt/launch.bat bin/thcrap_loader.exe thcrap2nix.js "$LAUNCHPATH/$gameExe"
          else
            ${wine}/bin/wine /opt/launch.bat "$LAUNCHPATH/$gameExe"
          fi
        else
          if ! [[ -e "$LAUNCHPATH/custom.exe" ]]; then
            echo "custom.exe not found: $LAUNCHPATH/custom.exe"
            exit 1
          fi

          if ! [[ -z $enableThcrap ]]; then
            if ! [[ -z $LAUNCH_WITH_BWRAP ]]; then
              cd /opt/thcrap
            else
              cd "$wrapperRoot/thcrap"
            fi
            ${wine}/bin/wine bin/thcrap_loader.exe thcrap2nix.js "$LAUNCHPATH/custom.exe"
          else
            ${wine}/bin/wine "$LAUNCHPATH/custom.exe"
          fi
        fi
      ''; # launcherScript


      installPhase = ''
        mkdir -p $out/bin
        mkdir -p $out/share/thcrap-wrapper
        wrapperRoot=$out/share/thcrap-wrapper
        echo "Linking all files in base derivation"
        if ! [[ -z $baseDrv ]]; then
          ln -sv $baseDrv $wrapperRoot/base
        else
          echo "Base derivation is empty"
        fi

        if ! [[ -z $vpatchPath ]]; then
          echo "Applying vpatch"
          if [[ -e $vpatchPath/bin/vpatch_$thVersion.dll ]]; then
            ln -sv $vpatchPath/bin/vpatch_$thVersion.dll $wrapperRoot
            ln -sv $vpatchPath/bin/vpatch.exe $wrapperRoot
          else
            echo "Corresponding vpatch $vpatchPath/bin/vpatch_$thVersion.dll not found!"
            exit 1
          fi
        fi

        if ! [[ -z $thcrapPath ]]; then
          echo "Applying thcrap"
          mkdir -p $wrapperRoot/thcrap/bin
          mkdir -p $wrapperRoot/thcrap/logs
          ln -sv $thcrapPath/bin/* $wrapperRoot/thcrap/bin/
          ln -sv $thcrapConfigPath/* $wrapperRoot/thcrap/
          rm -v $wrapperRoot/thcrap/bin/thcrap_update.dll
        fi

        if ! [[ -z $thpracPath ]]; then
          echo "Applying thprac"
          ln -sv $thpracPath $wrapperRoot/thprac.exe
        fi

        echo "Creating wrapper script"
        ln -sv $launcherScript $out/bin/$name-raw
        wrapProgram $out/bin/$name-raw --set enableThprac "$enableThprac" --set enableVpatch "$enableVpatch" --set enableThcrap "$enableThcrap" --set gameExe "$gameExe" --set wrapperRoot "$wrapperRoot"
        ln -sv $launcherScriptBwrap $out/bin/$name
        wrapProgram $out/bin/$name --set wrapperPath "$out" --set wrapperRoot "$wrapperRoot" \
          --set enableThprac "$enableThprac" --set enableVpatch "$enableVpatch" --set enableThcrap "$enableThcrap" \
          --set enableBase "$enableBase"
        echo "Done!"
      ''; # installPhase
    }

