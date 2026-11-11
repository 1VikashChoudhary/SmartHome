/// Network and URI sanitization utilities
String sanitizeHost(String input) {
  var s = input.trim();
  if (s.isEmpty) return '';

  // If input contains a protocol scheme (e.g. http://, https://, ws://), extract the host
  if (s.contains('://')) {
    try {
      final uri = Uri.parse(s);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }
    } catch (_) {}
    s = s.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
  }

  // Strip any trailing path components or slashes (e.g. 192.168.1.100/ or 192.168.1.100/api/status)
  final slashIdx = s.indexOf('/');
  if (slashIdx != -1) {
    s = s.substring(0, slashIdx);
  }

  // Strip query parameters (?foo=bar)
  final queryIdx = s.indexOf('?');
  if (queryIdx != -1) {
    s = s.substring(0, queryIdx);
  }

  // Strip hash fragments (#...)
  final hashIdx = s.indexOf('#');
  if (hashIdx != -1) {
    s = s.substring(0, hashIdx);
  }

  return s.trim();
}
