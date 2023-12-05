{
  stdenvNoCC,
  unzip,
  fetchurl,
}:
  stdenvNoCC.mkDerivation {
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
      mkdir -p $out
      cp -r ./bin ./repos $out
    '';
  }
