{
  description = "Development shell for bootstrapping Talos clusters locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          talosctlAsset =
            if system == "x86_64-linux" then {
              suffix = "linux-amd64";
              hash = "sha256-TEGjsQsHUpLmSxgig9VY6djpNfQyOd4e1OSxQ1lZPvs=";
            } else if system == "aarch64-linux" then {
              suffix = "linux-arm64";
              hash = "sha256-TSglTubqmUu7C8pJsgR9aczJD6n/sgBBlRQygEQ62hY=";
            } else if system == "x86_64-darwin" then {
              suffix = "darwin-amd64";
              hash = "sha256-hsw6NDUV+sNAQvDR0vnn2cZ9hXieFIqRO13gvzIJMJU=";
            } else if system == "aarch64-darwin" then {
              suffix = "darwin-arm64";
              hash = "sha256-JZ8MrFSSUqKfOXA9mSkXR5zskJoOqBE8OojUACs5UoU=";
            } else
              throw "Unsupported system for talosctl pin: ${system}";
          talosctlPinned = pkgs.stdenvNoCC.mkDerivation rec {
            pname = "talosctl";
            version = "1.12.6";
            src = pkgs.fetchurl {
              url = "https://github.com/siderolabs/talos/releases/download/v${version}/talosctl-${talosctlAsset.suffix}";
              hash = talosctlAsset.hash;
            };

            dontUnpack = true;

            installPhase = ''
              install -Dm755 "$src" "$out/bin/talosctl"
            '';
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              age
              jq
              kubectl
              kubeconform
              sops
              talhelper
              talosctlPinned
              yq-go
            ];

            shellHook = ''
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              export MISTSHIP_SECRETS_DIR="''${MISTSHIP_SECRETS_DIR:-$repo_root/.secret}"

              if [[ -z "''${TALOSCONFIG:-}" ]]; then
                if [[ -f "$repo_root/talosconfig" ]]; then
                  export TALOSCONFIG="$repo_root/talosconfig"
                else
                  export TALOSCONFIG="$MISTSHIP_SECRETS_DIR/talosconfig"
                fi
              fi

              if [[ -z "''${KUBECONFIG:-}" ]]; then
                if [[ -f "$repo_root/kubeconfig" ]]; then
                  export KUBECONFIG="$repo_root/kubeconfig"
                else
                  repo_kubeconfig="$(find "$repo_root" -path "$MISTSHIP_SECRETS_DIR" -prune -o -type f \( -name kubeconfig -o -name '*.kubeconfig' \) -print -quit 2>/dev/null)"
                  if [[ -n "$repo_kubeconfig" ]]; then
                    export KUBECONFIG="$repo_kubeconfig"
                  else
                    export KUBECONFIG="$MISTSHIP_SECRETS_DIR/kubeconfig"
                  fi
                fi
              fi

              echo "mistship Talos shell"
              echo "  REPO_ROOT=$repo_root"
              echo "  MISTSHIP_SECRETS_DIR=$MISTSHIP_SECRETS_DIR"
              echo "  TALOSCONFIG=$TALOSCONFIG"
              echo "  KUBECONFIG=$KUBECONFIG"
            '';
          };
        });

      formatter = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixpkgs-fmt);
    };
}
