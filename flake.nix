{
	description = "FaceFusion packaged as a Nix flake";

	inputs =
	{
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
		flake-utils.url = "github:numtide/flake-utils";
	};

	outputs = { self, nixpkgs, flake-utils }:
		flake-utils.lib.eachDefaultSystem (system:
			let
				pkgs = import nixpkgs { inherit system; };
				cudaPkgs = import nixpkgs {
					inherit system;
					config.allowUnfree = true;
				};
				isCudaSystem = system == "x86_64-linux";
				python = pkgs.python312.override {
					packageOverrides = final: prev:
					{
						"gradio-client" = prev.buildPythonPackage rec {
							pname = "gradio-client";
							version = "1.12.1";
							format = "wheel";
							nativeBuildInputs = [ prev.pythonRelaxDepsHook ];
							pythonRelaxDeps = [ "websockets" ];
							src = pkgs.fetchurl {
								url = "https://files.pythonhosted.org/packages/77/95/e248cabea8c5b1eaa69c0e4742e4d4cbb3708272670917daf8eef2f78aa1/gradio_client-1.12.1-py3-none-any.whl";
								sha256 = "37c0bcd0e6b3794b2b2e0b5039696d6962d8125bdb96960ad1b79412326b1664";
							};
							propagatedBuildInputs = with final;
							[
								fsspec
								httpx
								packaging
								websockets
							] ++
							[
								final."huggingface-hub"
								final."typing-extensions"
							];
							doCheck = false;
							pythonImportsCheck = [ "gradio_client" ];
						};

						gradio = prev.buildPythonPackage rec {
							pname = "gradio";
							version = "5.44.1";
							format = "wheel";
							nativeBuildInputs = [ prev.pythonRelaxDepsHook ];
							pythonRelaxDeps = [ "aiofiles" "huggingface-hub" "pydantic" "pillow" "tomlkit" ];
							src = pkgs.fetchurl {
								url = "https://files.pythonhosted.org/packages/e1/2f/8c2f8822217061888b68a8610c556d053983fe8759273c9a6fcf3f2fabca/gradio-5.44.1-py3-none-any.whl";
								sha256 = "cb22dd519c3bb2f8c7960cdcc23ca3b869511c85e320f486d7aef6e3627f97b9";
							};
							propagatedBuildInputs = with final;
							[
								aiofiles
								anyio
								brotli
								fastapi
								ffmpy
								groovy
								httpx
								jinja2
								markupsafe
								numpy
								orjson
								packaging
								pandas
								pillow
								pydantic
								pydub
								pyyaml
								requests
								ruff
								safehttpx
								starlette
								tomlkit
								typer
								uvicorn
							] ++
							[
								final."gradio-client"
								final."huggingface-hub"
								final."python-multipart"
								final."semantic-version"
								final."typing-extensions"
							];
							doCheck = false;
							pythonImportsCheck = [ "gradio" ];
						};

						"gradio-rangeslider" = prev.buildPythonPackage rec {
							pname = "gradio-rangeslider";
							version = "0.0.8";
							format = "wheel";
							src = pkgs.fetchurl {
								url = "https://files.pythonhosted.org/packages/54/44/14f759678a76ffbd6e3fe8852a4f758bc5ad51b379c67b5d167cfde752f6/gradio_rangeslider-0.0.8-py3-none-any.whl";
								sha256 = "3728c44e58ec1bff0bdf236cc84f12b183fbd596fb4714d8b797585a0515f89e";
							};
							propagatedBuildInputs = [ final.gradio ];
							doCheck = false;
							pythonImportsCheck = [ "gradio_rangeslider" ];
						};
					} // pkgs.lib.optionalAttrs isCudaSystem {
						"onnxruntime-gpu" = prev.buildPythonPackage rec {
							pname = "onnxruntime-gpu";
							version = "1.24.3";
							format = "wheel";
							src = pkgs.fetchurl {
								url = "https://files.pythonhosted.org/packages/24/fa/58ceca812214c9c1a286407c376e42e0b7de3e2c6e14b61cdf3caf6d6d9c/onnxruntime_gpu-1.24.3-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
								sha256 = "537bdd6d95006a9200ae81f2e73ba9e621e723fdf0deb5901e2e62fb2cccf876";
							};
							propagatedBuildInputs = with final;
							[
								flatbuffers
								numpy
								packaging
								protobuf
								sympy
							];
							doCheck = false;
						};
					};
				};
				pythonPkgs = python.pkgs;
				cudaRuntimeLibraries = with cudaPkgs;
				[
					stdenv.cc.cc.lib
					zlib
					cudaPackages.cuda_cudart
					cudaPackages.cuda_nvrtc
					cudaPackages.libcublas
					cudaPackages.libcufft
					cudaPackages.libcurand
					cudaPackages.libcusolver
					cudaPackages.libcusparse
					cudaPackages.libnpp
					cudaPackages.libnvjitlink
					cudaPackages.cudnn
				];
				cudaLibraryPath = cudaPkgs.lib.makeLibraryPath cudaRuntimeLibraries;
				facefusionPython = if isCudaSystem then python.withPackages (ps:
				[
					ps.gradio
					ps.numpy
					ps.onnx
					ps."onnxruntime-gpu"
					ps."opencv-python"
					ps.scipy
					ps.tqdm
					ps."gradio-rangeslider"
				]) else null;
				facefusionLauncher = if isCudaSystem then cudaPkgs.writeShellApplication {
					name = "facefusion";
					runtimeInputs = [ facefusionPython cudaPkgs.ffmpeg cudaPkgs.curl ];
					text = ''
						exec python "$FACEFUSION_SRC/facefusion.py" "$@"
					'';
				} else null;
				cudaDevShell = if isCudaSystem then cudaPkgs.mkShell {
					packages = [
						facefusionPython
						facefusionLauncher
						cudaPkgs.ffmpeg
						cudaPkgs.curl
					];

					shellHook = ''
						facefusion_src="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
						export FACEFUSION_SRC="$facefusion_src"
						export PYTHONPATH="$FACEFUSION_SRC''${PYTHONPATH:+:$PYTHONPATH}"
						export CUDA_PATH=${cudaPkgs.cudaPackages.cudatoolkit}
						export CUDA_HOME=${cudaPkgs.cudaPackages.cudatoolkit}
						export LD_LIBRARY_PATH=/run/opengl-driver/lib:${cudaLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
					'';
				} else null;
				facefusion = pythonPkgs.buildPythonApplication rec {
					pname = "facefusion";
					version = "3.6.0";
					format = "other";
					src = pkgs.lib.cleanSource ./.;

					propagatedBuildInputs = with pythonPkgs;
					[
						gradio
						numpy
						onnx
						onnxruntime
						opencv-python
						scipy
						tqdm
					] ++
					[
						pythonPkgs."gradio-rangeslider"
					];

					makeWrapperArgs =
					[
						"--prefix" "PATH" ":" (pkgs.lib.makeBinPath [ pkgs.curl pkgs.ffmpeg ])
					];

					installPhase = ''
						runHook preInstall

						mkdir -p "$out/${python.sitePackages}" "$out/bin"
						cp -r facefusion "$out/${python.sitePackages}/facefusion"
						install -Dm644 facefusion.ini "$out/${python.sitePackages}/facefusion.ini"
						install -Dm644 facefusion.ico "$out/${python.sitePackages}/facefusion.ico"
						install -Dm755 facefusion.py "$out/bin/facefusion"

						runHook postInstall
					'';

					doCheck = false;
					pythonImportsCheck = [ "facefusion" ];

					meta = with pkgs.lib;
					{
						description = "Industry leading face manipulation platform";
						homepage = "https://facefusion.io";
						mainProgram = "facefusion";
						platforms = platforms.linux;
					};
				};
			in
			{
				packages.default = facefusion;
				packages.facefusion = facefusion;
				apps.default = flake-utils.lib.mkApp { drv = facefusion; };
			} // pkgs.lib.optionalAttrs isCudaSystem {
				devShells.default = cudaDevShell;
				devShells.cuda = cudaDevShell;
			});
}
