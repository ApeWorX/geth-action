# Install Geth GitHub Action

A GitHub Action to install [Go Ethereum (Geth)](https://geth.ethereum.org/) on Linux, macOS, and Windows runners.

## Features

- 🖥️ **Cross-platform support**: Works on Ubuntu, macOS, and Windows runners
- 📦 **Smart version resolution**: Supports `latest`, semantic versions, and `v`-prefixed tags
- 🚀 **Fast installation**: Downloads pre-built binaries directly from official sources
- ✅ **Automatic PATH setup**: Geth is immediately available after installation
- 🔧 **Zero configuration**: Works out of the box with sensible defaults
- 📊 **Version output**: Returns the actual installed version for use in subsequent steps

## Usage

### Basic Usage

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Install Geth
    uses: ApeWorX/geth-action@v1
    with:
      version: "latest" # or '1.13.5' or 'v1.13.5'

  - name: Use Geth
    run: geth version
```

### Install Latest Version

```yaml
steps:
  - name: Install latest Geth
    id: install-geth
    uses: ApeWorX/geth-action@v1
    with:
      version: "latest"

  - name: Show installed version
    run: echo "Installed Geth ${{ steps.install-geth.outputs.version }}"
```

### Install Specific Version

```yaml
steps:
  - name: Install Geth 1.13.5
    uses: ApeWorX/geth-action@v1
    with:
      version: "1.13.5" # Can also use 'v1.13.5'
```

### Matrix Testing

Test your project with multiple Geth versions across different operating systems:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
    geth-version: ["latest", "1.13.5", "v1.13.4"]

runs-on: ${{ matrix.os }}

steps:
  - uses: actions/checkout@v4

  - name: Install Geth
    id: install
    uses: ApeWorX/geth-action@v1
    with:
      version: ${{ matrix.geth-version }}

  - name: Run tests
    run: |
      echo "Testing with Geth ${{ steps.install.outputs.version }}"
      geth version
      # Your test commands here
```

### Advanced Example with Caching

Speed up workflows by caching Geth installations:

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Cache Geth
    id: cache-geth
    uses: actions/cache@v3
    with:
      path: |
        /usr/local/bin/geth         # Linux/macOS
        C:\tools\geth\geth.exe       # Windows
      key: geth-${{ runner.os }}-1.13.5

  - name: Install Geth (if not cached)
    if: steps.cache-geth.outputs.cache-hit != 'true'
    uses: ApeWorX/geth-action@v1
    with:
      version: "1.13.5"
```

### Private Network Setup

Initialize and run a private Ethereum network:

```yaml
steps:
  - uses: actions/checkout@v4

  - name: Install latest Geth
    uses: ApeWorX/geth-action@v1
    with:
      version: "latest"

  - name: Setup private network
    run: |
      # Create genesis configuration
      cat > genesis.json << EOF
      {
        "config": {
          "chainId": 12345,
          "homesteadBlock": 0,
          "eip150Block": 0,
          "eip155Block": 0,
          "eip158Block": 0,
          "byzantiumBlock": 0,
          "constantinopleBlock": 0,
          "petersburgBlock": 0,
          "istanbulBlock": 0,
          "berlinBlock": 0,
          "londonBlock": 0,
          "parisBlock": 0,
          "shanghaiBlock": 0,
          "cancunBlock": 0
        },
        "difficulty": "0x20000",
        "gasLimit": "0x8000000",
        "alloc": {
          "0x0000000000000000000000000000000000000001": {
            "balance": "1000000000000000000000"
          }
        }
      }
      EOF

      # Initialize the chain
      geth init genesis.json --datadir ./private-chain

      # Start Geth in development mode
      geth --datadir ./private-chain \
           --networkid 12345 \
           --http \
           --http.addr "127.0.0.1" \
           --http.port 8545 \
           --http.api "eth,net,web3,personal" \
           --dev \
           --dev.period 1 &

      # Wait for Geth to start
      sleep 5

      # Your tests or deployment scripts here
```

## Inputs

| Input     | Description                    | Required | Default    | Examples                            |
| --------- | ------------------------------ | -------- | ---------- | ----------------------------------- |
| `version` | The version of Geth to install | Yes      | `'latest'` | `'latest'`, `'1.13.5'`, `'v1.13.5'` |

### Version Format Support

The action intelligently handles various version formats:

- **`latest`**: Automatically fetches and installs the most recent stable release
- **Semantic version**: `1.13.5`, `1.13.4`, etc.
- **v-prefixed**: `v1.13.5`, `v1.13.4` (automatically normalized)
- **Pre-release versions**: `1.14.0-unstable` (if available)

> [!NOTE]
> On macOS, this action uses Homebrew to install Geth. Homebrew typically installs the latest stable version. Specific version requests may be ignored on macOS if they differ from the latest Homebrew version.

## Outputs

| Output    | Description                                                                    | Example  |
| --------- | ------------------------------------------------------------------------------ | -------- |
| `version` | The actual version of Geth that was installed (normalized, without 'v' prefix) | `1.13.5` |

Use the output in subsequent steps:

```yaml
steps:
  - name: Install Geth
    id: geth
    uses: ApeWorX/geth-action@v1
    with:
      version: "latest"

  - name: Use version output
    run: |
      echo "Geth version ${{ steps.geth.outputs.version }} is now installed"

      # Example: Use in artifact name
      echo "artifact-name=build-geth-${{ steps.geth.outputs.version }}" >> $GITHUB_OUTPUT
```

## Supported Platforms

| Platform       | Architecture | Tested Versions                            |
| -------------- | ------------ | ------------------------------------------ |
| Ubuntu (Linux) | x64          | ubuntu-latest, ubuntu-22.04, ubuntu-20.04  |
| macOS          | x64          | macos-latest, macos-13, macos-12           |
| Windows        | x64          | windows-latest, windows-2022, windows-2019 |

## How It Works

1. The action detects the runner's operating system
2. Installs Geth:
   - **Linux**: Downloads the appropriate binary from official sources
   - **Windows**: Queries the official Geth build container and downloads the exact matching archive. Windows archive names include an eight-character build commit, so the action discovers the filename instead of guessing a hashless URL.
   - **macOS**: Installs via Homebrew (`brew install ethereum`)
3. Extracts the archive (Linux/Windows)
4. Installs the binary to:
   - Linux: `/usr/local/bin/geth`
   - Windows: `C:\tools\geth\geth.exe`
   - macOS: Managed by Homebrew
5. Adds the installation directory to PATH
6. Verifies the installation

## Version Format

The action accepts version numbers in the following formats:

- Without 'v' prefix: `1.13.5`
- With 'v' prefix: `v1.13.5` (will be automatically normalized)

## Troubleshooting

### Version Not Found

If you encounter an error about the version not being found:

1. Check available versions at [Geth Downloads](https://geth.ethereum.org/downloads)
2. Ensure you're using a valid version number
3. Try using a stable release version

### Permission Errors on Linux/macOS

The action uses `sudo` to install Geth to `/usr/local/bin`. This should work on GitHub-hosted runners. For self-hosted runners, ensure:

1. The user has sudo privileges
2. `/usr/local/bin` is writable
3. The PATH includes `/usr/local/bin`

### Windows PATH Issues

If `geth` is not found after installation on Windows:

1. The action adds Geth to both the system PATH and GitHub Actions PATH
2. You may need to use the full path: `C:\tools\geth\geth.exe`
3. For PowerShell scripts, use: `& "C:\tools\geth\geth.exe" version`

## Development

To contribute or modify this action:

1. Fork the repository
2. Make your changes to `action.yaml`
3. Test using the provided workflow in `.github/workflows/test.yaml`
4. Submit a pull request

### Testing Locally

You can test the installation scripts locally:

```bash
# Linux/macOS
VERSION=1.13.5
# Run the installation commands from the action.yaml file

# Windows installer fixture tests (PowerShell)
./tests/Test-GethWindows.ps1
```

## License

Apache 2.0

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Issues

If you encounter any problems or have suggestions, please [open an issue](https://github.com/ApeWorX/geth-action/issues).

## Credits

This action installs [Go Ethereum (Geth)](https://github.com/ethereum/go-ethereum), the official Golang implementation of the Ethereum protocol.
