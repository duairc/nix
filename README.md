# Haskell nix integration

There are many guides and tools out there for using Nix to build Haskell projects, but none of them are Invented Here.

My one can be used as follows:

```bash
git submodule add https://github.com/duairc/nix
nix/setup
```

## Overview

1. Simple setup.
2. Zero maintenance; all derivations are built dynamically from `.cabal` file(s) and `cabal.project` file (if present).
3. You get a working "root" `default.nix` and `shell.nix` for your entire project, and individual "leaf" `default.nix` and `shell.nix` for each subproject.
4. The "root" `shell.nix` includes the transitive build-dependencies of all subprojects, minus the subprojects themselves. This allows `cabal`'s to do most of the work when you're doing incremental development across multiple subprojects at a time.
5. It uses a pinned `nixpkgs` for maximum reproducibility. The `setup` script by default uses the latest `nixpkgs-unstable` commit, but you can use whatever commit you want by editing the `nixpkgs.json` file that gets created.
6. All `nix-shell`s include a Hoogle with the dependencies of that project indexed. This can be configured either in `options.nix` or on the command-line by passing `--arg hoogle false` to `nix-shell`.
7. You can use configure the version of GHC you use, either in `options.nix` or on the command-line by passing `--argstr ghc ghc865` to `nix-shell`.
8. A `config.nix` which is read and passed to `nixpkgs`; you can use this to set options like `allowUnfree` or `allowBroken` as required.
9. An `overrides.nix`, where you can can say things like `generic-lens = dontCheck super.generic-lens_1_2_0_1`.
10. The setup script is idempotent, it won't clobber any changes you've made. However you might want to run it again if you add new packages to your `cabal.project` and you want to generate `default.nix` and `shell.nix` files for them.
