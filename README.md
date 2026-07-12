# Antigravity Companion

Antigravity Companion is a powerful mobile application and relay server designed for seamless workspace integration and conversation management.

## Overview

The Antigravity Companion project consists of two main components:
1. **Mobile App (`mobile_app/`)**: A Flutter-based mobile client that provides an intuitive interface for interacting with the relay server.
2. **Relay Server (`relay-server/`)**: A Node.js backend that handles routing, environment configurations, and integration endpoints.

## Features
- **Real-time Synchronization**: Instant updates across your workspace.
- **Project & Conversation Management**: Easily create and switch between projects.
- **Secure Integration**: Authenticated API communication via the relay server.

## Architecture Overview
The system relies on a Flutter client communicating via REST and WebSocket to a Node.js relay server, which brokers requests and manages environment states securely.

## Installation & Setup

### Relay Server Setup
Please see the [Relay Server Documentation](relay-server/README.md) for instructions on environment configuration and running the server locally.

### Mobile App Setup
Please see the [Mobile App Documentation](mobile_app/README.md) for build instructions and running the Flutter client.

## Authentication
Authentication between the mobile client and the relay server is handled via secure API keys. Ensure that your `.env` configuration on the relay server matches the expected payload from the mobile app.

## Usage
1. Start the Relay Server.
2. Launch the Mobile App on your emulator or physical device.
3. Configure the app settings to point to your Relay Server's local or production IP.

## Troubleshooting
- **Connection Issues**: Ensure both the mobile device and the relay server are on the same local network or that the server is publicly accessible.
- **Environment Errors**: Verify that your `.env` file is properly configured using `.env.example` as a template.

## Security Notes
- Never commit the `.env` file or any file containing API keys/hashes to version control.
- Ensure that the relay server is run in a secure environment and not exposed publicly without proper SSL/TLS and firewall rules.

## Roadmap
- Enhanced offline support for the mobile app.
- Additional authentication providers.
- Improved logging and diagnostics on the relay server.

## Contributing
Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes. Ensure you follow standard coding conventions for both Flutter and Node.js.

## License
[MIT License](LICENSE)
