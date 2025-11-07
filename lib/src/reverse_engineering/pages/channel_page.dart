import 'package:html/parser.dart' as parser;

import '../../exceptions/exceptions.dart';
import '../../extensions/helpers_extension.dart';
import '../../retry.dart';
import '../models/initial_data.dart';
import '../models/youtube_page.dart';
import '../youtube_http_client.dart';

///
class ChannelPage extends YoutubePage<_InitialData> {
  ///
  bool get isOk => root!.querySelector('meta[property="og:url"]') != null;

  ///
  String get channelUrl => root!.querySelector('meta[property="og:url"]')?.attributes['content'] ?? '';

  ///
  String get channelId => channelUrl.substringAfter('channel/');

  ///
  String get channelTitle => root!.querySelector('meta[property="og:title"]')?.attributes['content'] ?? '';

  ///
  String get channelLogoUrl => root!.querySelector('meta[property="og:image"]')?.attributes['content'] ?? '';

  String get channelBannerUrl => initialData.bannerUrl ?? '';

  int? get subscribersCount => initialData.subscribersCount;

  ///
  ChannelPage.parse(String raw) : super(parser.parse(raw), (root) => _InitialData(root));

  ///
  static Future<ChannelPage> get(YoutubeHttpClient httpClient, String id) {
    final url = 'https://www.youtube.com/channel/$id?hl=en';

    return retry(httpClient, () async {
      final raw = await httpClient.getString(url);
      final result = ChannelPage.parse(raw);

      if (!result.isOk) {
        throw TransientFailureException('Channel page is broken');
      }
      return result;
    });
  }

  ///
  static Future<ChannelPage> getByUsername(
    YoutubeHttpClient httpClient,
    String username,
  ) {
    var url = 'https://www.youtube.com/user/$username?hl=en';

    return retry(httpClient, () async {
      try {
        final raw = await httpClient.getString(url);
        final result = ChannelPage.parse(raw);

        if (!result.isOk) {
          throw TransientFailureException('Channel page is broken');
        }
        return result;
      } on FatalFailureException catch (e) {
        if (e.statusCode != 404) {
          rethrow;
        }
        url = 'https://www.youtube.com/c/$username?hl=en';
      }
      throw FatalFailureException('', 0);
    });
  }

  ///
  static Future<ChannelPage> getByHandle(
    YoutubeHttpClient httpClient,
    String handle,
  ) {
    final url = 'https://www.youtube.com/$handle?hl=en';

    return retry(httpClient, () async {
      try {
        final raw = await httpClient.getString(url);
        final result = ChannelPage.parse(raw);

        if (!result.isOk) {
          throw TransientFailureException('Channel page is broken');
        }
        return result;
      } on FatalFailureException catch (e) {
        if (e.statusCode != 404) {
          rethrow;
        }
      }
      throw FatalFailureException('', 0);
    });
  }
}

class _InitialData extends InitialData {
  static final RegExp _subCountExp = RegExp(r'(\d+(?:\.\d+)?)(K|M|\s)');

  _InitialData(super.root);

  int? get subscribersCount {
    final header = root.get('header');

    // Try old format first (c4TabbedHeaderRenderer)
    var renderer = header?.get('c4TabbedHeaderRenderer');

    // If not found, try new format (pageHeaderRenderer)
    if (renderer == null) {
      final pageHeader = header?.get('pageHeaderRenderer');

      if (pageHeader != null) {
        // In new format, try to find subtitle which contains subscriber count
        final subtitle = pageHeader.get('subtitle');

        if (subtitle != null) {
          // Try to extract from subtitle runs
          final runs = subtitle.getList('runs');

          if (runs != null && runs.isNotEmpty) {
            for (int i = 0; i < runs.length; i++) {
              final run = runs[i];
              final text = run.getT<String>('text');

              if (text != null && text.contains('subscriber')) {
                return _parseSubscriberCount(text);
              }
            }
          }
        }

        // Try alternative path: content.pageHeaderViewModel
        final content = pageHeader.get('content');

        if (content != null) {
          final viewModel = content.get('pageHeaderViewModel');

          if (viewModel != null) {
            // Try to find subscriber count in metadata
            final metadata = viewModel.get('metadata');

            if (metadata != null) {
              // Check for contentMetadataViewModel
              final contentMetadata = metadata.get('contentMetadataViewModel');

              if (contentMetadata != null) {
                final metadataRows = contentMetadata.getList('metadataRows');

                if (metadataRows != null && metadataRows.isNotEmpty) {
                  for (int i = 0; i < metadataRows.length; i++) {
                    final row = metadataRows[i];

                    final parts = row.getList('metadataParts');
                    if (parts != null && parts.isNotEmpty) {
                      for (int j = 0; j < parts.length; j++) {
                        final part = parts[j];
                        final text = part.get('text')?.getT<String>('content');

                        if (text != null && (text.contains('subscriber') || text.contains('Subscriber'))) {
                          return _parseSubscriberCount(text);
                        }
                      }
                    }
                  }
                }
              } else {
                // Try direct metadataRows if contentMetadataViewModel doesn't exist
                final metadataRows = metadata.getList('metadataRows');

                if (metadataRows != null && metadataRows.isNotEmpty) {
                  for (int i = 0; i < metadataRows.length; i++) {
                    final row = metadataRows[i];

                    final parts = row.getList('metadataParts');
                    if (parts != null && parts.isNotEmpty) {
                      for (int j = 0; j < parts.length; j++) {
                        final part = parts[j];
                        final text = part.get('text')?.getT<String>('content');

                        if (text != null && (text.contains('subscriber') || text.contains('Subscriber'))) {
                          return _parseSubscriberCount(text);
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      return null;
    }

    // Old format parsing
    final subText = renderer.get('subscriberCountText')?.getT<String>('simpleText');

    if (subText == null) {
      return null;
    }

    return _parseSubscriberCount(subText);
  }

  int? _parseSubscriberCount(String subText) {
    final match = _subCountExp.firstMatch(subText);

    if (match == null) {
      return null;
    }

    if (match.groupCount != 2) {
      return null;
    }

    final countStr = match.group(1);
    final count = double.tryParse(countStr ?? '');

    if (count == null) {
      return null;
    }

    final multiplierText = match.group(2);

    if (multiplierText == null) {
      return null;
    }

    var multiplier = 1;
    if (multiplierText == 'K') {
      multiplier = 1000;
    } else if (multiplierText == 'M') {
      multiplier = 1000000;
    }

    final result = (count * multiplier).toInt();
    return result;
  }

  String? get bannerUrl => root.get('header')?.get('c4TabbedHeaderRenderer')?.get('banner')?.getList('thumbnails')?.first.getT<String>('url');
}
