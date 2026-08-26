import 'package:webrtc_interface/webrtc_interface.dart';

/// Stat-type filtering for [RTCPeerConnection.getStats].
extension RTCPeerConnectionStatsFilter on RTCPeerConnection {
  /// Collects stats, restricted to [statTypes] where the platform supports it.
  ///
  /// Building a full report boxes every member of every report and carries the
  /// whole tree across the platform channel; passing only the types the caller
  /// reads skips the rest before any of that happens. Falls back to the
  /// complete report where filtering is unsupported, so the result is always a
  /// superset of what was asked for.
  ///
  /// The browser builds the report itself, so there is nothing to skip here and
  /// the filter is ignored.
  Future<List<StatsReport>> getFilteredStats(
    List<String>? statTypes, [
    MediaStreamTrack? track,
  ]) =>
      getStats(track);
}
