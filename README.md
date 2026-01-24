# Config And Installers For Software - CAIFS v(0.5.0)

CAIFS is a tool to handle installing software across various unix-like operating systems. If you work with multiple
flavours of linux, build docker containers and work with macs, then this tool will help you consistently install
software and matching configuration across all of them.

CAIFS takes inspiration from Stow and especially Tuckr, in that it is a dotfile manager, with the ability to run
scripts. Unlike Tuckr though, CAIFS takes it a step further and allows you to define different installs for different
operating systems and even architectures. This is done via hook scripts and defining custom functions per os-flavour

For example, the following hook script (a `pre.sh` in this case), demonstrates how a single hook script can be defined
to work across operating systems, in this case installing curl in three different ways.

``` shell

fedora() {
    rootdo dnf install -y curl
}

macos() {
    brew install curl
}

debian() {
    rootdo apt-get install -y curl
}
```

Running the hooks on your Fedora, MacOS or Debian host in this case would be performed by

`caifs add curl --hooks`

Running the equivalent in a docker file, after a bootstrap gives you consistency

``` Dockerfile
FROM debian:trixie-slim

RUN curl -sL https://raw.githubusercontent.com/caifs-org/caifs/refs/heads/main/install.sh | sh && \
    caifs add caifs-common -d . && \
    caifs add docker-cli  --hooks

# Your other docker image build
...

```

Simplified dependency management in a GitHub Pipeline

``` yaml
...
  steps:
    - name: Add the dependencies to the runner
      run: |
        curl -sL https://raw.githubusercontent.com/caifs-org/caifs/refs/heads/main/install.sh | sh
        caifs add caifs-common
        caifs add uv ruff pre-commit rumdl docker-cli trivy just

    - name: Run pre-commit checks
      run: |
        pre-commit run --all
```

## Other good reasons to use CAIFS

- 100% pure POSIX compliant shell. So it should run just about everywhere
- less than 60kb in size, so it won't take up precious space in your Docker builds
- It has zero dependencies, besides coreutils functions such as find, `sed`, `grep`, `dirname`, `realpath`, `pathchk`...

> [!NOTE]
> This CAIFS repo itself is a valid caifs collection, containing a single target, caifs!
> See a curated library of scores of more installers at <https://github.com/caifs-org/caifs-common/>

## Install and Usage

YOLO it onto your system to install locally within `~/.local/`

`curl -sL https://raw.githubusercontent.com/caifs-org/caifs/refs/heads/main/install.sh | sh`

OR

Install globally by using env var `INSTALL_PREFIX=/usr/local/` and root privileges

`INSTALL_PREFIX=/usr/local/ curl -sOL https://raw.githubusercontent.com/caifs-org/caifs/refs/heads/main/install.sh | sudo sh -c`

Check it's working and on your path with -

`caifs --version` or `caifs --help`

OR

Clone the repository and install CAIFS, using CAIFS

``` shell
git clone https://github.com/caifs-org/caifs/caifs.git
./caifs/config/bin/caifs add caifs -d . --link-root "$HOME/.local"
```

### Enable caifs-common collection (optional but recommended)

(caifs-common)<https://github.com/caifs-org/caifs-common> is a collection of curated installs of commonly used developer
software that can be enabled via the caifs library.

```shell
caifs add caifs
caifs add caifs-common -d . 
```

This will grab the latest `caifs-common` release and place it into `~/.local/share/caifs-collections/caifs-common` CAIFS
automatically looks for this library so there is no need to add it to the `$CAIFS_COLLECTIONS` environment variable or
specify it directly with the `caifs add --directory <switch>` switch.

> ![TIP]
> Running `caifs add caifs-common` periodically will grab the latest version and keep it up to date

## Collection Structure

A CAIFS collection is a directory containing targets. Each target has a `config/` directory for files to symlink and an
optional `hooks/` directory for install scripts.

```text
my-dotfiles/
├── git/
│   ├── config/
│   │   ├── .gitconfig
│   │   └── .gitconfig.d/
│   │       └── aliases.config
│   └── hooks/
│       └── pre.sh
├── bash/
│   └── config/
│       ├── .bashrc
│       └── .bashrc.d/
│           └── aliases.bash
└── nvim/
    └── config/
        └── .config/
            └── nvim/
                └── init.lua
```

**Config files** mirror their destination path relative to `$HOME` (or `$CAIFS_LINK_ROOT`):

- `git/config/.gitconfig` → `~/.gitconfig`
- `nvim/config/.config/nvim/init.lua` → `~/.config/nvim/init.lua`

Three types of hooks exist, `pre.sh`, `post.sh` and `rm.sh`. Following on from the above example, if you wanted to do a
`pre.sh` hook that installed git, before the configuration was symlinked across, then this would like like:

`git/hooks/pre.sh`

**Hook scripts** define functions named after OS identifiers. CAIFS detects the OS and calls the matching function:

``` shell
# git/hooks/pre.sh

fedora() {
    rootdo dnf install -y git-core
}

ubuntu() {
    rootdo apt-get install -y git
}

arch() {
    rootdo pacman -S --noconfirm git
}

macos() {
    brew install git
}

linux() {
    # Runs on any Linux after the distro-specific function
    echo "Git installed on Linux"
}

generic() {
    # Runs on all platforms last
    echo "Git setup complete"
}
```

Available function names:

- Distro-specific: `fedora`, `ubuntu`, `arch`, `debian`, etc. (from `/etc/os-release` ID)
- `linux` - any Linux system
- `macos` - macOS/Darwin
- `generic` - all platforms
- `container` - runs when inside a container (Docker, Podman, LXC, etc.)
- `portable` - runs when on a portable device (laptop, notebook, etc.)

### CA trust updates

It's often common in enterprise setups to require a custom certificate to be installed to maintain the certificate
trust chain. For these scenarios, any given target should create a certificate file within the following structure:

`<target>/config/.local/share/certificates/my_cert.crt`

Of course, no OS updates their trust chain in the same way, so CAIFS provides a series of OS identifier wrapper
functions to manage the various OS specific tasks to get that cert into the system wide cert trust.

From a `post.sh` hook script (because we need it to run after the linking), call the `install_certs()` function, from
either of the handlers or as a fail safe, within the more generic `linux()` handler, like so:

``` shell
# enterprise-certs/hooks/post.sh

linux() {
    install_certs
}

```

## Usage Examples

``` shell

# bootstrap your system the caifs-common library, which contains everything below
caifs add caifs-common -d .

# does symlinking and pre/post hooks for target uv
caifs add uv

# does only symlinking for target uv
caifs add uv --links

# does only hooks for target uv
caifs add uv --hooks

# run multiple hooks for targets uv, ruff and poetry in that order
caifs add uv ruff poetry --hooks

# force an override of bash config files if the links exist already
caifs add bash --links --force

# run over multiple collections, with a first-link wins scenario
caifs add git -d ~/my-personal-collection -d ~/my-work-collection

# same as above, but using the environment variable to replace the -d|--directory option
CAIFS_COLLECTIONS="~/my-personal-collection:~/my-work-collection" \
    caifs add git

# remove symlinks for a target
caifs rm git -d ~/my-dotfiles --links

# run remove hook script
caifs rm git -d ~/my-dotfiles --hooks
```

## Environment Variables

| Variable                  | Default                          | Description                                                                    |
|---------------------------|----------------------------------|--------------------------------------------------------------------------------|
| `CAIFS_COLLECTIONS`       | `$PWD`                           | Colon-separated list of collection paths to search for targets                 |
| `CAIFS_LINK_ROOT`         | `$HOME`                          | Destination root for symlinks (e.g., set to `/` for system-wide configs)       |
| `CAIFS_VERBOSE`           | `1`                              | Set to `0` to enable debug output                                              |
| `CAIFS_RUN_FORCE`         | `1`                              | Set to `0` to force overwrite existing files/links                             |
| `CAIFS_RUN_LINKS`         | `0`                              | Set to `1` to skip symlinking (equivalent to `--hooks`)                        |
| `CAIFS_RUN_HOOKS`         | `0`                              | Set to `1` to skip hooks (equivalent to `--links`)                             |
| `CAIFS_DRY_RUN`           | `1`                              | Set to `0` to show what would run without making changes                       |
| `CAIFS_IN_CONTAINER`      | unset                            | Set to `0` to set container config to run + triggers `container()` hooks).     |
|                           |                                  | Set to `1` to specify not in container, regardless of if in a container or not |
| `CAIFS_IN_WSL`            | unset                            | Set to `0` to set WSL config to run. Set to `1` to force to run                |
| `CAIFS_LOCAL_COLLECTIONS` | ~/.local/share/caifs-collections | A central store for collections that is automatically checked.                 |
|                           |                                  |                                                                                |

## Advanced Configuration

### Define multiple collections

Enabling multiple collections allows you to separate out your personal (and preferred) configuration into one collection
,then for instance, a work-specific collection defined, followed by the standard `caifs-common` library.

When you runs CAIFS, it will search all the collections, with the order you specify the collections in being the order
of operations.

There are a few options to support this.

#### CLI arguments

Using the `-d|--directory` arguments *will* override any `$CAIFS_COLLECTIONS` variable set, allowing you to work with a
collection in isolation.

#### CAIFS_COLLECTIONS environment variable

The environment variable, `$CAIFS_COLLECTIONS`, can be set with multiple `:`-delimited directory paths. Much like the
standard `$PATH` variable. Setting this variable is the equivalent of supplying multiple `-d|--directory`
arguments to the `caifs add|rm` command itself.

#### Built in mechanism aka caifs-ception

When `caifs` is run with no `-d|--directory` arguments and the `$CAIFS_COLLECTIONS` variable is empty, then CAIFS will
internally look to an XDG area of `~/.local/share/caifs-collections/` for collections to process.

CAIFS will look only 1 level deep in that directory and then attempt to validate that they are in-fact, caifs
compatible directories. It adds each collection it finds to the back of the queue (internally the queue is just the
`$CAIFS_COLLECTIONS` variable), that is to say, the order of the collections in `~/.local/share/caifs-collections/` is
important and is dictated by the `find` defaults.

The one exception to this, is the `caifs-common` library. If present, then this collection will always be at the back
of the line. Allowing people to override configuration if they wish.

### Install to non-$HOME area

By default, CAIFS configuration will be linked to the current `$HOME` variable. This is desirable for most use cases
where you want to manage personal dotfiles.

If you need to manage files beyond the `$HOME` area, perhaps you have some custom networking that is required to be
added underneath `/` - then CAIFS has two options.

#### Leading ^ character in config path

A config file under `<target>/config/` with a leading `^` will be interpreted as being a `/` or root level file. For
example, `my_sudo/config/^etc/sudoers.d/01-mysudo.conf` will be attempted to be linked to
`/etc/sudoers.d/01-mysudo.conf`

Attempted, because CAIFS will attempt to escalate privileges

1. CAIFS is currently running as root, i.e. uid=0, run `<the command>` as is.
2. sudo is available and run `sudo <the command>`
3. fallback to `su -c <the command>` to issue the command

> [!NOTE]
> Some of these options may prompt for passwords, depending on your setup

#### Altering the CAIFS_LINK_ROOT variable

It may be useful in certain situations, particularly in docker builds which generally run as root, to set an alternative
to the default `$HOME` destination for links.

You can specify this with the `-r|--link-root` flags for the `add|rm` commands or use the `$CAIFS_LINK_ROOT` environment
variable

In a typical docker builds, or perhaps escalated automation scenarios where you are running as root, but want the
configuration to be placed into another users home directory.

``` Dockerfile
FROM debian:trixie-slim

# Add an app user with a home directory at /app
RUN useradd \
    --create-home \
    --home-dir /app \
    --uid 1000 \
    --shell /bin/sh \
    appuser


# Copy over a collection, or perhaps curl one on from github
COPY my-docker-collection /usr/local/share/my-docker-collection

# install some software and add the config from a custom collection, but
# create the links at the link-root of /app/
RUN curl -sL https://github.com/caifs-org/caifs/install.sh | sh && \
    caifs add -d . caifs-common && \
    caifs add uv git pre-commit ruff \
      --link-root /app \
      -d /usr/local/share/my-docker-collection
```

#### WSL, Container, or Portable specific configuration

Besides the standard `<target>/config` directory, CAIFS caters for environment-specific config. To enable a specific set
of configuration that should only be linked in a particular environment, provide an alternative directory:

- `<target>/config_wsl` - for WSL environments
- `<target>/config_container` - for container environments (Docker, Podman, LXC, etc.)
- `<target>/config_portable` - for portable devices (laptops, notebooks, convertibles, etc.)

> [!NOTE]
> The order of precedence for multiple config directories is `config_portable/`, `config_container/`, `config_wsl/`, `config/`.
> This effectively allows you to prevent environment-specific configuration from being clobbered by similarly named configuration
> within the main `config/` directory.

### Command Options

| Option            | Env Variable        | Description                                |
|-------------------|---------------------|--------------------------------------------|
| `--verbose`, `-v` | `CAIFS_VERBOSE=0`   | Show debug logs                            |
| `--force`, `-f`   | `CAIFS_RUN_FORCE=0` | Remove existing links/files on conflict    |
| `--links`, `-l`   | `CAIFS_RUN_LINKS=0` | Run only links, disable hooks              |
| `--hooks`, `-h`   | `CAIFS_RUN_HOOKS=0` | Run only hooks, disable links              |
| `--dry-run`, `-n` | `CAIFS_DRY_RUN=0`   | Show what would run without making changes |
