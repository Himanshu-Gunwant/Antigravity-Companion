# Antigravity Companion - Relay Server

The backend service for the Antigravity Companion system, built with Node.js.

## Purpose
The relay server acts as the central hub for routing requests, managing active workspaces, and orchestrating API interactions between the mobile app and the backend infrastructure.

## Architecture
The server is built on Node.js using WebSockets for real-time communication. It securely authenticates requests and handles data transmission between the mobile client and the workspace environment.

## Environment Variables
Create a `.env` file in the root of the `relay-server` directory using `.env.example` as a template.

Required variables:
- `API_KEY_HASH`: The bcrypt hash of your API key used for authenticating the mobile client.
- `WORKSPACE_DIR`: The absolute path to your active workspace directory.

## Setup Instructions
1. Navigate to the `relay-server` directory.
2. Install dependencies:
   ```bash
   npm install
   ```
3. **Credentials Setup**: Create a folder named `credentials/profiles` within the `relay-server` directory. Place your account access tokens (JSON files) inside this folder.
   ```bash
   mkdir -p credentials/profiles
   ```
4. **Firebase Configuration**: Ensure you have a valid Firebase service account or client configuration if your setup requires connecting to Firebase services. Place the required Firebase JSON configuration in your environment or designated configuration path as expected by your Firebase integration.

## Running Locally
To start the server for local development:
```bash
npm start
```
*Note: Depending on your `package.json` scripts, you may need to use `node index.js` or equivalent.*

## Production Deployment
For production, it is recommended to run the server using a process manager like PM2:
```bash
npm install -g pm2
pm2 start index.js --name "antigravity-relay"
```
Ensure that your server is secured behind a reverse proxy (like Nginx) with SSL termination.

## Troubleshooting
- **Cannot connect from mobile**: Check if the server is binding to `localhost` (127.0.0.1) instead of `0.0.0.0`. You may need to bind to all interfaces to allow local network traffic.
- **Authentication Failures**: Verify that the `API_KEY_HASH` matches the API key configured in your mobile app settings.
