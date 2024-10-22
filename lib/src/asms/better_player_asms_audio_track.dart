import '../locale/locale_parser.dart';

///Representation of HLS / DASH audio track
class BetterPlayerAsmsAudioTrack {
  ///Audio index in DASH xml or Id of track inside HLS playlist
  final int? id;

  ///segmentAlignment
  final bool? segmentAlignment;

  ///Description of the audio
  final String? label;

  ///Language code
  final String? language;

  ///Url of audio track
  final String? url;

  ///mimeType of the audio track
  final String? mimeType;

  ///human readable language
  final Language? localizedLanguage;

  BetterPlayerAsmsAudioTrack({
    this.id,
    this.segmentAlignment,
    this.label,
    this.language,
    this.url,
    this.mimeType,
  }) : localizedLanguage = language != null && language.isNotEmpty ? LocaleParser.getDisplayLanguage(language) : null;

  String getDisplayName() {
    return localizedLanguage?.nativeName ??
        (language != null && language!.isNotEmpty ? language : null) ??
        label ??
        id?.toString() ??
        "";
  }
}
