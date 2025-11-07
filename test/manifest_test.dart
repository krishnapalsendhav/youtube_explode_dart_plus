import 'package:test/test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  final videoId = VideoId('vwDqF-eqYJU');
  YoutubeExplode yt = YoutubeExplode();
  yt.videos.get(videoId).then((video) {
    print('Video Title: ${video.title}');
  });

  test('Get video details', () async {
    final video = await yt.videos.get(videoId);
    expect(video.id.toJson(), videoId.toJson());
  });

  test('Get video manifest', () async {
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [
        YoutubeApiClient.mweb,
        YoutubeApiClient.safari,
        YoutubeApiClient.mediaConnect,
      ],
    );
    expect(manifest.streams.length, greaterThan(0));
    expect(manifest.hls.length, greaterThan(0));
  });
}
