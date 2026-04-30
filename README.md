# devoid

A zero-knowledge communication infrastructure designed to facilitate secure, invite-only messaging. The system comprises a Flutter client and a Node.js server, utilizing a blind router model where the infrastructure provider has no access to the cryptographic keys required to decrypt message content. The Node.js server is hosted on a Raspberry Pi Model 4.




## 1-> Security Model and Encryption Layers

The security architecture of devoid is composed of three distinct layers of protection, ensuring that data is secured at the transport, session, and application levels.

### 1->1 Network Transport Layer (TLS)
All external traffic is routed through an Nginx reverse proxy using TLS termination. This layer ensures that the metadata and encrypted payloads are shielded from network-level inspection during transit. The server binds exclusively to the loopback address (127.0.0.1) on port 9000, ensuring it is never directly exposed to the internet.

### 1->2 Session Layer (Ephemeral X25519)
Communication between the client and the server is secured by ephemeral sessions. Each session is established using an X25519 key exchange to derive a temporary session key via HKDF-SHA256. These keys are kept in memory and are never written to disk.

```dart
// Implementation of ephemeral session derivation
final sharedSecret = await cryptoService.deriveX25519SharedSecret(
  localKeyPair: clientEphemeralKeyPair,
  remotePublicKeyBase64: serverEphemeralPublicKey,
);

final sessionKey = await cryptoService.deriveSessionKey(
  sharedSecret: sharedSecret,
  salt: serverProvidedSalt,
  info: 'devoid-session-key-v1',
);
```

### 1->3 Application Layer (Pairwise End-to-End Encryption)
Messages are encrypted using AES-256-GCM with pairwise keys. These keys are derived independently by the sender and recipient using Elliptic Curve Diffie-Hellman (ECDH). The server only stores X25519 public keys, making it mathematically impossible for the server to derive the shared secret needed for decryption.



## 2-> Traffic Disguising and Network Presence

The system is designed to blend into standard HTTPS and WebSocket traffic to avoid detection by automated traffic analysis tools.

*   Uniform JSON Envelopes: All data, including text, binary files, and control messages, is wrapped in standard JSON envelopes.
*   Base64 Binary Encoding: Binary media is converted into Base64 strings before encryption, causing media traffic to appear identical to high-entropy text data.
*   Standard WebSocket Upgrades: Real-time communication utilizes the standard HTTP/1->1 Upgrade header for WebSockets, allowing the traffic to flow through standard Nginx configurations on ports 443 or 8443->
*   Nginx Proxying: By acting as a standard web gateway, Nginx handles the real client IP via the `X-Forwarded-For` header, ensuring the internal Node.js server only interacts with the local proxy.



## 3-> Media Sharing and Binary Management

The platform supports high-fidelity sharing of images, videos, and files without compromising the zero-knowledge model.

### 3->1 Binary Processing Path
When a user shares a file, the client performs the following operations:
1->  The file is read into a `Uint8List` binary buffer.
2->  The buffer is encoded into a Base64 string to act as the "plaintext" for the encryption engine.
3->  The string is encrypted using the pairwise AES-256-GCM key.
4->  The client enforces a 10 MB cap on raw file size to manage memory usage and network overhead.

### 3->2 Dynamic Re-decryption
To minimize the forensic footprint on the device, sent media is not stored in local message storage. Instead, the application fetches the ciphertext from the server and re-decrypts it in memory whenever the conversation history is viewed.



## 4-> Hyperminimal Interface and Theme Engine

The user interface is designed for maximum efficiency and visual clarity, removing all non-essential design elements.

### 4->1 Visual Philosophy
The UI utilizes a "content-first" approach with a custom theme engine implemented using Flutter's `ValueNotifier` system.

| Feature | Technical Implementation |
| : | : |
| Theme Switching | `ValueListenable<bool->` toggles between dark and light modes via the corner icon. |
| Page Transitions | `BlackFadeTransitionBuilder` provides a solid black background that fades content in, replacing standard slide animations. |
| State Management | Custom `InheritedWidget` (CommManagerProvider) passes singletons down the tree without third-party libraries. |

### 4->2 Real-Time Sorting
The UsersScreen dynamically manages the contact list through a combination of `ChangeNotifier` and `ListenableBuilder`.

```dart
// Sorting logic for the hyperminimal user list
void sortUsers() {
  networkUsers.sort((a, b) {
    final aUnread = commManager.hasUnreadFrom(a.publicKey);
    final bUnread = commManager.hasUnreadFrom(b.publicKey);
    if (aUnread && !bUnread) return -1;
    if (!aUnread && bUnread) return 1;
    return a.name.compareTo(b.name);
  });
}
```



## 5-> Server Architecture and Data Persistence

The backend is built as a lightweight, high-concurrency router using Node.js and SQLite.

*   SQLite WAL Mode: The database uses Write-Ahead Logging (WAL) to enable high-performance concurrent reads during heavy messaging loads.
*   Message Lifecycle: Messages are stored with a `delivered` flag. Once a message is pushed via WebSocket or retrieved via polling, it is marked as delivered and scheduled for deletion.
*   Automatic Data Pruning: A cleanup job runs hourly to purge delivered messages older than 7 days, expired sessions, and old authentication challenges.
*   Hot-Reload Hubs: Access control is managed via a `hubs.json` file that is monitored for changes every 5 seconds, allowing for real-time user partitioning without server restarts.

## 6-> The codebase
1. The application, `assets`, `lib` and  `pubspec.yaml` are flutter files and can be imported to a flutter project with sufficient permissions and setup for Android and iOS.
2. The server, in `server.js` can be run via Node.js on a Raspberry Pi served by nginx. 
