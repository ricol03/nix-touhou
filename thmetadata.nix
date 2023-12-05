let
  mkRelative = paths: {
    mutable = {
      type = "relative";
      inherit paths;
    };
  };
in
  {
    th06 = mkRelative [ "東方紅魔郷.cfg" "score.dat" "replay/" "log.txt" ];

    th07 = mkRelative [ "th07.cfg" "score.dat" "replay/" "log.txt" ];
    th08 = mkRelative [ "th08.cfg" "score.dat" "replay/" "log.txt" ];
    th09 = mkRelative [ "th09.cfg" "score.dat" "replay/" "log.txt" ];
    th095 = mkRelative [ "th095.cfg" "scoreth095.dat" "replay/" "log.txt" ];
    th10 = mkRelative [ "th10.cfg" "scoreth10.dat" "replay/" "log.txt" ];
    th11 = mkRelative [ "th11.cfg" "scoreth11.dat" "replay/" "log.txt" ];
    th12 = mkRelative [ "th12.cfg" "scoreth12.dat" "replay/" "log.txt" ];
    th125.mutable.type = "appdata";
    th128.mutable.type = "appdata";
    th13.mutable.type = "appdata";
    th14.mutable.type = "appdata";
    th15.mutable.type = "appdata";
    th16.mutable.type = "appdata";
    th165.mutable.type = "appdata";
    th17.mutable.type = "appdata";
    th18.mutable.type = "appdata";
    th185.mutable.type = "appdata";
    th19.mutable.type = "appdata";
  }
