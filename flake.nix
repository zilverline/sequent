{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, systems, ... } @ inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem (system: {
        devenv-up = self.devShells.${system}.default.config.procfileScript;
        devenv-test = self.devShells.${system}.default.config.test;
      });

      devShells = forEachSystem
        (system:
          let
            postgresPort = 6543;
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [
                {
                  env.PGPORT = postgresPort;
                  env.SEQUENT_ENV = "test";

                  enterTest = ''
                    reset-database
                    run-tests
                  '';

                  git-hooks.hooks.rubocop = {
                    enable = true;
                    name = "rubocop";
                    types = [ "ruby" ];
                    excludes = [
                      "^docs/.*$"
                      "^integration-specs/rails-app/(bin|db)/.*$"
                      "^integration-specs/rails-app/config/puma.rb$"
                    ];
                    entry = "bundle exec rubocop";
                  };

                  languages.ruby = {
                    enable = true;
                    package = pkgs.ruby;
                  };

                  processes.jekyll.exec = ''
                    cd docs
                    bundle
                    bundle exec jekyll serve --livereload
                  '';

                  services.postgres = {
                    enable = true;
                    listen_addresses = "127.0.0.1";
                    port = postgresPort;
                    initialScript = ''
                      CREATE ROLE sequent LOGIN SUPERUSER;
                    '';
                    settings = {
                      log_min_duration_statement = "100ms";
                    };
                  };

                  # https://devenv.sh/reference/options/
                  packages = with pkgs; [
                    libyaml
                    pkg-config
                    postgresql
                  ];

                  scripts.lint.exec = "bundle exec rubocop";
                  scripts.run-tests.exec = "bundle exec rspec";
                  scripts.reset-database.exec = "bundle exec rake sequent:db:drop sequent:db:create";
                }
              ];
            };
          });
    };
}
