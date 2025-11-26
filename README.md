# Nazi Zombies: Portable Toolbox

## About

NZ:P Toolbox (or just _"Toolbox"_) is a small suite of glue code and infrastructure to support NZ:P developers, modders, and map makers in creation of content by leveraging our systems we use for both CI and local development.

Toolbox leverages Docker to set up a virtual environment separate from your host to do this, while also utilizing Python venvs to allow various development components to share a space and not interfere with one another.

## Features

Toolbox can do the following in its current state:

* `fetch`: Clones various repositories under the [nzp-team GitHub organization](https://github.com/nzp-team), setting up Python virtual environments where necessary. Running `fetch` after a clone will pull latest changes from main. This will run on first start-up if not manually invoked.

* `new-map`: Create a new `.map` file from the template in [assets](https://github.com/nzp-team/assets), already in a buildable state with some basic rooms built for testing.

* `build-wads`: Builds WAD texture archives in [assets](https://github.com/nzp-team/assets) stored as PNG files in `source/textures/wad/` for easy modification or creation of texture WADs.

* `build-map`: Builds all or a specific `.map` into a BSP going through the entire map compilation process, including Spawn Zone generation. Special arguments are supported via `.arg` files in the same path as the `.map`. This can easily be hooked up to TrenchBroom to never have to self-manage map compilation.

* `build-quakec`: Compiles latest [QuakeC](https://github.com/nzp-team/quakec) changes from `main` branch. Useful for mods or debugging.

## Usage/Installation

1: Install [Docker](https://www.docker.com/)

2: [Download](https://github.com/nzp-team/toolbox/archive/refs/heads/main.zip) this repository (releases are TBD and depend on growth and strategy changes)

3a: On systems with Bash or other UNIX shells:
```bash
./nzp fetch
```
3b: On Windows:
```cmd
nzp.cmd fetch
```

4: Profit. You can use `nzp help` for the complete command list (including optional and required parameters)