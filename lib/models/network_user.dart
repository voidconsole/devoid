/// Network user model
/// Represents another user on the DEVOID network
class NetworkUser {
  final String publicKey;  // Ed25519 public key (base64)
  final String name;       // Display name
  final String icon;       // Icon/avatar (single character)
  final DateTime? lastSeen; // Last time user was active

  NetworkUser({
    required this.publicKey,
    required this.name,
    required this.icon,
    this.lastSeen,
  });

  /// Creates a NetworkUser from JSON (from server response)
  factory NetworkUser.fromJson(Map<String, dynamic> json) {
    final publicKey = json['public_key'] as String;
    final lastSeenMs = json['last_seen'] as int?;

    // Server sends 'username', not 'name'
    final username = json['username'] as String?;

    return NetworkUser(
      publicKey: publicKey,
      name: username ?? _generateName(publicKey),
      icon: username?.substring(0, 1) ?? publicKey.substring(0, 1),
      lastSeen: lastSeenMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
          : null,
    );
  }

  /// Converts to JSON
  Map<String, dynamic> toJson() {
    return {
      'public_key': publicKey,
      'username': name,  // Changed to match server field name
      'icon': icon,
      'last_seen': lastSeen?.millisecondsSinceEpoch,
    };
  }

  /// Generates a display name from public key
  static String _generateName(String publicKey) {
    return 'User_${publicKey.substring(0, 8)}';
  }

  /// Returns a human-readable "last seen" string
  String get lastSeenText {
    if (lastSeen == null) return 'Never';

    final now = DateTime.now();
    final difference = now.difference(lastSeen!);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return 'Over a week ago';
    }
  }

  /// Returns true if user is currently online (active within last 5 minutes)
  bool get isOnline {
    if (lastSeen == null) return false;

    final now = DateTime.now();
    final difference = now.difference(lastSeen!);

    return difference.inMinutes < 5;
  }

  @override
  String toString() {
    return 'NetworkUser(name: $name, publicKey: ${publicKey.substring(0, 12)}..., lastSeen: $lastSeenText)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is NetworkUser && other.publicKey == publicKey;
  }

  @override
  int get hashCode => publicKey.hashCode;
}