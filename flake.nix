{
  description = "A collection of services enabling the users to perform inference on LLM models";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };
  outputs = {nixpkgs, ...} @ inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;
      imports = [
        inputs.process-compose-flake.flakeModule
        # (import ./overlays)
      ];
      perSystem = {
        self',
        pkgs,
        lib,
        system,
        ...
      }
      : {
        _module.args.pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        packages.default = self'.packages.services-flake-llm;

        process-compose."services-flake-llm" = pc: {
          _module.args.pkgs = import inputs.nixpkgs {
            config.allowUnfree = true;
            overlays = [
              (self: super: {
                config.allowUnfree = true;
                ollama = super.ollama.override {
                  acceleration = "cuda";
                  config = {
                    rocmSupport = false;
                    cudaSupport = true;
                  };
                };
              })
            ];
            # inherit system;
          };
          # inputs.nixpkgs.config = {
          #   allowUnfree = true;
          # };
          imports = [
            inputs.services-flake.processComposeModules.default
          ];
          services = let
            dataDirBase = "$HOME/.services-flake/llm";
          in {
            # Backend service to perform inference on LLM models
            ollama."ollama1" = {
              enable = true;

              # The models are usually huge, downloading them in every project
              # directory can lead to a lot of duplication. Change here to a
              # directory where the Ollama models can be stored and shared across
              # projects.
              dataDir = "${dataDirBase}/ollama1";

              # Define the models to download when our app starts
              #
              # You can also initialize this to empty list, and download the
              # models manually in the UI.
              models = [
                "codestral"
                "llama3"
                # "llama2-uncensored"
              ];

              package = pkgs.ollama.override {
                acceleration = "cuda";
                config = {
                  rocmSupport = false;
                  cudaSupport = true;
                };
              };
            };

            # Get ChatGPT like UI, but open-source, with Open WebUI
            open-webui."open-webui1" = {
              enable = true;
              dataDir = "${dataDirBase}/open-webui";
              environment = let
                inherit (pc.config.services.ollama.ollama1) host port;
              in {
                ENABLE_OLLAMA_API = "True";
                OLLAMA_BASE_URL = "http://${host}:${toString port}";
                OLLAMA_API_BASE_URL = "http://${host}:${toString port}/api";
                WEBUI_AUTH = "False";
                DEVICE_TYPE = "cuda";
                RAG_EMBEDDING_ENGINE = "ollama";
                RAG_EMBEDDING_MODEL = "mxbai-embed-large:latest";
                RAG_EMBEDDING_MODEL_AUTO_UPDATE = "True";
                RAG_RERANKING_MODEL_AUTO_UPDATE = "True";
                DOCS_DIR = "${dataDirBase}/docs";
              };
            };
          };

          # Start the Open WebUI service after the Ollama service has finished initializing and loading the models
          settings.processes.open-webui1.depends_on.ollama1-models.condition = "process_completed_successfully";

          # Open the browser after the Open WebUI service has started
          settings.processes.open-browser = {
            command = let
              inherit (pc.config.services.open-webui.open-webui1) host port;
              opener =
                if pkgs.stdenv.isDarwin
                then "open"
                else lib.getExe' pkgs.xdg-utils "xdg-open";
              url = "http://${host}:${toString port}";
            in "${opener} ${url}";
            depends_on.open-webui1.condition = "process_healthy";
          };
        };
      };
    };
}
