{
  description = "Development shell for operating Talos clusters";

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
              talosctl
              yq-go
            ];

            shellHook = ''
              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              export MISTSHIP_SECRETS_DIR="''${MISTSHIP_SECRETS_DIR:-$repo_root/.secret}"
              export TALOSCONFIG="''${TALOSCONFIG:-$MISTSHIP_SECRETS_DIR/talosconfig}"
              export KUBECONFIG="''${KUBECONFIG:-$MISTSHIP_SECRETS_DIR/kubeconfig}"

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
