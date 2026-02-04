# MacTorrent

**MacTorrent** is a modern, native macOS BitTorrent client built entirely with **SwiftUI**. It combines the raw power and stability of the **Transmission** backend (`transmission-daemon`) with a beautiful, "juicy" native interface designed for macOS 15+.

> **Note**: This project is currently in active development.

## ✨ Features

- **Native macOS Experience**: Built with SwiftUI for a smooth, responsive, and native look and feel.
- **Modern User Interface**: 
  - Real-time animated progress bars and speed graphs.
  - "Juicy" interactions with hover effects and smooth transitions.
  - Dark Mode and Light Mode support.
- **Powerful Backend**: Leveraging the industry-standard `transmission-daemon` for reliable and efficient torrenting.
- **Drag & Drop**: Simply drag `.torrent` files onto the window or app icon to start downloading.
- **Real-time Stats**: persistent status bar showing total download/upload speeds and active torrent count.
- **Essential Controls**: Pause, Resume, and Remove (with option to keep or delete data).
- **Magnet Link Support**: Handle magnet URIs directly.

## 🚀 Installation

1. Download the latest release (if available).
2. Drag **MacTorrent.app** to your **Applications** folder.
3. Launch the app.

## 🛠 Building from Source

To build MacTorrent yourself, you need **Xcode 16+** (on macOS 15+).

### Prerequisites

You need `transmission-daemon` installed locally to bundle it with the app (or ensure the script can find it).
```bash
brew install transmission
```

### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/tiadiff/MacTorrent.git
   cd MacTorrent
   ```

2. Run the build script:
   ```bash
   ./build_app.sh
   ```
   This script will:
   - Compile the Swift project in Release mode.
   - Create the `.app` bundle structure.
   - Bundle the `transmission-daemon` binary.
   - Generate the App Icon.
   - Sign the application (ad-hoc).

3. The compiled app will be available in the root directory as `MacTorrent.app`.

## 💻 Requirements

- **macOS 15.0** or later.
- Apple Silicon (M1/M2/M3) or Intel Mac.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is open source.
