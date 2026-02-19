# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `ArController.loadModel()` preload workflow for model placement.
- `ArController.placeModelAtScreenPosition()` for tap-based placement.
- Remote model caching on Android with hashed cache files.
- `ArController.clearModelCache()` and native cache clearing support.

### Fixed
- Android plugin namespace alignment (`com.example.flutter_ar_easy`) for reliable plugin registration.
- `ArController.placeOnTap()` now maps to a native method instead of an unimplemented channel call.

## [0.1.0] - 2026-02-19

### Added
- Initial release
- ARCore Android support
- Horizontal plane detection
- Primitive shapes (cube, sphere, cylinder)
- `ArView` widget for camera feed
- `ArController` for scene management
- `ArModelViewer` prebuilt widget
- Debug plane visualization
- Automatic lifecycle management (pause/resume)
- Event streaming (plane detected, session state, node tapped)
- Support checking (`ArController.isArSupported()`)
- Example app with 2 demos

### Known Limitations
- Android only (iOS coming in v0.3.0)
- Primitives only (3D models coming in v0.2.0)
