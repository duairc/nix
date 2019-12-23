with builtins;
rec {
  dotCabal = dir: let
    base = baseNameOf dir;
  in {
    "${base}" = dir + "/${base}.cabal";
  };

  cabalPackages = dir: let
    # Here we "parse" a cabal.project file with hacky regexes. It doesn't
    # handle globs or URLs, but conceivably this could be added.
    files = let
      entries = let
        path = dir + "/cabal.project";
        contents = readFile path;
        regex = ".*([\n]|^)packages[ ]*:((([ ]*[^ \n]+)*)(\n[ ]+([^ \n]+[ ]*)*)*).*";
        matches = match regex contents;
        lines = split "[\n ]+" (elemAt matches 1);
      in filter (line: isString line && line != "") lines;

      toFile = entry: let
        path = dir + "/${entry}";
      in if util.isDir path
        then path + "/${baseNameOf path}.cabal"
        else path;
    in map toFile entries;

    cabalDotProject = let
      toPackage = cabal: {
        name = replaceStrings [".cabal"] [""] (baseNameOf cabal);
        value = cabal;
      };
    in listToAttrs (map toPackage files);

    packages = if util.findParent "cabal.project" dir == null
      then dotCabal dir
      else cabalDotProject;
  in packages;

  options = f: dir: {dev ? null, ghc ? null, hoogle ? null, ...}@args: let
    defaults = {
      dev = true;
      ghc = null;
      hoogle = true;
    };
    settings = if pathExists (dir + "/options.nix")
      then import (dir + "/options.nix")
      else {};
    opts = defaults // settings // args;
  in f dir opts;

  config = dir: opts: let
    preconfig = if pathExists (dir + "/config.nix")
      then import (dir + "/config.nix")
      else {};

    overrides = if pathExists (dir + "/overrides.nix")
      then import (dir + "/overrides.nix")
      else _: _: _: {};

    projects = pkgs: let
      gitignoreSrc = pkgs.fetchFromGitHub { 
        owner = "hercules-ci";
        repo = "gitignore";
        rev = "7415c4feb127845553943a3856cbc5cb967ee5e0";
        sha256 = "1zd1ylgkndbb5szji32ivfhwh04mr1sbgrnvbrqpmfb67g2g3r9i";
      };
      inherit (import gitignoreSrc { inherit (pkgs) lib; }) gitignoreFilter;
    in self: super: let
      go = name: package: let
        src = dirOf package;
      in self.callCabal2nix name (pkgs.lib.cleanSourceWith {
        inherit name src;
        filter = gitignoreFilter src;
      }) {};
    in mapAttrs go (cabalPackages dir);

  in preconfig // {
    packageOverrides = oldpkgs: let
      pkgs = (preconfig.packageOverrides or (p: p)) oldpkgs;
      projects' = projects pkgs;
      compose = old: {
        overrides = pkgs.lib.composeExtensions
          (pkgs.lib.composeExtensions (old.overrides or (_: _: {})) projects')
          (overrides pkgs);
      };
    in if opts.ghc == null then {
      haskellPackages = pkgs.haskellPackages.override compose;
    }
    else {
      haskell = pkgs.haskell // {
        packages = pkgs.haskell.packages // {
          "${opts.ghc}" = pkgs.haskell.packages."${opts.ghc}".override compose;
        };
      };
    };
  };

  packages = dir: opts: let
    nixpkgs = fromJSON (readFile (dir + "/nixpkgs.json"));
    src = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgs.rev}.tar.gz";
      inherit (nixpkgs) sha256;
    };
  in import src {
    config = config dir opts;
  };

  haskellPackages = dir: opts: let
    pkgs = packages dir opts;
  in if opts.ghc == null
    then pkgs.haskellPackages
    else pkgs.haskell.packages."${opts.ghc}";

  metarelease = cabals: options (dir: opts: let
    pkgs = packages dir opts;
    hspkgs = haskellPackages dir opts;
    go = name: let
      package = getAttr name hspkgs;
    in [
      {
        name = name;
        value = package;
      }
      # This would be nice to have but doesn't do anything useful yet AFAICT
      #{
      #  name = "${name}-static";
      #  value = pkgs.haskell.lib.justStaticExecutables package;
      #}
    ];
    in listToAttrs (concatMap go (attrNames cabals)));

  release = dir: metarelease (cabalPackages dir) dir;
  subrelease = dir: subdir: metarelease (dotCabal subdir) dir;

  metashell = cabals: options (dir: opts: let
    pkgs = packages dir opts;
    hspkgs = haskellPackages dir opts;
    project = p: map (n: getAttr n p) (attrNames cabals);
    shell = (hspkgs.shellFor {
      packages = project;
      withHoogle = opts.hoogle;
    }).overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ (with hspkgs; [
        ghcid cabal-install
      ]);
    });
    full = pkgs.mkShell {
      buildInputs = [
        (hspkgs.ghcWithPackages project)
      ];
    };
  in if opts.dev then shell else full);

  shell = dir: metashell (cabalPackages dir) dir;
  subshell = dir: subdir: metashell (dotCabal subdir) dir;

  util = rec {
    isDir = path: pathExists path
        && getAttr (baseNameOf path) (readDir (dirOf path)) == "directory";

    findParent = file: let
      loop = dir: if pathExists (dir + "/${file}")
        then dir
        else let parent = /. + dirOf dir; in if parent == /.
          then null
          else loop parent;
    in loop;
  };
}
