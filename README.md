# Kubebar

Native macOS menu bar app for Kubernetes context management.

```
🔴 gateway    <- red = remote cluster
⬡ docker-de… <- normal = localhost
```

## Features

- Shows current k8s context in menu bar (truncated to 10 chars)
- Red indicator (🔴) for remote clusters, normal (⬡) for localhost
- Click to see all contexts and switch between them
- Auto-refreshes every 2 seconds
- Zero dependencies beyond macOS and kubectl

## Installation

### From source

```bash
git clone https://github.com/jelmersnoeck/kubebar.git
cd kubebar
make install
```

This compiles the app and copies it to `/Applications/Kubebar.app`.

### Manual build

```bash
make build    # compile only
make run      # compile and launch
make stop     # kill running instance
make restart  # stop + run
```

## Requirements

- macOS 13+
- `kubectl` in PATH

## Localhost detection

The following server patterns are considered "local" (no red warning):

- `localhost`
- `127.0.0.1`
- `0.0.0.0`
- `host.docker.internal`
- `kubernetes.docker.internal`

Everything else shows the red indicator.

## License

MIT
