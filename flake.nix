{
  description = "Evervault Pay SDK";

  # Flake inputs
  inputs = {
    # Latest stable Nixpkgs
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
  };

  # Flake outputs
  outputs = { self, nixpkgs }:
    let
      # Systems supported
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      # Helper to provide system-specific attributes
      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
      });
    in
    {
      # Development environment output
      devShells = forAllSystems ({ pkgs }:
        let
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            platformVersions = [ "33" ];
            buildToolsVersions = [ "36.0.0" ];
            includeEmulator = false;
            includeSystemImages = false;
            includeNDK = false;
          };
          androidSdk = "${androidComposition.androidsdk}/libexec/android-sdk";
        in
        {
          default = pkgs.mkShell {
            # The Nix packages provided in the environment
            packages = with pkgs; [
              nodejs_20
              openjdk17
              cocoapods
              androidComposition.androidsdk
            ];

            ANDROID_HOME = androidSdk;
            ANDROID_SDK_ROOT = androidSdk;

            JAVA_HOME = pkgs.openjdk17.home;

            GRADLE_OPTS =
              "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidSdk}/build-tools/36.0.0/aapt2";

            shellHook = ''
              echo "[INFO] Using Node: $(node -v)"
              echo "[INFO] ANDROID_HOME set to $ANDROID_HOME"
            '' + pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
              export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
              # Use Xcode's toolchain
              export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
              export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

              export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
              echo "[INFO] Xcode SDK root: $SDKROOT"
              echo "[INFO] clang path: $(which clang)"
            '' + ''

              # Use system installed tools first.
              export PATH="/usr/bin:$PATH"
            '';
          };
        });
    };
}
